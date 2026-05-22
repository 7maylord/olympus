import { ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  app.enableCors();
  app.setGlobalPrefix('api');
  app.useGlobalPipes(new ValidationPipe({ transform: true, whitelist: true }));

  const port = app.get(ConfigService).get<number>('port') ?? 3000;
  await app.listen(port);
  console.log(`Server running on http://localhost:${port}/api`);
}

bootstrap();
