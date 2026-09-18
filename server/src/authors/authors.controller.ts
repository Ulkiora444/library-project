import { Body, Controller, Delete, Get, Param, ParseIntPipe, Post, Put, UploadedFiles, UseInterceptors } from '@nestjs/common';
import { AuthorsModel } from 'src/Models/authors.model';
import { AuthorsService } from './authors.service';
import { FileFieldsInterceptor } from '@nestjs/platform-express';

@Controller('authors')
export class AuthorsController {
    constructor(private readonly authorsService: AuthorsService) {}

    @Get()
    async find() {
        return this.authorsService.find();
    }

    @Get(':id')
    async findOne(@Param('id') id: number) {
        return this.authorsService.findOne(id);
    }
    @UseInterceptors(
        FileFieldsInterceptor([
            { name: 'image', maxCount: 1 }, 
        ])
    )
    @Post()
    async create(@Body() authors: AuthorsModel, @UploadedFiles() files: { image?: Express.Multer.File[]}) {
        return this.authorsService.create(authors, files);
    }
    @UseInterceptors(
        FileFieldsInterceptor([
            { name: 'image', maxCount: 1 }, 
        ])
    )
    @Put()
    async update(@Body() authors: AuthorsModel, @UploadedFiles() files: { image?: Express.Multer.File[]}) {
        return this.authorsService.update(authors, files);
    }

    @Delete(':id')
    async delete(@Param('id', ParseIntPipe) id: number) {
        return this.authorsService.delete(id);
    }
}
