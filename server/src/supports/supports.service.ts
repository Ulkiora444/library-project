import { HttpException, HttpStatus, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Supports } from 'src/Entities/supports.entity';
import { SupportsModel } from 'src/Models/supports.model';
import { Repository } from 'typeorm';

@Injectable()
export class SupportsService {
    constructor(
        @InjectRepository(Supports)
        private readonly supportsRepository: Repository<Supports>,
    ) {}

    async find() {
        try {
            return { success: true, datas: await this.supportsRepository.find({ relations: ['users'] }) };
        } catch {
            throw new HttpException(`Cannot GET /supports`, HttpStatus.NOT_FOUND);
        }
    }

    async findOne(id: number) {
        try {
            return {
                success: true,
                datas: await this.supportsRepository.findOne({ where: { id: id }, relations: ['users'] }),
            };
        } catch {
            throw new HttpException(`Cannot GET /supports/${id}`, HttpStatus.NOT_FOUND);
        }
    }

    async create(supports: SupportsModel) {
        try {
            const old_supports = await this.supportsRepository.findOne({
                where: { usersId: supports.usersId, title: supports.title },
            });
            if (!old_supports) {
                return { success: true, datas: await this.supportsRepository.save(supports) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot POST /supports`, HttpStatus.NOT_FOUND);
        }
    }

    async update(supports: SupportsModel) {
        try {
            const old_supports = await this.supportsRepository.findOne({
                where: { usersId: supports.usersId, title: supports.title },
            });
            if (!old_supports) {
                return { success: true, datas: await this.supportsRepository.update(supports.id, supports) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot PUT /supports`, HttpStatus.NOT_FOUND);
        }
    }

    async delete(id: number) {
        try {
            const supports = await this.supportsRepository.findOne({ where: { id: id } });
            if (supports) {
                return { success: true, datas: await this.supportsRepository.delete(id) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot DELETE /supports/${id}`, HttpStatus.NOT_FOUND);
        }
    }
}
