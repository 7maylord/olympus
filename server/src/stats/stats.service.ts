import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Agent } from '../entities/agent.entity';
import { Task, TaskStatus } from '../entities/task.entity';

@Injectable()
export class StatsService {
  constructor(
    @InjectRepository(Task)  private tasks:  Repository<Task>,
    @InjectRepository(Agent) private agents: Repository<Agent>,
  ) {}

  async global() {
    const [totalTasks, totalAgents] = await Promise.all([
      this.tasks.count(),
      this.agents.count(),
    ]);

    const [byStatus, bountyRow] = await Promise.all([
      this.tasks
        .createQueryBuilder('t')
        .select('t.status', 'status')
        .addSelect('COUNT(*)', 'count')
        .groupBy('t.status')
        .getRawMany<{ status: string; count: string }>(),

      this.tasks
        .createQueryBuilder('t')
        .select('COALESCE(SUM(t.bounty::numeric), 0)', 'total')
        .getRawOne<{ total: string }>(),
    ]);

    const statusMap = Object.fromEntries(
      byStatus.map(r => [r.status, parseInt(r.count, 10)]),
    );

    const openTasks      = statusMap[TaskStatus.Open]     ?? 0;
    const executedTasks  = statusMap[TaskStatus.Executed] ?? 0;
    const completionRate = totalTasks > 0
      ? Math.round((executedTasks / totalTasks) * 100)
      : 0;

    return {
      totalTasks,
      openTasks,
      totalAgents,
      totalBounties: bountyRow?.total ?? '0',
      completionRate,
      avgClaimTimeMs: 0,
    };
  }
}
