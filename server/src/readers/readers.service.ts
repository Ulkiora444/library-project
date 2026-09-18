import { HttpException, HttpStatus, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Readers } from 'src/Entities/readers.entity';
import { ReadersModel } from 'src/Models/readers.model';
import { Repository } from 'typeorm';

@Injectable()
export class ReadersService {
    constructor(
        @InjectRepository(Readers)
        private readonly readersRepository: Repository<Readers>,
    ) {}

    async find() {
        try {
            return { success: true, datas: await this.readersRepository.find() };
        } catch {
            throw new HttpException(`Cannot GET /readers`, HttpStatus.NOT_FOUND);
        }
    }

    async findOne(id: number) {
        try {
            return { success: true, datas: await this.readersRepository.findOne({ where: { id: id } }) };
        } catch {
            throw new HttpException(`Cannot GET /readers/${id}`, HttpStatus.NOT_FOUND);
        }
    }

    async create(readers: ReadersModel) {
        try {
            const old_readers = await this.readersRepository.findOne({ where: { name: readers.name } });
            if (!old_readers) {
                return { success: true, datas: await this.readersRepository.save(readers) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot POST /readers`, HttpStatus.NOT_FOUND);
        }
    }

    async update(readers: ReadersModel) {
        try {
            const old_readers = await this.readersRepository.findOne({ where: { name: readers.name } });
            if (!old_readers) {
                return { success: true, datas: await this.readersRepository.update(readers.id, readers) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot PUT /readers`, HttpStatus.NOT_FOUND);
        }
    }

    async delete(id: number) {
        try {
            const readers = await this.readersRepository.findOne({ where: { id: id } });
            if (readers) {
                return { success: true, datas: await this.readersRepository.delete(id) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot DELETE /readers/${id}`, HttpStatus.NOT_FOUND);
        }
    }
}
