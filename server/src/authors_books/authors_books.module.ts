import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { JwtModule } from '@nestjs/jwt';
import { AuthorsBooks } from 'src/Entities/authors_books.entity';
import { AuthorsBooksController } from './authors_books.controller';
import { AuthorsBooksService } from './authors_books.service';

@Module({
    imports: [
        TypeOrmModule.forFeature([AuthorsBooks]),
        JwtModule.register({
            secret: "isajfysadofbivuvhyw98474y9273459437by978wyebufiadbyfoy2887204357029384bwioeurynwiecufywoineuyaniulyr2304870510451094ncryfhnc0n139rdxn2398djcnj2381mjdc9n8ud0xs812djd",
            signOptions: { expiresIn: '24h' },
        }),
    ],
    controllers: [AuthorsBooksController],
    providers: [AuthorsBooksService],
})
export class AuthorsBooksModule {}
