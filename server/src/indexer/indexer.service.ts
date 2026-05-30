import { Injectable, Logger, OnApplicationBootstrap } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { parseAbiItem } from 'viem';
import { Repository } from 'typeorm';
import { ChainService } from '../chain/chain.service';
import { Agent } from '../entities/agent.entity';
import { IndexerState } from '../entities/indexer-state.entity';
import { PendingSettlement } from '../entities/pending-settlement.entity';
import { Task, TaskStatus } from '../entities/task.entity';

const INDEXER_KEY   = 'main';
const POLL_INTERVAL = 4_000; // ms

@Injectable()
export class IndexerService implements OnApplicationBootstrap {
  private readonly logger = new Logger(IndexerService.name);

  constructor(
    private chain: ChainService,
    private config: ConfigService,
    @InjectRepository(Task)              private tasks: Repository<Task>,
    @InjectRepository(Agent)             private agents: Repository<Agent>,
    @InjectRepository(PendingSettlement) private settlements: Repository<PendingSettlement>,
    @InjectRepository(IndexerState)      private state: Repository<IndexerState>,
  ) {}

  async onApplicationBootstrap() {
    this.poll();
  }

  private async poll() {
    while (true) {
      try {
        await this.processNewBlocks();
      } catch (err) {
        this.logger.error('Indexer poll error', err);
      }
      await new Promise(r => setTimeout(r, POLL_INTERVAL));
    }
  }

  private async processNewBlocks() {
    const latest = await this.chain.publicClient.getBlockNumber();
    const stored = await this.state.findOne({ where: { key: INDEXER_KEY } });
    const configStart = this.config.get<bigint>('chain.startBlock') ?? 0n;
    const from = stored ? BigInt(stored.lastBlock) + 1n : configStart;

    if (from > latest) return;

    const to = latest < from + 999n ? latest : from + 999n;

    await Promise.all([
      this.indexTaskRegistry(from, to),
      this.indexAgentRegistry(from, to),
      this.indexExecutionVerifier(from, to),
    ]);

    await this.state.save({ key: INDEXER_KEY, lastBlock: to.toString() });
    this.logger.debug(`Indexed blocks ${from}–${to}`);
  }

  // ── TaskRegistry events ──────────────────────────────────────────────────

  private async indexTaskRegistry(from: bigint, to: bigint) {
    const address = this.config.get<`0x${string}`>('chain.taskRegistryAddress')!;

    const logs = await this.chain.publicClient.getLogs({
      address,
      events: [
        parseAbiItem('event TaskPosted(uint256 indexed taskId, bytes32 indexed capabilityTag, uint256 bounty, uint256 expiry)'),
        parseAbiItem('event TaskClaimed(uint256 indexed taskId, address indexed agent, uint256 claimBond)'),
        parseAbiItem('event TaskExecuted(uint256 indexed taskId, address indexed agent, bytes32 proofHash, uint256 latencyMs)'),
        parseAbiItem('event TaskExpired(uint256 indexed taskId, bool bondForfeited)'),
        parseAbiItem('event TaskDisputed(uint256 indexed taskId, address indexed challenger)'),
      ],
      fromBlock: from,
      toBlock:   to,
    });

    for (const log of logs) {
      const taskId = (log.args as any).taskId?.toString() as string;

      if (log.eventName === 'TaskPosted') {
        const { capabilityTag, bounty, expiry } = log.args as any;
        const receipt = await this.chain.publicClient.getTransactionReceipt({ hash: log.transactionHash! });

        const task = this.tasks.create({
          id:                 taskId,
          poster:             receipt.from,
          capabilityTag:      capabilityTag as string,
          bounty:             (bounty as bigint).toString(),
          expiry:             (expiry as bigint).toString(),
          status:             TaskStatus.Open,
          claimWindowSeconds: 60,
          blockNumber:        log.blockNumber!.toString(),
          txHash:             log.transactionHash!,
        });
        await this.tasks.upsert(task, ['id']);

      } else if (log.eventName === 'TaskClaimed') {
        const { agent } = log.args as any;
        const block = await this.chain.publicClient.getBlock({ blockNumber: log.blockNumber! });
        await this.tasks.update(taskId, {
          status:    TaskStatus.Claimed,
          claimedBy: agent as string,
          claimedAt: block.timestamp.toString(),
        });

      } else if (log.eventName === 'TaskExecuted') {
        const { proofHash, latencyMs } = log.args as any;
        const block = await this.chain.publicClient.getBlock({ blockNumber: log.blockNumber! });
        await this.tasks.update(taskId, {
          status:    TaskStatus.Executed,
          proofHash: proofHash as string,
          latencyMs: Number(latencyMs),
          executedAt: block.timestamp.toString(),
        });

      } else if (log.eventName === 'TaskExpired') {
        await this.tasks.update(taskId, { status: TaskStatus.Expired });

      } else if (log.eventName === 'TaskDisputed') {
        await this.tasks.update(taskId, { status: TaskStatus.Disputed });
      }
    }
  }

  // ── AgentRegistry events ─────────────────────────────────────────────────

  private async indexAgentRegistry(from: bigint, to: bigint) {
    const address = this.config.get<`0x${string}`>('chain.agentRegistryAddress')!;

    const logs = await this.chain.publicClient.getLogs({
      address,
      events: [
        parseAbiItem('event AgentRegistered(uint256 indexed tokenId, address indexed operator, string metadataURI)'),
        parseAbiItem('event FeedbackPosted(uint256 indexed agentId, bool success, uint256 reputationScore)'),
      ],
      fromBlock: from,
      toBlock:   to,
    });

    for (const log of logs) {
      const agentId = (log.args as any).tokenId?.toString() ?? (log.args as any).agentId?.toString();

      if (log.eventName === 'AgentRegistered') {
        const { operator, metadataURI } = log.args as any;
        const stake = await this.chain.publicClient.readContract({
          address,
          abi: (this.chain.agentRegistry as any).abi,
          functionName: 'agentData',
          args: [BigInt(agentId)],
        }) as any[];

        await this.agents.upsert({
          id:          agentId,
          operator:    operator as string,
          metadataUri: metadataURI as string,
          stake:       stake[2].toString(),
          blockNumber: log.blockNumber!.toString(),
        }, ['id']);

      } else if (log.eventName === 'FeedbackPosted') {
        const { success, score } = log.args as any;
        await this.agents.update(agentId, {
          reputationScore: Number(score),
          ...(success ? { tasksCompleted: () => '"tasks_completed" + 1' }
                      : { tasksFailed:    () => '"tasks_failed" + 1' }),
        });
      }
    }
  }

  // ── ExecutionVerifier events ──────────────────────────────────────────────

  private async indexExecutionVerifier(from: bigint, to: bigint) {
    const address = this.config.get<`0x${string}`>('chain.executionVerifierAddress')!;
    if (!address) return;

    const logs = await this.chain.publicClient.getLogs({
      address,
      events: [
        parseAbiItem('event ProofPending(uint256 indexed taskId, address indexed agent, bytes32 proofTxHash, uint256 disputeDeadline)'),
        parseAbiItem('event ExecutionFinalized(uint256 indexed taskId, address indexed agent)'),
        parseAbiItem('event DisputeResolved(uint256 indexed taskId, bool disputeSucceeded)'),
      ],
      fromBlock: from,
      toBlock:   to,
    });

    for (const log of logs) {
      const taskId = (log.args as any).taskId?.toString() as string;

      if (log.eventName === 'ProofPending') {
        const { agent, proofTxHash, disputeDeadline } = log.args as any;
        const pending = await this.chain.publicClient.readContract({
          address,
          abi: (this.chain.executionVerifier as any).abi,
          functionName: 'pending',
          args: [BigInt(taskId)],
        }) as any[];

        await this.settlements.upsert({
          taskId,
          proofTxHash:     proofTxHash as string,
          agent:           agent as string,
          submittedAt:     pending[2].toString(),
          disputeDeadline: (disputeDeadline as bigint).toString(),
          finalized: false,
          disputed:  false,
        }, ['taskId']);

      } else if (log.eventName === 'ExecutionFinalized') {
        await this.settlements.update({ taskId }, { finalized: true });

      } else if (log.eventName === 'DisputeResolved') {
        await this.settlements.update({ taskId }, { disputed: true });
      }
    }
  }
}
