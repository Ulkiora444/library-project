import { Body, Controller, Delete, Get, Param, ParseIntPipe, Post, Put } from '@nestjs/common';
import { CollectionsModel } from 'src/Models/collections.model';
import { CollectionsService } from './collections.service';

@Controller('collections')
export class CollectionsController {
    constructor(private readonly collectionsService: CollectionsService) {}

    @Get()
    async find() {
        return this.collectionsService.find();
    }

    @Get(':id')
    async findOne(@Param('id') id: number) {
        return this.collectionsService.findOne(id);
    }

    @Post()
    async create(@Body() collections: CollectionsModel) {
        return this.collectionsService.create(collections);
    }

    @Put()
    async update(@Body() collections: CollectionsModel) {
        return this.collectionsService.update(collections);
    }

    @Delete(':id')
    async delete(@Param('id', ParseIntPipe) id: number) {
        return this.collectionsService.delete(id);
    }
}
