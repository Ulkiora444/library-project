import { Body, Controller, Delete, Get, Param, ParseIntPipe, Post, Put, UploadedFiles, UseInterceptors } from '@nestjs/common';
import { CategoriesModel } from 'src/Models/categories.model';
import { CategoriesService } from './categories.service';
import { FileFieldsInterceptor } from '@nestjs/platform-express';

@Controller('categories')
export class CategoriesController {
    constructor(private readonly categoriesService: CategoriesService) {}

    @Get()
    async find() {
        return this.categoriesService.find();
    }

    @Get(':id')
    async findOne(@Param('id') id: number) {
        return this.categoriesService.findOne(id);
    }
    
    @UseInterceptors(
        FileFieldsInterceptor([
            { name: 'image', maxCount: 1 }, 
        ])
    )
    @Post()
    async create(@Body() categories: CategoriesModel, @UploadedFiles() files: Express.Multer.File[]) {
        return this.categoriesService.create(categories, files);
    }

    @UseInterceptors(
        FileFieldsInterceptor([
            { name: 'image', maxCount: 1 }, 
        ])
    )
    @Put()
    async update(@Body() categories: CategoriesModel, @UploadedFiles() files: Express.Multer.File[]) {
        return this.categoriesService.update(categories, files);
    }

    @Delete(':id')
    async delete(@Param('id', ParseIntPipe) id: number) {
        return this.categoriesService.delete(id);
    }
}
