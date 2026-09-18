import { Body, Controller, Delete, Get, Param, ParseIntPipe, Post, Put } from '@nestjs/common';
import { RolesModel } from 'src/Models/roles.model';
import { RolesService } from './roles.service';

@Controller('roles')
export class RolesController {
    constructor(private readonly rolesService: RolesService) {}

    @Get()
    async find(){
        return this.rolesService.find();
    }

    @Get(':id')
    async findOne(@Param('id') id: number){
        return this.rolesService.findOne(id);
    }

    @Post()
    async create(@Body() roles: RolesModel){
        return this.rolesService.create(roles);
    }

    @Put()
    async update(@Body() roles: RolesModel){
        return this.rolesService.update(roles);
    }
    
    @Delete(':id')
    async delete(@Param('id', ParseIntPipe) id: number){
        return this.rolesService.delete(id);
    }
}