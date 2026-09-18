import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { JwtModule } from '@nestjs/jwt';
import { EpubBooks } from 'src/Entities/epub_books.entity';
import { EpubBooksController } from './epub_books.controller';
import { EpubBooksService } from './epub_books.service';
import { ImagesModule } from 'src/images/images.module';

@Module({
    imports: [
        TypeOrmModule.forFeature([EpubBooks]),
        JwtModule.register({
            secret: "isajfysadofbivuvhyw98474y9273459437by978wyebufiadbyfoy2887204357029384bwioeurynwiecufywoineuyaniulyr2304870510451094ncryfhnc0n139rdxn2398djcnj2381mjdc9n8ud0xs812djd",
            signOptions: { expiresIn: '24h' },
        }),
        ImagesModule
    ],
    controllers: [EpubBooksController],
    providers: [EpubBooksService],
})
export class EpubBooksModule {}
