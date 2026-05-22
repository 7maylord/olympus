import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Task } from '../entities/task.entity';
import { PendingSettlement } from '../entities/pending-settlement.entity';
import { TasksService } from './tasks.service';
import { TasksController } from './tasks.controller';

@Module({
  imports: [TypeOrmModule.forFeature([Task, PendingSettlement])],
  providers: [TasksService],
  controllers: [TasksController],
})
export class TasksModule {}
