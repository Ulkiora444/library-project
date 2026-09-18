import { Entity, Column, PrimaryGeneratedColumn } from 'typeorm';

@Entity()
export class Readers {
    @PrimaryGeneratedColumn()
    id: number;

    @Column('text', { nullable: true })
    name: string;
}
