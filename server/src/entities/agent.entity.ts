import { Column, Entity, Index, PrimaryColumn, UpdateDateColumn } from 'typeorm';

@Entity('agents')
export class Agent {
  @PrimaryColumn({ type: 'bigint' })
  id: string;

  @Index({ unique: true })
  @Column()
  operator: string;

  @Column({ name: 'metadata_uri' })
  metadataUri: string;

  @Column({ type: 'numeric', precision: 78 })
  stake: string;

  @Column({ name: 'reputation_score', type: 'int', default: 500 })
  reputationScore: number;

  @Column({ name: 'tasks_completed', type: 'int', default: 0 })
  tasksCompleted: number;

  @Column({ name: 'tasks_failed', type: 'int', default: 0 })
  tasksFailed: number;

  @Column({ default: true })
  active: boolean;

  @Column({ name: 'block_number', type: 'bigint' })
  blockNumber: string;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt: Date;
}
