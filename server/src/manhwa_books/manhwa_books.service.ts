import { HttpException, HttpStatus, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { ManhwaBooks } from 'src/Entities/manhwa_books.entity';
import { ImagesService } from 'src/images/images.service';
import { ManhwaBooksModel } from 'src/Models/manhwa_books.model';
import { Repository } from 'typeorm';

@Injectable()
export class ManhwaBooksService {
    constructor(
        @InjectRepository(ManhwaBooks)
        private readonly manhwaBooksRepository: Repository<ManhwaBooks>,
        private readonly imagesService: ImagesService
    ) {}

    async find() {
        try {
            return {
                success: true,
                datas: await this.manhwaBooksRepository.find({
                    relations: ['books'],
                    order: { booksId: 'ASC', name: 'ASC', id: 'ASC' },
                }),
            };
        } catch {
            throw new HttpException(`Cannot GET /manhwa_books`, HttpStatus.NOT_FOUND);
        }
    }

    async findOne(id: number) {
        try {
            return {
                success: true,
                datas: await this.manhwaBooksRepository.findOne({ where: { id: id }, relations: ['books'] }),
            };
        } catch {
            throw new HttpException(`Cannot GET /manhwa_books/${id}`, HttpStatus.NOT_FOUND);
        }
    }

    async findByBook(booksId: number) {
        try {
            return {
                success: true,
                datas: await this.manhwaBooksRepository.find({
                    where: { booksId: booksId },
                    order: { id: 'ASC' },
                }),
            };
        } catch {
            throw new HttpException(`Cannot GET /manhwa_books/book/${booksId}`, HttpStatus.NOT_FOUND);
        }
    }

    async create(manhwaBooks: ManhwaBooksModel, files) {
        try {
            if (files && files.file && files.file.length) {
                const file = files.file[0];
                manhwaBooks.name = manhwaBooks.name || file.originalname;
                manhwaBooks.file = this.imagesService.saveImage(file);
            }
            return { success: true, datas: await this.manhwaBooksRepository.save(manhwaBooks) };
        } catch {
            throw new HttpException(`Cannot POST /manhwa_books`, HttpStatus.NOT_FOUND);
        }
    }

    async update(manhwaBooks: ManhwaBooksModel, files) {
        try {
            if (files && files.file && files.file.length) {
                const file = files.file[0];
                manhwaBooks.name = manhwaBooks.name || file.originalname;
                manhwaBooks.file = this.imagesService.saveImage(file);
            }
            return { success: true, datas: await this.manhwaBooksRepository.update(manhwaBooks.id, manhwaBooks) };
        } catch {
            throw new HttpException(`Cannot PUT /manhwa_books`, HttpStatus.NOT_FOUND);
        }
    }

    async delete(id: number) {
        try {
            const manhwaBooks = await this.manhwaBooksRepository.findOne({ where: { id: id } });
            if (manhwaBooks) {
                return { success: true, datas: await this.manhwaBooksRepository.delete(id) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot DELETE /manhwa_books/${id}`, HttpStatus.NOT_FOUND);
        }
    }
}
