import { Body, Controller, Delete, Get, Param, ParseIntPipe, Post, Put } from '@nestjs/common';
import { AuthorsBooksModel } from 'src/Models/authors_books.model';
import { AuthorsBooksService } from './authors_books.service';

@Controller('authors_books')
export class AuthorsBooksController {
    constructor(private readonly authorsBooksService: AuthorsBooksService) {}

    @Get()
    async find() {
        return this.authorsBooksService.find();
    }

    @Get(':id')
    async findOne(@Param('id') id: number) {
        return this.authorsBooksService.findOne(id);
    }

    @Post()
    async create(@Body() authorsBooks: AuthorsBooksModel) {
        return this.authorsBooksService.create(authorsBooks);
    }

    @Put()
    async update(@Body() authorsBooks: AuthorsBooksModel) {
        return this.authorsBooksService.update(authorsBooks);
    }

    @Delete(':id')
    async delete(@Param('id', ParseIntPipe) id: number) {
        return this.authorsBooksService.delete(id);
    }
}
