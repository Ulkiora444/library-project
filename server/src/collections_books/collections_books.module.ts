import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { JwtModule } from '@nestjs/jwt';
import { CollectionsBooks } from 'src/Entities/collections_books.entity';
import { CollectionsBooksController } from './collections_books.controller';
import { CollectionsBooksService } from './collections_books.service';

@Module({
    imports: [
        TypeOrmModule.forFeature([CollectionsBooks]),
        JwtModule.register({
            secret: "isajfysadofbivuvhyw98474y9273459437by978wyebufiadbyfoy2887204357029384bwioeurynwiecufywoineuyaniulyr2304870510451094ncryfhnc0n139rdxn2398djcnj2381mjdc9n8ud0xs812djd",
            signOptions: { expiresIn: '24h' },
        }),
    ],
    controllers: [CollectionsBooksController],
    providers: [CollectionsBooksService],
})
export class CollectionsBooksModule {}
