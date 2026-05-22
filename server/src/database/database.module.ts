import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Agent } from '../entities/agent.entity';
import { IndexerState } from '../entities/indexer-state.entity';
import { PendingSettlement } from '../entities/pending-settlement.entity';
import { Task } from '../entities/task.entity';

@Module({
  imports: [
    TypeOrmModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        type: 'postgres',
        host:     config.get('database.host'),
        port:     config.get<number>('database.port'),
        username: config.get('database.username'),
        password: config.get('database.password'),
        database: config.get('database.name'),
        entities: [Task, Agent, PendingSettlement, IndexerState],
        synchronize: true,
        logging: false,
      }),
    }),
  ],
})
export class DatabaseModule {}
