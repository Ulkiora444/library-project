import { HttpException, HttpStatus, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { EpubBooks } from 'src/Entities/epub_books.entity';
import { ImagesService } from 'src/images/images.service';
import { EpubBooksModel } from 'src/Models/epub_books.model';
import { Repository } from 'typeorm';

@Injectable()
export class EpubBooksService {
    constructor(
        @InjectRepository(EpubBooks)
        private readonly epubBooksRepository: Repository<EpubBooks>,
        private readonly imagesService: ImagesService
    ) {}

    async find() {
        try {
            return { success: true, datas: await this.epubBooksRepository.find({ relations: ['books'] }) };
        } catch {
            throw new HttpException(`Cannot GET /epub_books`, HttpStatus.NOT_FOUND);
        }
    }

    async findOne(id: number) {
        try {
            return {
                success: true,
                datas: await this.epubBooksRepository.findOne({ where: { id: id }, relations: ['books'] }),
            };
        } catch {
            throw new HttpException(`Cannot GET /epub_books/${id}`, HttpStatus.NOT_FOUND);
        }
    }

    async create(epubBooks: EpubBooksModel, files) {
        try {
            const old_epub_books = await this.epubBooksRepository.findOne({
                where: { booksId: epubBooks.booksId },
            });
            if (!old_epub_books) {
                if(files && files.file && files.file.length){
                    epubBooks.file = this.imagesService.saveEpub(files.file[0]);
                }
                return { success: true, datas: await this.epubBooksRepository.save(epubBooks) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot POST /epub_books`, HttpStatus.NOT_FOUND);
        }
    }

    async update(epubBooks: EpubBooksModel, files) {
        try {
            const old_epub_books = await this.epubBooksRepository.findOne({
                where: { booksId: epubBooks.booksId },
            });
            if (!old_epub_books || Number(old_epub_books.id) === Number(epubBooks.id)) {
                if(files && files.file && files.file.length){
                    epubBooks.file = this.imagesService.saveEpub(files.file[0]);
                }
                return { success: true, datas: await this.epubBooksRepository.update(epubBooks.id, epubBooks) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot PUT /epub_books`, HttpStatus.NOT_FOUND);
        }
    }

    async delete(id: number) {
        try {
            const epubBooks = await this.epubBooksRepository.findOne({ where: { id: id } });
            if (epubBooks) {
                return { success: true, datas: await this.epubBooksRepository.delete(id) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot DELETE /epub_books/${id}`, HttpStatus.NOT_FOUND);
        }
    }
}
