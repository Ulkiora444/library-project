import { HttpException, HttpStatus, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { MangaBooks } from 'src/Entities/manga_books.entity';
import { ImagesService } from 'src/images/images.service';
import { MangaBooksModel } from 'src/Models/manga_books.model';
import { Repository } from 'typeorm';

@Injectable()
export class MangaBooksService {
    constructor(
        @InjectRepository(MangaBooks)
        private readonly mangaBooksRepository: Repository<MangaBooks>,
        private readonly imagesService: ImagesService
    ) {}

    async find() {
        try {
            return {
                success: true,
                datas: await this.mangaBooksRepository.find({
                    relations: ['books'],
                    order: { booksId: 'ASC', name: 'ASC', id: 'ASC' },
                }),
            };
        } catch {
            throw new HttpException(`Cannot GET /manga_books`, HttpStatus.NOT_FOUND);
        }
    }

    async findOne(id: number) {
        try {
            return {
                success: true,
                datas: await this.mangaBooksRepository.findOne({ where: { id: id }, relations: ['books'] }),
            };
        } catch {
            throw new HttpException(`Cannot GET /manga_books/${id}`, HttpStatus.NOT_FOUND);
        }
    }

    async findByBook(booksId: number) {
        try {
            return {
                success: true,
                datas: await this.mangaBooksRepository.find({
                    where: { booksId: booksId },
                    order: { id: 'ASC' },
                }),
            };
        } catch {
            throw new HttpException(`Cannot GET /manga_books/book/${booksId}`, HttpStatus.NOT_FOUND);
        }
    }

    async create(mangaBooks: MangaBooksModel, files) {
        try {
            if (files && files.file && files.file.length) {
                const file = files.file[0];
                mangaBooks.name = mangaBooks.name || file.originalname;
                mangaBooks.file = this.imagesService.saveImage(file);
            }
            return { success: true, datas: await this.mangaBooksRepository.save(mangaBooks) };
        } catch {
            throw new HttpException(`Cannot POST /manga_books`, HttpStatus.NOT_FOUND);
        }
    }

    async update(mangaBooks: MangaBooksModel, files) {
        try {
            if (files && files.file && files.file.length) {
                const file = files.file[0];
                mangaBooks.name = mangaBooks.name || file.originalname;
                mangaBooks.file = this.imagesService.saveImage(file);
            }
            return { success: true, datas: await this.mangaBooksRepository.update(mangaBooks.id, mangaBooks) };
        } catch {
            throw new HttpException(`Cannot PUT /manga_books`, HttpStatus.NOT_FOUND);
        }
    }

    async delete(id: number) {
        try {
            const mangaBooks = await this.mangaBooksRepository.findOne({ where: { id: id } });
            if (mangaBooks) {
                return { success: true, datas: await this.mangaBooksRepository.delete(id) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot DELETE /manga_books/${id}`, HttpStatus.NOT_FOUND);
        }
    }
}
