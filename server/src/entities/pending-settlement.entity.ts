import { Column, Entity, Index, PrimaryColumn } from 'typeorm';

@Entity('pending_settlements')
export class PendingSettlement {
  @PrimaryColumn({ name: 'task_id', type: 'bigint' })
  taskId: string;

  @Column({ name: 'proof_tx_hash' })
  proofTxHash: string;

  @Index()
  @Column()
  agent: string;

  @Column({ name: 'submitted_at', type: 'bigint' })
  submittedAt: string;

  @Column({ name: 'dispute_deadline', type: 'bigint' })
  disputeDeadline: string;

  @Column({ default: false })
  finalized: boolean;

  @Column({ default: false })
  disputed: boolean;
}
