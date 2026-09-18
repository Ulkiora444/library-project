import { HttpException, HttpStatus, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Users } from 'src/Entities/users.entity';
import { ImagesService } from 'src/images/images.service';
import { UsersModel } from 'src/Models/users.model';
import { Repository } from 'typeorm';

@Injectable()
export class UsersService {
    constructor(
        @InjectRepository(Users)
        private readonly usersRepository: Repository<Users>,
        private readonly imagesService: ImagesService
    ) {}

    async find() {
        try {
            return { success: true, datas: await this.usersRepository.find({ relations: ['roles'] }) };
        } catch {
            throw new HttpException(`Cannot GET /users`, HttpStatus.NOT_FOUND);
        }
    }

    async findOne(id: number) {
        try {
            return {
                success: true,
                datas: await this.usersRepository.findOne({ where: { id: id }, relations: ['roles'] }),
            };
        } catch {
            throw new HttpException(`Cannot GET /users/${id}`, HttpStatus.NOT_FOUND);
        }
    }

    async login(login: string, password: string) {
        try {
            const user = await this.usersRepository.findOne({
                where: [
                    { email: login, password: password },
                    { username: login, password: password },
                    { phone: login, password: password },
                ],
                relations: ['roles'],
            });

            if (!user) {
                return { success: false };
            }

            const { password: _password, ...userWithoutPassword } = user;
            return { success: true, datas: userWithoutPassword };
        } catch {
            throw new HttpException(`Cannot POST /users/login`, HttpStatus.NOT_FOUND);
        }
    }

    async create(users: UsersModel, files) {
        try {
            const old_users = await this.usersRepository.findOne({ where: { username: users.username } });
            if (!old_users || Number(old_users.id) === Number(users.id)) {
                if(files && files.image && files.image.length){
                    users.image = this.imagesService.saveImage(files.image[0]);
                }
                return { success: true, datas: await this.usersRepository.save(users) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot POST /users`, HttpStatus.NOT_FOUND);
        }
    }

    async update(users: UsersModel, files) {
        try {
            const old_users = await this.usersRepository.findOne({ where: { username: users.username } });
            if (!old_users) {
                if(files && files.image && files.image.length){
                    users.image = this.imagesService.saveImage(files.image[0]);
                }
                return { success: true, datas: await this.usersRepository.update(users.id, users) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot PUT /users`, HttpStatus.NOT_FOUND);
        }
    }

    async delete(id: number) {
        try {
            const users = await this.usersRepository.findOne({ where: { id: id } });
            if (users) {
                return { success: true, datas: await this.usersRepository.delete(id) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot DELETE /users/${id}`, HttpStatus.NOT_FOUND);
        }
    }
}
