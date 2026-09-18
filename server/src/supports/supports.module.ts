import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { JwtModule } from '@nestjs/jwt';
import { Supports } from 'src/Entities/supports.entity';
import { SupportsController } from './supports.controller';
import { SupportsService } from './supports.service';

@Module({
    imports: [
        TypeOrmModule.forFeature([Supports]),
        JwtModule.register({
            secret: "isajfysadofbivuvhyw98474y9273459437by978wyebufiadbyfoy2887204357029384bwioeurynwiecufywoineuyaniulyr2304870510451094ncryfhnc0n139rdxn2398djcnj2381mjdc9n8ud0xs812djd",
            signOptions: { expiresIn: '24h' },
        }),
    ],
    controllers: [SupportsController],
    providers: [SupportsService],
})
export class SupportsModule {}
