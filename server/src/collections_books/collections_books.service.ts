import { HttpException, HttpStatus, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { CollectionsBooks } from 'src/Entities/collections_books.entity';
import { CollectionsBooksModel } from 'src/Models/collections_books.model';
import { Repository } from 'typeorm';

@Injectable()
export class CollectionsBooksService {
    constructor(
        @InjectRepository(CollectionsBooks)
        private readonly collectionsBooksRepository: Repository<CollectionsBooks>,
    ) {}

    async find() {
        try {
            return { success: true, datas: await this.collectionsBooksRepository.find({ relations: ['collections', 'books'] }) };
        } catch {
            throw new HttpException(`Cannot GET /collections_books`, HttpStatus.NOT_FOUND);
        }
    }

    async findOne(id: number) {
        try {
            return {
                success: true,
                datas: await this.collectionsBooksRepository.findOne({
                    where: { id: id },
                    relations: ['collections', 'books'],
                }),
            };
        } catch {
            throw new HttpException(`Cannot GET /collections_books/${id}`, HttpStatus.NOT_FOUND);
        }
    }

    async create(collectionsBooks: CollectionsBooksModel) {
        try {
            const old_collections_books = await this.collectionsBooksRepository.findOne({
                where: { collectionsId: collectionsBooks.collectionsId, booksId: collectionsBooks.booksId },
            });
            if (!old_collections_books) {
                return { success: true, datas: await this.collectionsBooksRepository.save(collectionsBooks) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot POST /collections_books`, HttpStatus.NOT_FOUND);
        }
    }

    async update(collectionsBooks: CollectionsBooksModel) {
        try {
            const old_collections_books = await this.collectionsBooksRepository.findOne({
                where: { collectionsId: collectionsBooks.collectionsId, booksId: collectionsBooks.booksId },
            });
            if (!old_collections_books) {
                return { success: true, datas: await this.collectionsBooksRepository.update(collectionsBooks.id, collectionsBooks) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot PUT /collections_books`, HttpStatus.NOT_FOUND);
        }
    }

    async delete(id: number) {
        try {
            const collectionsBooks = await this.collectionsBooksRepository.findOne({ where: { id: id } });
            if (collectionsBooks) {
                return { success: true, datas: await this.collectionsBooksRepository.delete(id) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot DELETE /collections_books/${id}`, HttpStatus.NOT_FOUND);
        }
    }
}
