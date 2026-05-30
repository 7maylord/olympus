import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Agent } from '../entities/agent.entity';
import { Task, TaskStatus } from '../entities/task.entity';

type AgentWithExtras = Agent & { winRate: number; totalEarned: string };

@Injectable()
export class AgentsService {
  constructor(
    @InjectRepository(Agent) private agents: Repository<Agent>,
    @InjectRepository(Task)  private tasks: Repository<Task>,
  ) {}

  private async earnedMap(operators: string[]): Promise<Map<string, string>> {
    if (operators.length === 0) return new Map();
    const rows: { operator: string; earned: string }[] = await this.tasks
      .createQueryBuilder('t')
      .select('t.claimedBy', 'operator')
      .addSelect('SUM(t.bounty)', 'earned')
      .where('t.status = :status', { status: TaskStatus.Executed })
      .andWhere('t.claimedBy IN (:...operators)', { operators })
      .groupBy('t.claimedBy')
      .getRawMany();
    return new Map(rows.map(r => [r.operator.toLowerCase(), r.earned ?? '0']));
  }

  async leaderboard(limit = 50): Promise<AgentWithExtras[]> {
    const list = await this.agents.find({
      where:  { active: true },
      order:  { reputationScore: 'DESC' },
      take:   limit,
    });

    const earned = await this.earnedMap(list.map(a => a.operator));

    return list.map(a => {
      const total   = a.tasksCompleted + a.tasksFailed;
      const winRate = total > 0 ? a.tasksCompleted / total : 0;
      return { ...a, winRate, totalEarned: earned.get(a.operator.toLowerCase()) ?? '0' };
    });
  }

  async findByAddress(address: string): Promise<AgentWithExtras> {
    const agent = await this.agents.findOne({
      where: { operator: address.toLowerCase() },
    });
    if (!agent) throw new NotFoundException(`Agent ${address} not found`);

    const earned = await this.earnedMap([agent.operator]);
    const total   = agent.tasksCompleted + agent.tasksFailed;
    const winRate = total > 0 ? agent.tasksCompleted / total : 0;
    return { ...agent, winRate, totalEarned: earned.get(agent.operator.toLowerCase()) ?? '0' };
  }

  async findById(id: string): Promise<AgentWithExtras> {
    const agent = await this.agents.findOne({ where: { id } });
    if (!agent) throw new NotFoundException(`Agent ${id} not found`);

    const earned = await this.earnedMap([agent.operator]);
    const total   = agent.tasksCompleted + agent.tasksFailed;
    const winRate = total > 0 ? agent.tasksCompleted / total : 0;
    return { ...agent, winRate, totalEarned: earned.get(agent.operator.toLowerCase()) ?? '0' };
  }
}
