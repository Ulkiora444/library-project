import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { JwtModule } from '@nestjs/jwt';
import { Categories } from 'src/Entities/categories.entity';
import { CategoriesController } from './categories.controller';
import { CategoriesService } from './categories.service';
import { ImagesModule } from 'src/images/images.module';

@Module({
    imports: [
        TypeOrmModule.forFeature([Categories]),
        JwtModule.register({
            secret: "isajfysadofbivuvhyw98474y9273459437by978wyebufiadbyfoy2887204357029384bwioeurynwiecufywoineuyaniulyr2304870510451094ncryfhnc0n139rdxn2398djcnj2381mjdc9n8ud0xs812djd",
            signOptions: { expiresIn: '24h' },
        }),
        ImagesModule
    ],
    controllers: [CategoriesController],
    providers: [CategoriesService],
})
export class CategoriesModule {}
