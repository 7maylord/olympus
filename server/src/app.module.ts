import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ScheduleModule } from '@nestjs/schedule';
import { AgentsModule } from './agents/agents.module';
import configuration from './config/configuration';
import { DatabaseModule } from './database/database.module';
import { HealthController } from './health.controller';
import { IndexerModule } from './indexer/indexer.module';
import { KeeperModule } from './keeper/keeper.module';
import { StatsModule } from './stats/stats.module';
import { TasksModule } from './tasks/tasks.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, load: [configuration] }),
    ScheduleModule.forRoot(),
    DatabaseModule,
    TasksModule,
    AgentsModule,
    IndexerModule,
    KeeperModule,
    StatsModule,
  ],
  controllers: [HealthController],
})
export class AppModule {}
