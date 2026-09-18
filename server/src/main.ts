import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import * as cookieParser from 'cookie-parser';
import * as fs from 'fs';
import * as express from 'express';
import { resolve } from 'path';

// const httpsOptions = {
//   key: fs.readFileSync('./public/ssl/localhost.pem'),
//   cert: fs.readFileSync('./public/ssl/cert.pem'),
// };

async function bootstrap() {
  const app = await NestFactory.create(AppModule);//, {httpsOptions,}
  app.enableCors();
  app.use(express.static(resolve(__dirname, '..', '..', 'public', 'images'), {
    index: false,
    fallthrough: true,
  }));
  app.setGlobalPrefix('api');
  app.use(cookieParser());
  await app.listen(3000);
}
bootstrap();
