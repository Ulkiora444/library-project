import { HttpException, HttpStatus, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Roles } from 'src/Entities/roles.entity';
import { RolesModel } from 'src/Models/roles.model';
import { Repository } from 'typeorm';

@Injectable()
export class RolesService {
    
    constructor(
        @InjectRepository(Roles)
        private readonly rolesRepository: Repository<Roles>
    ){}

    async find(){
        try{
            return {success: true, datas: await this.rolesRepository.find()};
        }
        catch{
            throw new HttpException(`Cannot GET /roles`, HttpStatus.NOT_FOUND);
        }
    }

    async findOne(id: number){
        try{
            return {success: true, datas: await this.rolesRepository.findOne({where: {id: id}})};
        }
        catch{
            throw new HttpException(`Cannot GET /roles/${id}`, HttpStatus.NOT_FOUND);
        }
    }

    async create(roles: RolesModel){
        try{
            const old_roles = await this.rolesRepository.findOne({where: {name: roles.name}});
            if(!old_roles){
                return {success: true, datas: await this.rolesRepository.save(roles)};
            }
            return {success: false};
        }
        catch{
            throw new HttpException(`Cannot POST /roles`, HttpStatus.NOT_FOUND);
        }
    }

    async update(roles: RolesModel){
        try{
            const old_roles = await this.rolesRepository.findOne({where: {name: roles.name}});
            if(!old_roles){
                return {success: true, datas: await this.rolesRepository.update(roles.id, roles)};
            }
            return {success: false};
        }
        catch{
            throw new HttpException(`Cannot PUT /roles`, HttpStatus.NOT_FOUND);
        }
    }

    async delete(id: number){
        try{
            const roles = await this.rolesRepository.findOne({where: {id: id}});
            if(roles){
                return {success: true, datas: await this.rolesRepository.delete(id)};
            }
            return {success: false};
        }
        catch{
            throw new HttpException(`Cannot DELETE /roles/${id}`, HttpStatus.NOT_FOUND);
        }
    }
}