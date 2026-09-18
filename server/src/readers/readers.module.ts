import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { JwtModule } from '@nestjs/jwt';
import { Readers } from 'src/Entities/readers.entity';
import { ReadersController } from './readers.controller';
import { ReadersService } from './readers.service';

@Module({
    imports: [
        TypeOrmModule.forFeature([Readers]),
        JwtModule.register({
            secret: "isajfysadofbivuvhyw98474y9273459437by978wyebufiadbyfoy2887204357029384bwioeurynwiecufywoineuyaniulyr2304870510451094ncryfhnc0n139rdxn2398djcnj2381mjdc9n8ud0xs812djd",
            signOptions: { expiresIn: '24h' },
        }),
    ],
    controllers: [ReadersController],
    providers: [ReadersService],
})
export class ReadersModule {}
