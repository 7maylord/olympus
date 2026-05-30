import { Column, Entity, Index, PrimaryColumn, UpdateDateColumn } from 'typeorm';

export enum TaskStatus {
  Open     = 'Open',
  Claimed  = 'Claimed',
  Executed = 'Executed',
  Expired  = 'Expired',
  Disputed = 'Disputed',
}

@Entity('tasks')
export class Task {
  @PrimaryColumn({ type: 'bigint' })
  id: string;

  @Column()
  poster: string;

  @Index()
  @Column({ name: 'capability_tag' })
  capabilityTag: string;

  @Column({ name: 'trigger_condition', type: 'bytea', nullable: true })
  triggerCondition: Buffer | null;

  @Column({ name: 'target_action', type: 'bytea', nullable: true })
  targetAction: Buffer | null;

  @Column({ type: 'numeric', precision: 78 })
  bounty: string;

  @Column({ name: 'expiry', type: 'bigint' })
  expiry: string;

  @Column({ name: 'min_agent_reputation', type: 'int', default: 0 })
  minAgentReputation: number;

  @Index()
  @Column({ type: 'enum', enum: TaskStatus, default: TaskStatus.Open })
  status: TaskStatus;

  @Column({ name: 'claimed_by', type: 'varchar', nullable: true })
  claimedBy: string | null;

  @Column({ name: 'claimed_at', type: 'bigint', nullable: true })
  claimedAt: string | null;

  @Column({ name: 'claim_window_seconds', type: 'int' })
  claimWindowSeconds: number;

  @Column({ name: 'proof_tx_hash', type: 'varchar', nullable: true })
  proofHash: string | null;

  @Column({ name: 'executed_at', type: 'bigint', nullable: true })
  executedAt: string | null;

  @Column({ name: 'latency_ms', type: 'int', nullable: true })
  latencyMs: number | null;

  @Column({ name: 'block_number', type: 'bigint' })
  blockNumber: string;

  @Column({ name: 'tx_hash' })
  txHash: string;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt: Date;
}
