import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { FindManyOptions, Repository } from 'typeorm';
import { PendingSettlement } from '../entities/pending-settlement.entity';
import { Task, TaskStatus } from '../entities/task.entity';

export interface TaskFilter {
  status?:         TaskStatus;
  capabilityTag?:  string;
  poster?:         string;
  minBounty?:      string;
  page?:           number;
  limit?:          number;
}

@Injectable()
export class TasksService {
  constructor(
    @InjectRepository(Task)              private tasks: Repository<Task>,
    @InjectRepository(PendingSettlement) private settlements: Repository<PendingSettlement>,
  ) {}

  async findAll(filter: TaskFilter) {
    const { status, capabilityTag, poster, minBounty, page = 1, limit = 20 } = filter;

    const qb = this.tasks.createQueryBuilder('t');

    if (status)        qb.andWhere('t.status = :status', { status });
    if (capabilityTag) qb.andWhere('t.capability_tag = :capabilityTag', { capabilityTag });
    if (poster)        qb.andWhere('LOWER(t.poster) = LOWER(:poster)', { poster });
    if (minBounty)     qb.andWhere('t.bounty::numeric >= :minBounty', { minBounty });

    qb.orderBy('t.id', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);

    const [items, total] = await qb.getManyAndCount();
    return { items, total, page, limit };
  }

  async findOne(id: string) {
    const task = await this.tasks.findOne({ where: { id } });
    if (!task) throw new NotFoundException(`Task ${id} not found`);

    const settlement = await this.settlements.findOne({ where: { taskId: id } });
    return { ...task, settlement: settlement ?? null };
  }

  async findByStatus(status: TaskStatus): Promise<Task[]> {
    return this.tasks.find({ where: { status } });
  }
}
