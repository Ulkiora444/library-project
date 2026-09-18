import { HttpException, HttpStatus, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { CategoriesBooks } from 'src/Entities/categories_books.entity';
import { CategoriesBooksModel } from 'src/Models/categories_books.model';
import { Repository } from 'typeorm';

@Injectable()
export class CategoriesBooksService {
    constructor(
        @InjectRepository(CategoriesBooks)
        private readonly categoriesBooksRepository: Repository<CategoriesBooks>,
    ) {}

    async find() {
        try {
            return { success: true, datas: await this.categoriesBooksRepository.find({ relations: ['categories', 'books'] }) };
        } catch {
            throw new HttpException(`Cannot GET /categories_books`, HttpStatus.NOT_FOUND);
        }
    }

    async findOne(id: number) {
        try {
            return {
                success: true,
                datas: await this.categoriesBooksRepository.findOne({
                    where: { id: id },
                    relations: ['categories', 'books'],
                }),
            };
        } catch {
            throw new HttpException(`Cannot GET /categories_books/${id}`, HttpStatus.NOT_FOUND);
        }
    }

    async create(categoriesBooks: CategoriesBooksModel) {
        try {
            const old_categories_books = await this.categoriesBooksRepository.findOne({
                where: { categoreisId: categoriesBooks.categoreisId, booksId: categoriesBooks.booksId },
            });
            if (!old_categories_books) {
                return { success: true, datas: await this.categoriesBooksRepository.save(categoriesBooks) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot POST /categories_books`, HttpStatus.NOT_FOUND);
        }
    }

    async update(categoriesBooks: CategoriesBooksModel) {
        try {
            const old_categories_books = await this.categoriesBooksRepository.findOne({
                where: { categoreisId: categoriesBooks.categoreisId, booksId: categoriesBooks.booksId },
            });
            if (!old_categories_books) {
                return { success: true, datas: await this.categoriesBooksRepository.update(categoriesBooks.id, categoriesBooks) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot PUT /categories_books`, HttpStatus.NOT_FOUND);
        }
    }

    async delete(id: number) {
        try {
            const categoriesBooks = await this.categoriesBooksRepository.findOne({ where: { id: id } });
            if (categoriesBooks) {
                return { success: true, datas: await this.categoriesBooksRepository.delete(id) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot DELETE /categories_books/${id}`, HttpStatus.NOT_FOUND);
        }
    }
}
