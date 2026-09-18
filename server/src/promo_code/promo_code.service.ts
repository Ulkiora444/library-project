import { HttpException, HttpStatus, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { PromoCode } from 'src/Entities/promo_code.entity';
import { PromoCodeModel } from 'src/Models/promo_code.model';
import { Repository } from 'typeorm';

@Injectable()
export class PromoCodeService {
    constructor(
        @InjectRepository(PromoCode)
        private readonly promoCodeRepository: Repository<PromoCode>,
    ) {}

    async find() {
        try {
            return { success: true, datas: await this.promoCodeRepository.find({ relations: ['users'] }) };
        } catch {
            throw new HttpException(`Cannot GET /promo_code`, HttpStatus.NOT_FOUND);
        }
    }

    async findOne(id: number) {
        try {
            return {
                success: true,
                datas: await this.promoCodeRepository.findOne({ where: { id: id }, relations: ['users'] }),
            };
        } catch {
            throw new HttpException(`Cannot GET /promo_code/${id}`, HttpStatus.NOT_FOUND);
        }
    }

    async create(promoCode: PromoCodeModel) {
        try {
            const old_promo_code = await this.promoCodeRepository.findOne({ where: { code: promoCode.code } });
            if (!old_promo_code) {
                return { success: true, datas: await this.promoCodeRepository.save(promoCode) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot POST /promo_code`, HttpStatus.NOT_FOUND);
        }
    }

    async update(promoCode: PromoCodeModel) {
        try {
            const old_promo_code = await this.promoCodeRepository.findOne({ where: { code: promoCode.code } });
            if (!old_promo_code) {
                return { success: true, datas: await this.promoCodeRepository.update(promoCode.id, promoCode) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot PUT /promo_code`, HttpStatus.NOT_FOUND);
        }
    }

    async delete(id: number) {
        try {
            const promoCode = await this.promoCodeRepository.findOne({ where: { id: id } });
            if (promoCode) {
                return { success: true, datas: await this.promoCodeRepository.delete(id) };
            }
            return { success: false };
        } catch {
            throw new HttpException(`Cannot DELETE /promo_code/${id}`, HttpStatus.NOT_FOUND);
        }
    }
}
