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
      useFactory: (config: ConfigService) => {
        const url = config.get<string>('database.url');
        const entities = [Task, Agent, PendingSettlement, IndexerState];
        if (url) {
          return { type: 'postgres' as const, url, entities, synchronize: true, logging: false, ssl: { rejectUnauthorized: false } };
        }
        return {
          type:        'postgres' as const,
          host:        config.get<string>('database.host'),
          port:        config.get<number>('database.port'),
          username:    config.get<string>('database.username'),
          password:    config.get<string>('database.password'),
          database:    config.get<string>('database.name'),
          entities,
          synchronize: true,
          logging:     false,
          ssl:         false,
        };
      },
    }),
  ],
})
export class DatabaseModule {}
