import { HttpException, HttpStatus, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Authors } from 'src/Entities/authors.entity';
import { ImagesService } from 'src/images/images.service';
import { AuthorsModel } from 'src/Models/authors.model';
import { Repository } from 'typeorm';

@Injectable()
export class AuthorsService {
    constructor(
        @InjectRepository(Authors)
        private readonly authorsRepository: Repository<Authors>,
        private readonly imagesService: ImagesService
    ) {}

    async find() {
        try {
            return { success: true, datas: await this.authorsRepository.find() };
        } catch {
            throw new HttpException(`Cannot GET /authors`, HttpStatus.NOT_FOUND);
        }
    }

    async findOne(id: number) {
        try {
            return { success: true, datas: await this.authorsRepository.findOne({ where: { id: id } }) };
        } catch {
            throw new HttpException(`Cannot GET /authors/${id}`, HttpStatus.NOT_FOUND);
        }
    }

    async create(authors: AuthorsModel, files) {
        try {
            const old_authors = await this.authorsRepository.findOne({ where: { name: authors.name } });
            if (!old_authors || Number(old_authors.id) === Number(authors.id)) {
                if(files && files.image && files.image.length){
                    authors.image = this.imagesService.saveImage(files.image[0]);
                }
                authors.likes_total = 0;
                authors.do_not_likes_total = 0;
                return { success: true, datas: await this.authorsRepository.save(authors) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot POST /authors`, HttpStatus.NOT_FOUND);
        }
    }

    async update(authors: AuthorsModel, files) {
        try {
            const old_authors = await this.authorsRepository.findOne({ where: { name: authors.name } });
            if (!old_authors || Number(old_authors.id) === Number(authors.id)) {
                if(files && files.image && files.image.length){
                    authors.image = this.imagesService.saveImage(files.image[0]);
                }
                return { success: true, datas: await this.authorsRepository.update(authors.id, authors) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot PUT /authors`, HttpStatus.NOT_FOUND);
        }
    }

    async delete(id: number) {
        try {
            const authors = await this.authorsRepository.findOne({ where: { id: id } });
            if (authors) {
                return { success: true, datas: await this.authorsRepository.delete(id) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot DELETE /authors/${id}`, HttpStatus.NOT_FOUND);
        }
    }
}
