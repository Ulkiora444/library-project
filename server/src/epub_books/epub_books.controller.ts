import { Body, Controller, Delete, Get, Param, ParseIntPipe, Post, Put, UploadedFiles, UseInterceptors } from '@nestjs/common';
import { FileFieldsInterceptor } from '@nestjs/platform-express';
import { EpubBooksModel } from 'src/Models/epub_books.model';
import { EpubBooksService } from './epub_books.service';

@Controller('epub_books')
export class EpubBooksController {
    constructor(private readonly epubBooksService: EpubBooksService) {}

    @Get()
    async find() {
        return this.epubBooksService.find();
    }

    @Get(':id')
    async findOne(@Param('id') id: number) {
        return this.epubBooksService.findOne(id);
    }

    @UseInterceptors(
        FileFieldsInterceptor([
            { name: 'file', maxCount: 1 },
        ])
    )
    @Post()
    async create(@Body() epubBooks: EpubBooksModel, @UploadedFiles() files: { file?: Express.Multer.File[] }) {
        return this.epubBooksService.create(epubBooks, files);
    }

    @UseInterceptors(
        FileFieldsInterceptor([
            { name: 'file', maxCount: 1 },
        ])
    )
    @Put()
    async update(@Body() epubBooks: EpubBooksModel, @UploadedFiles() files: { file?: Express.Multer.File[] }) {
        return this.epubBooksService.update(epubBooks, files);
    }

    @Delete(':id')
    async delete(@Param('id', ParseIntPipe) id: number) {
        return this.epubBooksService.delete(id);
    }
}
