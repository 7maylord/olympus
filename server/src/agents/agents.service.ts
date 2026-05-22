import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Agent } from '../entities/agent.entity';

@Injectable()
export class AgentsService {
  constructor(@InjectRepository(Agent) private agents: Repository<Agent>) {}

  async leaderboard(limit = 50): Promise<Agent[]> {
    return this.agents.find({
      where:  { active: true },
      order:  { reputationScore: 'DESC' },
      take:   limit,
    });
  }

  async findByAddress(address: string): Promise<Agent & { winRate: number }> {
    const agent = await this.agents.findOne({
      where: { operator: address.toLowerCase() },
    });
    if (!agent) throw new NotFoundException(`Agent ${address} not found`);

    const total   = agent.tasksCompleted + agent.tasksFailed;
    const winRate = total > 0 ? agent.tasksCompleted / total : 0;
    return { ...agent, winRate };
  }

  async findById(id: string): Promise<Agent & { winRate: number }> {
    const agent = await this.agents.findOne({ where: { id } });
    if (!agent) throw new NotFoundException(`Agent ${id} not found`);

    const total   = agent.tasksCompleted + agent.tasksFailed;
    const winRate = total > 0 ? agent.tasksCompleted / total : 0;
    return { ...agent, winRate };
  }
}
