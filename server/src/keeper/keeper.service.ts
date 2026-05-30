import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { InjectRepository } from '@nestjs/typeorm';
import { LessThan, Repository } from 'typeorm';
import { ChainService } from '../chain/chain.service';
import { PendingSettlement } from '../entities/pending-settlement.entity';
import { Task, TaskStatus } from '../entities/task.entity';

const DISPUTE_WINDOW = 3600n; // 1 hour in seconds — must match contract

@Injectable()
export class KeeperService {
  private readonly logger = new Logger(KeeperService.name);

  constructor(
    private chain: ChainService,
    @InjectRepository(Task)              private tasks: Repository<Task>,
    @InjectRepository(PendingSettlement) private settlements: Repository<PendingSettlement>,
  ) {}

  @Cron(CronExpression.EVERY_30_SECONDS)
  async expireStaleClaimsAndTasks() {
    const now = BigInt(Math.floor(Date.now() / 1000));

    const stale = await this.tasks.find({ where: { status: TaskStatus.Claimed } });
    for (const task of stale) {
      const deadline = BigInt(task.claimedAt!) + BigInt(task.claimWindowSeconds);
      if (now > deadline) {
        await this.sendExpire(task.id);
      }
    }

    const expired = await this.tasks.find({ where: { status: TaskStatus.Open } });
    for (const task of expired) {
      if (now > BigInt(task.expiry)) {
        await this.sendExpire(task.id);
      }
    }
  }

  @Cron(CronExpression.EVERY_30_SECONDS)
  async finalizeSettlements() {
    const now = BigInt(Math.floor(Date.now() / 1000));

    const ready = await this.settlements.find({
      where: { finalized: false, disputed: false },
    });

    for (const s of ready) {
      const deadline = BigInt(s.submittedAt) + DISPUTE_WINDOW;
      if (now > deadline) {
        await this.sendFinalize(s.taskId);
      }
    }
  }

  private async sendExpire(taskId: string) {
    try {
      const hash = await (this.chain.taskRegistry as any).write.expireTask(
        [BigInt(taskId)],
        { gas: 200000n },
      );
      this.logger.log(`expireTask(${taskId}) → ${hash}`);
    } catch (err: any) {
      this.logger.warn(`expireTask(${taskId}) failed: ${err.message}`);
    }
  }

  private async sendFinalize(taskId: string) {
    try {
      const hash = await (this.chain.executionVerifier as any).write.finalizeExecution(
        [BigInt(taskId)],
        { gas: 300000n },
      );
      this.logger.log(`finalizeExecution(${taskId}) → ${hash}`);
    } catch (err: any) {
      this.logger.warn(`finalizeExecution(${taskId}) failed: ${err.message}`);
    }
  }
}
