import { Body, Controller, Delete, Get, Param, ParseIntPipe, Post, Put } from '@nestjs/common';
import { PromoCodeModel } from 'src/Models/promo_code.model';
import { PromoCodeService } from './promo_code.service';

@Controller('promo_code')
export class PromoCodeController {
    constructor(private readonly promoCodeService: PromoCodeService) {}

    @Get()
    async find() {
        return this.promoCodeService.find();
    }

    @Get(':id')
    async findOne(@Param('id') id: number) {
        return this.promoCodeService.findOne(id);
    }

    @Post()
    async create(@Body() promoCode: PromoCodeModel) {
        return this.promoCodeService.create(promoCode);
    }

    @Put()
    async update(@Body() promoCode: PromoCodeModel) {
        return this.promoCodeService.update(promoCode);
    }

    @Delete(':id')
    async delete(@Param('id', ParseIntPipe) id: number) {
        return this.promoCodeService.delete(id);
    }
}
