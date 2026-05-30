import 'dotenv/config';
import { createPublicClient, createWalletClient, http, keccak256, toBytes, parseEther } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

// ── Config ────────────────────────────────────────────────────────────────────

const RPC_URL              = process.env.RPC_URL              ?? 'https://dream-rpc.somnia.network';
const API_URL              = process.env.API_URL              ?? 'http://localhost:3000';
const TASK_REGISTRY        = (process.env.TASK_REGISTRY_ADDRESS  ?? '0x8450DA4dC6b25FF15EfC4F4B3Fc0E97Fa154DF16') as `0x${string}`;
const AGENT_REGISTRY       = (process.env.AGENT_REGISTRY_ADDRESS ?? '0xC068715fB109ACecd159508A0B9079Def74202d0') as `0x${string}`;
const CAPABILITIES         = (process.env.CAPABILITIES ?? 'SWAP,TRANSFER,COMPOUND,MONITOR').split(',').map(s => s.trim());
const METADATA_URI         = process.env.METADATA_URI ?? 'https://olympus-agent.example/metadata.json';
const POLL_INTERVAL_MS     = Number(process.env.POLL_INTERVAL_MS ?? 6000);

const CLAIM_BOND  = BigInt('100000000000000');  // 0.0001 STT
const MIN_STAKE   = BigInt('10000000000000000'); // 0.01 STT

const SOMNIA_CHAIN = {
  id: 50312,
  name: 'Somnia Testnet',
  nativeCurrency: { name: 'STT', symbol: 'STT', decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] } },
} as const;

// ── ABI loading ───────────────────────────────────────────────────────────────

const __dir = dirname(fileURLToPath(import.meta.url));

function loadAbi(name: string) {
  // Try agent-bot local abis first, then server abis
  const paths = [
    join(__dir, 'abis', `${name}.json`),
    join(__dir, '../server/src/chain/abis', `${name}.json`),
    join(__dir, '../client/lib/abis', `${name}.json`),
  ];
  for (const p of paths) {
    try {
      const raw = JSON.parse(readFileSync(p, 'utf8'));
      return raw.abi ?? raw;
    } catch {}
  }
  throw new Error(`ABI not found for ${name}`);
}

const TaskRegistryABI  = loadAbi('TaskRegistry');
const AgentRegistryABI = loadAbi('AgentRegistry');

// ── Clients ───────────────────────────────────────────────────────────────────

if (!process.env.PRIVATE_KEY) {
  console.error('❌  PRIVATE_KEY not set in .env');
  process.exit(1);
}

const account = privateKeyToAccount(process.env.PRIVATE_KEY as `0x${string}`);

const publicClient = createPublicClient({ chain: SOMNIA_CHAIN, transport: http(RPC_URL) });
const walletClient = createWalletClient({ account, chain: SOMNIA_CHAIN, transport: http(RPC_URL) });

// ── Helpers ───────────────────────────────────────────────────────────────────

const log = (msg: string) => console.log(`[${new Date().toISOString()}] ${msg}`);

function capabilityTagFor(name: string): `0x${string}` {
  return keccak256(toBytes(name));
}

const capabilityTags = CAPABILITIES.map(capabilityTagFor);

async function apiGet<T>(path: string): Promise<T> {
  const res = await fetch(`${API_URL}${path}`);
  if (!res.ok) throw new Error(`API ${path} → ${res.status}`);
  return res.json() as Promise<T>;
}

// ── Agent registration ────────────────────────────────────────────────────────

async function ensureRegistered(): Promise<bigint> {
  const agentId = await publicClient.readContract({
    address: AGENT_REGISTRY,
    abi: AgentRegistryABI,
    functionName: 'agentOf',
    args: [account.address],
  }) as bigint;

  if (agentId > 0n) {
    log(`✅  Already registered — Agent ID: ${agentId}`);
    return agentId;
  }

  log('📝  Not registered yet, registering agent…');
  const hash = await walletClient.writeContract({
    address: AGENT_REGISTRY,
    abi: AgentRegistryABI,
    functionName: 'registerAgent',
    args: [METADATA_URI],
    value: MIN_STAKE,
  });
  log(`   registerAgent tx: ${hash}`);
  await publicClient.waitForTransactionReceipt({ hash });

  // Set capabilities
  const newId = await publicClient.readContract({
    address: AGENT_REGISTRY,
    abi: AgentRegistryABI,
    functionName: 'agentOf',
    args: [account.address],
  }) as bigint;

  const capHash = await walletClient.writeContract({
    address: AGENT_REGISTRY,
    abi: AgentRegistryABI,
    functionName: 'setCapabilities',
    args: [newId, capabilityTags],
  });
  await publicClient.waitForTransactionReceipt({ hash: capHash });
  log(`✅  Registered! Agent ID: ${newId} — capabilities set`);
  return newId;
}

// ── Task execution simulation ─────────────────────────────────────────────────
// In a real agent this would actually perform the swap/transfer/etc.
// Here we send a zero-value self-transfer to produce a real tx hash as proof.

async function executeTask(taskId: string, capabilityTag: string): Promise<`0x${string}`> {
  log(`   ⚙️   Executing task #${taskId} (${capabilityTag})…`);

  // Simulate work time (1–3 seconds)
  await new Promise(r => setTimeout(r, 1000 + Math.random() * 2000));

  // Send a zero-value self-transfer as "proof of execution"
  const proofHash = await walletClient.sendTransaction({
    to: account.address,
    value: 0n,
    data: `0x4f6c796d707573000000${taskId.padStart(10, '0')}` as `0x${string}`,
  });

  await publicClient.waitForTransactionReceipt({ hash: proofHash });
  log(`   ✅  Execution proof tx: ${proofHash}`);
  return proofHash;
}

// ── Main loop ─────────────────────────────────────────────────────────────────

const MAX_CONCURRENT_CLAIMS = 2;

const activeClaims = new Set<string>(); // taskIds currently in-flight
const failedTasks  = new Set<string>(); // taskIds where submitProof failed — skip for session

async function tick(agentId: bigint) {
  interface ApiTask {
    id: string;
    status: string;
    capabilityTag: string;
    bounty: string;
    poster: string;
    expiry: string;
  }

  // Don't pick up new work if we're already at the claim limit
  if (activeClaims.size >= MAX_CONCURRENT_CLAIMS) {
    log(`⏳  At claim limit (${activeClaims.size}/${MAX_CONCURRENT_CLAIMS}) — waiting`);
    return;
  }

  let tasks: ApiTask[];
  try {
    const res = await apiGet<{ items: ApiTask[] } | ApiTask[]>('/api/tasks?status=Open&limit=50');
    tasks = Array.isArray(res) ? res : res.items;
  } catch (err: any) {
    log(`⚠️   API unavailable: ${err.message}`);
    return;
  }

  const now = Math.floor(Date.now() / 1000);

  const candidates = tasks.filter(t =>
    t.status === 'Open' &&
    Number(t.expiry) > now + 60 &&
    capabilityTags.includes(t.capabilityTag as `0x${string}`) &&
    !activeClaims.has(t.id) &&
    !failedTasks.has(t.id),
  );

  if (candidates.length === 0) {
    log(`😴  No matching open tasks (checked ${tasks.length} total, ${failedTasks.size} skipped as failed)`);
    return;
  }

  // Pick highest bounty
  const task = candidates.sort((a, b) => Number(BigInt(b.bounty) - BigInt(a.bounty)))[0];
  log(`🎯  Targeting task #${task.id} — bounty: ${(Number(BigInt(task.bounty)) / 1e18).toFixed(4)} STT`);

  activeClaims.add(task.id);

  // Fire-and-forget so the poll loop isn't blocked by a single slow task
  handleTask(task).finally(() => activeClaims.delete(task.id));
}

async function handleTask(task: { id: string; capabilityTag: string }) {
  try {
    // 1. Claim
    log(`   📌  Claiming task #${task.id}…`);
    const claimHash = await walletClient.writeContract({
      address: TASK_REGISTRY,
      abi: TaskRegistryABI,
      functionName: 'claimTask',
      args: [BigInt(task.id)],
      value: CLAIM_BOND,
      gas: 300000n,
    });
    log(`   claimTask tx: ${claimHash}`);
    await publicClient.waitForTransactionReceipt({ hash: claimHash });
    log(`   ✅  Claimed task #${task.id}`);

    // 2. Execute
    const proofTxHash = await executeTask(task.id, task.capabilityTag);

    // 3. Submit proof
    log(`   📤  Submitting proof for task #${task.id}…`);
    const submitHash = await walletClient.writeContract({
      address: TASK_REGISTRY,
      abi: TaskRegistryABI,
      functionName: 'submitProof',
      args: [BigInt(task.id), proofTxHash],
      gas: 200000n,
    });
    log(`   submitProof tx: ${submitHash}`);
    await publicClient.waitForTransactionReceipt({ hash: submitHash });
    log(`🏆  Task #${task.id} proof submitted! Waiting for dispute window…`);

  } catch (err: any) {
    const msg: string = err.message ?? String(err);
    if (msg.includes('ClaimLimitReached')) {
      log(`⚠️   Task #${task.id}: claim limit reached on-chain — will retry next poll`);
      // Don't mark as failed — let it retry when a slot frees up
    } else if (msg.includes('TriggerConditionNotMet')) {
      log(`⛔  Task #${task.id}: trigger condition not met (task was posted with a price/health/block condition that isn't satisfied on-chain). Skipping for this session.`);
      failedTasks.add(task.id);
    } else {
      log(`❌  Task #${task.id} failed: ${msg}`);
      failedTasks.add(task.id);
    }
  }
}

async function main() {
  log('🤖  Olympus Agent Bot starting…');
  log(`   Wallet: ${account.address}`);
  log(`   Capabilities: ${CAPABILITIES.join(', ')}`);
  log(`   API: ${API_URL}`);
  log(`   RPC: ${RPC_URL}`);

  const balance = await publicClient.getBalance({ address: account.address });
  log(`   Balance: ${(Number(balance) / 1e18).toFixed(4)} STT`);

  if (balance < MIN_STAKE + CLAIM_BOND * 5n) {
    log('⚠️   Low balance — need at least 0.015 STT to register + claim tasks');
  }

  const agentId = await ensureRegistered();

  log(`\n🔄  Polling every ${POLL_INTERVAL_MS / 1000}s…\n`);

  // Run first tick immediately, then on interval
  await tick(agentId);
  setInterval(() => tick(agentId), POLL_INTERVAL_MS);
}

main().catch(err => {
  console.error('Fatal:', err);
  process.exit(1);
});
