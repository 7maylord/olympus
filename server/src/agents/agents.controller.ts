import { Controller, Get, Param, Query } from '@nestjs/common';
import { AgentsService } from './agents.service';

@Controller('agents')
export class AgentsController {
  constructor(private service: AgentsService) {}

  @Get()
  leaderboard(@Query('limit') limit?: string) {
    return this.service.leaderboard(limit ? parseInt(limit, 10) : 50);
  }

  @Get(':identifier')
  get(@Param('identifier') identifier: string) {
    return identifier.startsWith('0x')
      ? this.service.findByAddress(identifier)
      : this.service.findById(identifier);
  }
}
