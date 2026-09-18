import { Body, Controller, Delete, Get, Param, ParseIntPipe, Post, Put } from '@nestjs/common';
import { ReadersModel } from 'src/Models/readers.model';
import { ReadersService } from './readers.service';

@Controller('readers')
export class ReadersController {
    constructor(private readonly readersService: ReadersService) {}

    @Get()
    async find() {
        return this.readersService.find();
    }

    @Get(':id')
    async findOne(@Param('id') id: number) {
        return this.readersService.findOne(id);
    }

    @Post()
    async create(@Body() readers: ReadersModel) {
        return this.readersService.create(readers);
    }

    @Put()
    async update(@Body() readers: ReadersModel) {
        return this.readersService.update(readers);
    }

    @Delete(':id')
    async delete(@Param('id', ParseIntPipe) id: number) {
        return this.readersService.delete(id);
    }
}
