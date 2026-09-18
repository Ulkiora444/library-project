import { Entity, Column, PrimaryGeneratedColumn } from 'typeorm';

@Entity()
export class Authors {
    @PrimaryGeneratedColumn()
    id: number;

    @Column('text', { nullable: true })
    name: string;

    @Column('text', { nullable: true })
    description: string;

    @Column('integer', { default: 0 })
    likes_total: number;

    @Column('integer', { default: 0 })
    do_not_likes_total: number;

    @Column('text', { nullable: true })
    image: string;
}
