import { Column, Entity, PrimaryColumn } from 'typeorm';

@Entity('indexer_state')
export class IndexerState {
  @PrimaryColumn()
  key: string;

  @Column({ name: 'last_block', type: 'bigint' })
  lastBlock: string;
}
