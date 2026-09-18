import { Body, Controller, Delete, Get, Param, ParseIntPipe, Post, Put, UploadedFiles, UseInterceptors } from '@nestjs/common';
import { FileFieldsInterceptor } from '@nestjs/platform-express';
import { PdfBooksModel } from 'src/Models/pdf_books.model';
import { PdfBooksService } from './pdf_books.service';

@Controller('pdf_books')
export class PdfBooksController {
    constructor(private readonly pdfBooksService: PdfBooksService) {}

    @Get()
    async find() {
        return this.pdfBooksService.find();
    }

    @Get(':id')
    async findOne(@Param('id') id: number) {
        return this.pdfBooksService.findOne(id);
    }

    @UseInterceptors(
        FileFieldsInterceptor([
            { name: 'file', maxCount: 1 },
        ])
    )
    @Post()
    async create(@Body() pdfBooks: PdfBooksModel, @UploadedFiles() files: { file?: Express.Multer.File[] }) {
        return this.pdfBooksService.create(pdfBooks, files);
    }

    @UseInterceptors(
        FileFieldsInterceptor([
            { name: 'file', maxCount: 1 },
        ])
    )
    @Put()
    async update(@Body() pdfBooks: PdfBooksModel, @UploadedFiles() files: { file?: Express.Multer.File[] }) {
        return this.pdfBooksService.update(pdfBooks, files);
    }

    @Delete(':id')
    async delete(@Param('id', ParseIntPipe) id: number) {
        return this.pdfBooksService.delete(id);
    }
}
