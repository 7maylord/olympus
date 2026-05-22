import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ChainModule } from '../chain/chain.module';
import { PendingSettlement } from '../entities/pending-settlement.entity';
import { Task } from '../entities/task.entity';
import { KeeperService } from './keeper.service';

@Module({
  imports: [
    ChainModule,
    TypeOrmModule.forFeature([Task, PendingSettlement]),
  ],
  providers: [KeeperService],
})
export class KeeperModule {}
