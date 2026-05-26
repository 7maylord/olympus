import TaskRegistryABI from './abis/TaskRegistry.json';
import AgentRegistryABI from './abis/AgentRegistry.json';
import BountyEscrowABI from './abis/BountyEscrow.json';
import ExecutionVerifierABI from './abis/ExecutionVerifier.json';

export const TASK_REGISTRY_ADDRESS =
  (process.env.NEXT_PUBLIC_TASK_REGISTRY_ADDRESS as `0x${string}`) ??
  '0x0000000000000000000000000000000000000000';

export const AGENT_REGISTRY_ADDRESS =
  (process.env.NEXT_PUBLIC_AGENT_REGISTRY_ADDRESS as `0x${string}`) ??
  '0x0000000000000000000000000000000000000000';

export const BOUNTY_ESCROW_ADDRESS =
  (process.env.NEXT_PUBLIC_BOUNTY_ESCROW_ADDRESS as `0x${string}`) ??
  '0x0000000000000000000000000000000000000000';

export const EXECUTION_VERIFIER_ADDRESS =
  (process.env.NEXT_PUBLIC_EXECUTION_VERIFIER_ADDRESS as `0x${string}`) ??
  '0x0000000000000000000000000000000000000000';

export { TaskRegistryABI, AgentRegistryABI, BountyEscrowABI, ExecutionVerifierABI };

// Protocol constants (mirror contract values)
export const MIN_BOUNTY = BigInt('1000000000000000');    // 0.001 ETH
export const LISTING_FEE = BigInt('100000000000000');   // 0.0001 ETH
export const CLAIM_BOND = BigInt('100000000000000');    // 0.0001 ETH
export const MIN_STAKE = BigInt('10000000000000000');   // 0.01 ETH

export const CAPABILITY_TAGS = {
  SWAP:     '0x5357415000000000000000000000000000000000000000000000000000000000',
  TRANSFER: '0x5452414e53464552000000000000000000000000000000000000000000000000',
  COMPOUND: '0x434f4d504f554e44000000000000000000000000000000000000000000000000',
  MONITOR:  '0x4d4f4e49544f5200000000000000000000000000000000000000000000000000',
} as const;

export const CAPABILITY_LABELS: Record<string, string> = {
  SWAP: 'Swap',
  TRANSFER: 'Transfer',
  COMPOUND: 'Compound',
  MONITOR: 'Monitor',
};
