import { Entity, Column, PrimaryGeneratedColumn } from 'typeorm';

@Entity()
export class Collections {
    @PrimaryGeneratedColumn()
    id: number;

    @Column('text', { nullable: true })
    name: string;

    @Column('text', { nullable: true })
    description: string;
}
