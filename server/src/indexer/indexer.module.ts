import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ChainModule } from '../chain/chain.module';
import { Agent } from '../entities/agent.entity';
import { IndexerState } from '../entities/indexer-state.entity';
import { PendingSettlement } from '../entities/pending-settlement.entity';
import { Task } from '../entities/task.entity';
import { IndexerService } from './indexer.service';

@Module({
  imports: [
    ChainModule,
    TypeOrmModule.forFeature([Task, Agent, PendingSettlement, IndexerState]),
  ],
  providers: [IndexerService],
  exports:   [IndexerService],
})
export class IndexerModule {}
