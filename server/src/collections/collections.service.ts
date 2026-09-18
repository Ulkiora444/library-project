import { HttpException, HttpStatus, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Collections } from 'src/Entities/collections.entity';
import { CollectionsModel } from 'src/Models/collections.model';
import { Repository } from 'typeorm';

@Injectable()
export class CollectionsService {
    constructor(
        @InjectRepository(Collections)
        private readonly collectionsRepository: Repository<Collections>,
    ) {}

    async find() {
        try {
            return { success: true, datas: await this.collectionsRepository.find() };
        } catch {
            throw new HttpException(`Cannot GET /collections`, HttpStatus.NOT_FOUND);
        }
    }

    async findOne(id: number) {
        try {
            return { success: true, datas: await this.collectionsRepository.findOne({ where: { id: id } }) };
        } catch {
            throw new HttpException(`Cannot GET /collections/${id}`, HttpStatus.NOT_FOUND);
        }
    }

    async create(collections: CollectionsModel) {
        try {
            const old_collections = await this.collectionsRepository.findOne({ where: { name: collections.name } });
            if (!old_collections) {
                return { success: true, datas: await this.collectionsRepository.save(collections) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot POST /collections`, HttpStatus.NOT_FOUND);
        }
    }

    async update(collections: CollectionsModel) {
        try {
            const old_collections = await this.collectionsRepository.findOne({ where: { name: collections.name } });
            if (!old_collections) {
                return { success: true, datas: await this.collectionsRepository.update(collections.id, collections) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot PUT /collections`, HttpStatus.NOT_FOUND);
        }
    }

    async delete(id: number) {
        try {
            const collections = await this.collectionsRepository.findOne({ where: { id: id } });
            if (collections) {
                return { success: true, datas: await this.collectionsRepository.delete(id) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot DELETE /collections/${id}`, HttpStatus.NOT_FOUND);
        }
    }
}
