import { Body, Controller, Delete, Get, Param, ParseIntPipe, Post, Put } from '@nestjs/common';
import { CollectionsBooksModel } from 'src/Models/collections_books.model';
import { CollectionsBooksService } from './collections_books.service';

@Controller('collections_books')
export class CollectionsBooksController {
    constructor(private readonly collectionsBooksService: CollectionsBooksService) {}

    @Get()
    async find() {
        return this.collectionsBooksService.find();
    }

    @Get(':id')
    async findOne(@Param('id') id: number) {
        return this.collectionsBooksService.findOne(id);
    }

    @Post()
    async create(@Body() collectionsBooks: CollectionsBooksModel) {
        return this.collectionsBooksService.create(collectionsBooks);
    }

    @Put()
    async update(@Body() collectionsBooks: CollectionsBooksModel) {
        return this.collectionsBooksService.update(collectionsBooks);
    }

    @Delete(':id')
    async delete(@Param('id', ParseIntPipe) id: number) {
        return this.collectionsBooksService.delete(id);
    }
}
