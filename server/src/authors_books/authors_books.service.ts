import { HttpException, HttpStatus, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { AuthorsBooks } from 'src/Entities/authors_books.entity';
import { AuthorsBooksModel } from 'src/Models/authors_books.model';
import { Repository } from 'typeorm';

@Injectable()
export class AuthorsBooksService {
    constructor(
        @InjectRepository(AuthorsBooks)
        private readonly authorsBooksRepository: Repository<AuthorsBooks>,
    ) {}

    async find() {
        try {
            return { success: true, datas: await this.authorsBooksRepository.find({ relations: ['authors', 'books'] }) };
        } catch {
            throw new HttpException(`Cannot GET /authors_books`, HttpStatus.NOT_FOUND);
        }
    }

    async findOne(id: number) {
        try {
            return {
                success: true,
                datas: await this.authorsBooksRepository.findOne({ where: { id: id }, relations: ['authors', 'books'] }),
            };
        } catch {
            throw new HttpException(`Cannot GET /authors_books/${id}`, HttpStatus.NOT_FOUND);
        }
    }

    async create(authorsBooks: AuthorsBooksModel) {
        try {
            const old_authors_books = await this.authorsBooksRepository.findOne({
                where: { authorsId: authorsBooks.authorsId, booksId: authorsBooks.booksId },
            });
            if (!old_authors_books) {
                return { success: true, datas: await this.authorsBooksRepository.save(authorsBooks) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot POST /authors_books`, HttpStatus.NOT_FOUND);
        }
    }

    async update(authorsBooks: AuthorsBooksModel) {
        try {
            const old_authors_books = await this.authorsBooksRepository.findOne({
                where: { authorsId: authorsBooks.authorsId, booksId: authorsBooks.booksId },
            });
            if (!old_authors_books) {
                return { success: true, datas: await this.authorsBooksRepository.update(authorsBooks.id, authorsBooks) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot PUT /authors_books`, HttpStatus.NOT_FOUND);
        }
    }

    async delete(id: number) {
        try {
            const authorsBooks = await this.authorsBooksRepository.findOne({ where: { id: id } });
            if (authorsBooks) {
                return { success: true, datas: await this.authorsBooksRepository.delete(id) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot DELETE /authors_books/${id}`, HttpStatus.NOT_FOUND);
        }
    }
}
