import { Entity, Column, PrimaryGeneratedColumn } from 'typeorm';

@Entity()
export class Categories {
    @PrimaryGeneratedColumn()
    id: number;

    @Column('text', { nullable: true })
    name: string;

    @Column('text', { nullable: true })
    image: string;

    @Column('text', { nullable: true })
    description: string;
}
