import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { PdfBooks } from 'src/Entities/pdf_books.entity';
import { ImagesModule } from 'src/images/images.module';
import { PdfBooksController } from './pdf_books.controller';
import { PdfBooksService } from './pdf_books.service';

@Module({
    imports: [TypeOrmModule.forFeature([PdfBooks]), ImagesModule],
    controllers: [PdfBooksController],
    providers: [PdfBooksService],
})
export class PdfBooksModule {}
