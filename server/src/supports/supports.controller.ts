import { Body, Controller, Delete, Get, Param, ParseIntPipe, Post, Put } from '@nestjs/common';
import { SupportsModel } from 'src/Models/supports.model';
import { SupportsService } from './supports.service';

@Controller('supports')
export class SupportsController {
    constructor(private readonly supportsService: SupportsService) {}

    @Get()
    async find() {
        return this.supportsService.find();
    }

    @Get(':id')
    async findOne(@Param('id') id: number) {
        return this.supportsService.findOne(id);
    }

    @Post()
    async create(@Body() supports: SupportsModel) {
        return this.supportsService.create(supports);
    }

    @Put()
    async update(@Body() supports: SupportsModel) {
        return this.supportsService.update(supports);
    }

    @Delete(':id')
    async delete(@Param('id', ParseIntPipe) id: number) {
        return this.supportsService.delete(id);
    }
}
