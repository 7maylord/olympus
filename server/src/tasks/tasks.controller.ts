import { Controller, Get, Param, Query } from '@nestjs/common';
import { TaskStatus } from '../entities/task.entity';
import { TaskFilter, TasksService } from './tasks.service';

@Controller('tasks')
export class TasksController {
  constructor(private service: TasksService) {}

  @Get()
  list(@Query() query: {
    status?:        string;
    capabilityTag?: string;
    poster?:        string;
    minBounty?:     string;
    page?:          string;
    limit?:         string;
  }) {
    const filter: TaskFilter = {
      status:        query.status as TaskStatus | undefined,
      capabilityTag: query.capabilityTag,
      poster:        query.poster,
      minBounty:     query.minBounty,
      page:          query.page  ? parseInt(query.page,  10) : undefined,
      limit:         query.limit ? parseInt(query.limit, 10) : undefined,
    };
    return this.service.findAll(filter);
  }

  @Get(':id')
  get(@Param('id') id: string) {
    return this.service.findOne(id);
  }
}
