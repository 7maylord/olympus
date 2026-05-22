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
    const [totalTasks, activeAgents, volumeRow] = await Promise.all([
      this.tasks.count(),
      this.agents.count({ where: { active: true } }),
      this.tasks
        .createQueryBuilder('t')
        .select('SUM(t.bounty::numeric)', 'total')
        .where('t.status = :s', { s: TaskStatus.Executed })
        .getRawOne<{ total: string }>(),
    ]);

    const byStatus = await this.tasks
      .createQueryBuilder('t')
      .select('t.status', 'status')
      .addSelect('COUNT(*)', 'count')
      .groupBy('t.status')
      .getRawMany<{ status: string; count: string }>();

    return {
      totalTasks,
      activeAgents,
      volumePaid: volumeRow?.total ?? '0',
      byStatus: Object.fromEntries(byStatus.map(r => [r.status, parseInt(r.count, 10)])),
    };
  }
}
