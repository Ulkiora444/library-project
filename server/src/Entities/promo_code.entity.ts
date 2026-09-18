import { Entity, Column, PrimaryGeneratedColumn, ManyToOne, JoinColumn } from 'typeorm';
import { Users } from './users.entity';

@Entity('promo_code')
export class PromoCode {
    @PrimaryGeneratedColumn()
    id: number;

    @Column('text', { nullable: true })
    code: string;

    @Column('integer', { nullable: true })
    month: number;

    @Column('integer', { nullable: true })
    usersId: number;

    @Column('timestamp with time zone', { nullable: true })
    start: Date;

    @Column('timestamp with time zone', { nullable: true })
    end: Date;

    @ManyToOne(() => Users, { onUpdate: 'CASCADE', onDelete: 'CASCADE' })
    @JoinColumn({ name: 'usersId' })
    users: Users;
}
