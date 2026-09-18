import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { JwtModule } from '@nestjs/jwt';
import { Collections } from 'src/Entities/collections.entity';
import { CollectionsController } from './collections.controller';
import { CollectionsService } from './collections.service';

@Module({
    imports: [
        TypeOrmModule.forFeature([Collections]),
        JwtModule.register({
            secret: "isajfysadofbivuvhyw98474y9273459437by978wyebufiadbyfoy2887204357029384bwioeurynwiecufywoineuyaniulyr2304870510451094ncryfhnc0n139rdxn2398djcnj2381mjdc9n8ud0xs812djd",
            signOptions: { expiresIn: '24h' },
        }),
    ],
    controllers: [CollectionsController],
    providers: [CollectionsService],
})
export class CollectionsModule {}
