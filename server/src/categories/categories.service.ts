import { HttpException, HttpStatus, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Categories } from 'src/Entities/categories.entity';
import { ImagesService } from 'src/images/images.service';
import { CategoriesModel } from 'src/Models/categories.model';
import { Repository } from 'typeorm';

@Injectable()
export class CategoriesService {
    constructor(
        @InjectRepository(Categories)
        private readonly categoriesRepository: Repository<Categories>,
        private readonly imagesService: ImagesService
    ) {}

    async find() {
        try {
            return { success: true, datas: await this.categoriesRepository.find() };
        } catch {
            throw new HttpException(`Cannot GET /categories`, HttpStatus.NOT_FOUND);
        }
    }

    async findOne(id: number) {
        try {
            return { success: true, datas: await this.categoriesRepository.findOne({ where: { id: id } }) };
        } catch {
            throw new HttpException(`Cannot GET /categories/${id}`, HttpStatus.NOT_FOUND);
        }
    }

    async create(categories: CategoriesModel, files) {
        try {
            const old_categories = await this.categoriesRepository.findOne({ where: { name: categories.name } });
            if (!old_categories || Number(old_categories.id) === Number(categories.id)) {
                if(files && files.image && files.image.length){
                    categories.image = this.imagesService.saveImage(files.image[0]);
                }
                return { success: true, datas: await this.categoriesRepository.save(categories) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot POST /categories`, HttpStatus.NOT_FOUND);
        }
    }

    async update(categories: CategoriesModel, files) {
        try {
            const old_categories = await this.categoriesRepository.findOne({ where: { name: categories.name } });
            if (!old_categories) {
                if(files && files.image && files.image.length){
                    categories.image = this.imagesService.saveImage(files.image[0]);
                }
                return { success: true, datas: await this.categoriesRepository.update(categories.id, categories) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot PUT /categories`, HttpStatus.NOT_FOUND);
        }
    }

    async delete(id: number) {
        try {
            const categories = await this.categoriesRepository.findOne({ where: { id: id } });
            if (categories) {
                return { success: true, datas: await this.categoriesRepository.delete(id) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot DELETE /categories/${id}`, HttpStatus.NOT_FOUND);
        }
    }
}
