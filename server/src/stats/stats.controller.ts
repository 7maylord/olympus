import { Controller, Get } from '@nestjs/common';
import { StatsService } from './stats.service';

@Controller('stats')
export class StatsController {
  constructor(private service: StatsService) {}

  @Get()
  global() {
    return this.service.global();
  }
}
