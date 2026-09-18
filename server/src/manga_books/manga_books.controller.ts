import { Body, Controller, Delete, Get, Param, ParseIntPipe, Post, Put, UploadedFiles, UseInterceptors } from '@nestjs/common';
import { MangaBooksModel } from 'src/Models/manga_books.model';
import { MangaBooksService } from './manga_books.service';
import { FileFieldsInterceptor } from '@nestjs/platform-express';

@Controller('manga_books')
export class MangaBooksController {
    constructor(private readonly mangaBooksService: MangaBooksService) {}

    @Get()
    async find() {
        return this.mangaBooksService.find();
    }

    @Get('book/:booksId')
    async findByBook(@Param('booksId', ParseIntPipe) booksId: number) {
        return this.mangaBooksService.findByBook(booksId);
    }

    @Get(':id')
    async findOne(@Param('id') id: number) {
        return this.mangaBooksService.findOne(id);
    }

    @UseInterceptors(
        FileFieldsInterceptor([
            { name: 'file', maxCount: 1 },
        ])
    )
    @Post()
    async create(@Body() mangaBooks: MangaBooksModel, @UploadedFiles() files: { file?: Express.Multer.File[] }) {
        return this.mangaBooksService.create(mangaBooks, files);
    }

    @UseInterceptors(
        FileFieldsInterceptor([
            { name: 'file', maxCount: 1 },
        ])
    )
    @Put()
    async update(@Body() mangaBooks: MangaBooksModel, @UploadedFiles() files: { file?: Express.Multer.File[] }) {
        return this.mangaBooksService.update(mangaBooks, files);
    }

    @Delete(':id')
    async delete(@Param('id', ParseIntPipe) id: number) {
        return this.mangaBooksService.delete(id);
    }
}
