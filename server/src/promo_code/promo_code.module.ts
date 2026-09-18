import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { JwtModule } from '@nestjs/jwt';
import { PromoCode } from 'src/Entities/promo_code.entity';
import { PromoCodeController } from './promo_code.controller';
import { PromoCodeService } from './promo_code.service';

@Module({
    imports: [
        TypeOrmModule.forFeature([PromoCode]),
        JwtModule.register({
            secret: "isajfysadofbivuvhyw98474y9273459437by978wyebufiadbyfoy2887204357029384bwioeurynwiecufywoineuyaniulyr2304870510451094ncryfhnc0n139rdxn2398djcnj2381mjdc9n8ud0xs812djd",
            signOptions: { expiresIn: '24h' },
        }),
    ],
    controllers: [PromoCodeController],
    providers: [PromoCodeService],
})
export class PromoCodeModule {}
