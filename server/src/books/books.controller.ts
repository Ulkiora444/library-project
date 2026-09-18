import { Body, Controller, Delete, Get, Param, ParseIntPipe, Post, Put, UploadedFiles, UseInterceptors } from '@nestjs/common';
import { BooksModel } from 'src/Models/books.model';
import { BooksService } from './books.service';
import { FileFieldsInterceptor } from '@nestjs/platform-express';

@Controller('books')
export class BooksController {
    constructor(private readonly booksService: BooksService) {}

    @Get()
    async find() {
        return this.booksService.find();
    }

    @Get('catalog')
    async catalog() {
        return this.booksService.catalog();
    }

    @Get(':id')
    async findOne(@Param('id') id: number) {
        return this.booksService.findOne(id);
    }

    @Post(':id/reaction')
    async reaction(@Param('id', ParseIntPipe) id: number, @Body() body: { reaction?: string; previousReaction?: string }) {
        return this.booksService.reaction(id, body);
    }

    @Put(':id/show_in_app')
    async updateShowInApp(@Param('id', ParseIntPipe) id: number, @Body() body: { show_in_app?: boolean }) {
        return this.booksService.updateShowInApp(id, body);
    }
    
    @UseInterceptors(
        FileFieldsInterceptor([
            { name: 'image', maxCount: 1 }, 
        ])
    )
    @Post()
    async create(@Body() books: BooksModel, @UploadedFiles() files: Express.Multer.File[]) {
        return this.booksService.create(books, files);
    }

    @UseInterceptors(
        FileFieldsInterceptor([
            { name: 'image', maxCount: 1 }, 
        ])
    )
    @Put()
    async update(@Body() books: BooksModel, @UploadedFiles() files: Express.Multer.File[]) {
        return this.booksService.update(books, files);
    }

    @Delete(':id')
    async delete(@Param('id', ParseIntPipe) id: number) {
        return this.booksService.delete(id);
    }
}
