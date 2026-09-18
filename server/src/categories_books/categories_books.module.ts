import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { JwtModule } from '@nestjs/jwt';
import { CategoriesBooks } from 'src/Entities/categories_books.entity';
import { CategoriesBooksController } from './categories_books.controller';
import { CategoriesBooksService } from './categories_books.service';

@Module({
    imports: [
        TypeOrmModule.forFeature([CategoriesBooks]),
        JwtModule.register({
            secret: "isajfysadofbivuvhyw98474y9273459437by978wyebufiadbyfoy2887204357029384bwioeurynwiecufywoineuyaniulyr2304870510451094ncryfhnc0n139rdxn2398djcnj2381mjdc9n8ud0xs812djd",
            signOptions: { expiresIn: '24h' },
        }),
    ],
    controllers: [CategoriesBooksController],
    providers: [CategoriesBooksService],
})
export class CategoriesBooksModule {}
