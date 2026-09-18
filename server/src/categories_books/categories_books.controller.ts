import { Body, Controller, Delete, Get, Param, ParseIntPipe, Post, Put } from '@nestjs/common';
import { CategoriesBooksModel } from 'src/Models/categories_books.model';
import { CategoriesBooksService } from './categories_books.service';

@Controller('categories_books')
export class CategoriesBooksController {
    constructor(private readonly categoriesBooksService: CategoriesBooksService) {}

    @Get()
    async find() {
        return this.categoriesBooksService.find();
    }

    @Get(':id')
    async findOne(@Param('id') id: number) {
        return this.categoriesBooksService.findOne(id);
    }

    @Post()
    async create(@Body() categoriesBooks: CategoriesBooksModel) {
        return this.categoriesBooksService.create(categoriesBooks);
    }

    @Put()
    async update(@Body() categoriesBooks: CategoriesBooksModel) {
        return this.categoriesBooksService.update(categoriesBooks);
    }

    @Delete(':id')
    async delete(@Param('id', ParseIntPipe) id: number) {
        return this.categoriesBooksService.delete(id);
    }
}
