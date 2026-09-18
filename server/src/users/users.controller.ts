import { Body, Controller, Delete, Get, Param, ParseIntPipe, Post, Put, UploadedFiles, UseInterceptors } from '@nestjs/common';
import { UsersModel } from 'src/Models/users.model';
import { UsersService } from './users.service';
import { FileFieldsInterceptor } from '@nestjs/platform-express';

@Controller('users')
export class UsersController {
    constructor(private readonly usersService: UsersService) {}

    @Get()
    async find() {
        return this.usersService.find();
    }

    @Post('login')
    async login(@Body() body: { login: string; password: string }) {
        return this.usersService.login(body.login, body.password);
    }

    @Get(':id')
    async findOne(@Param('id') id: number) {
        return this.usersService.findOne(id);
    }
    
    @UseInterceptors(
        FileFieldsInterceptor([
            { name: 'image', maxCount: 1 }, 
        ])
    )
    @Post()
    async create(@Body() users: UsersModel, @UploadedFiles() files: { image?: Express.Multer.File[]}) {
        return this.usersService.create(users, files);
    }

    @UseInterceptors(
        FileFieldsInterceptor([
            { name: 'image', maxCount: 1 }, 
        ])
    )
    @Put()
    async update(@Body() users: UsersModel, @UploadedFiles() files: { image?: Express.Multer.File[]}) {
        return this.usersService.update(users, files);
    }

    @Delete(':id')
    async delete(@Param('id', ParseIntPipe) id: number) {
        return this.usersService.delete(id);
    }
}
