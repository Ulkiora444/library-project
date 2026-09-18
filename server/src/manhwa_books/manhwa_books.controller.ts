import { Body, Controller, Delete, Get, Param, ParseIntPipe, Post, Put, UploadedFiles, UseInterceptors } from '@nestjs/common';
import { FileFieldsInterceptor } from '@nestjs/platform-express';
import { ManhwaBooksModel } from 'src/Models/manhwa_books.model';
import { ManhwaBooksService } from './manhwa_books.service';

@Controller('manhwa_books')
export class ManhwaBooksController {
    constructor(private readonly manhwaBooksService: ManhwaBooksService) {}

    @Get()
    async find() {
        return this.manhwaBooksService.find();
    }

    @Get('book/:booksId')
    async findByBook(@Param('booksId', ParseIntPipe) booksId: number) {
        return this.manhwaBooksService.findByBook(booksId);
    }

    @Get(':id')
    async findOne(@Param('id') id: number) {
        return this.manhwaBooksService.findOne(id);
    }

    @UseInterceptors(
        FileFieldsInterceptor([
            { name: 'file', maxCount: 1 },
        ])
    )
    @Post()
    async create(@Body() manhwaBooks: ManhwaBooksModel, @UploadedFiles() files: { file?: Express.Multer.File[] }) {
        return this.manhwaBooksService.create(manhwaBooks, files);
    }

    @UseInterceptors(
        FileFieldsInterceptor([
            { name: 'file', maxCount: 1 },
        ])
    )
    @Put()
    async update(@Body() manhwaBooks: ManhwaBooksModel, @UploadedFiles() files: { file?: Express.Multer.File[] }) {
        return this.manhwaBooksService.update(manhwaBooks, files);
    }

    @Delete(':id')
    async delete(@Param('id', ParseIntPipe) id: number) {
        return this.manhwaBooksService.delete(id);
    }
}
