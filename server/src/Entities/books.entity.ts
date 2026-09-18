import { Entity, Column, PrimaryGeneratedColumn, ManyToOne, JoinColumn, OneToMany } from 'typeorm';
import { Readers } from './readers.entity';
import { AuthorsBooks } from './authors_books.entity';

@Entity()
export class Books {
    @PrimaryGeneratedColumn()
    id: number;

    @Column('text', { nullable: true })
    name: string;

    @Column('text', { nullable: true })
    image: string;

    @Column('text', { nullable: true })
    description: string;

    @Column('text', { nullable: true, default: '\u0420\u0443\u0441\u0441\u043a\u0438\u0439' })
    language: string;

    @Column('integer', { nullable: true })
    readersId: number;

    @Column('integer', { default: 0 })
    likes_total: number;

    @Column('integer', { default: 0 })
    do_not_likes_total: number;

    @Column('integer', { nullable: true })
    year: number;

    @Column('integer', { nullable: true })
    recommended_age: number;

    @Column('boolean', { default: true })
    show_in_app: boolean;

    @ManyToOne(() => Readers, { onUpdate: 'CASCADE', onDelete: 'CASCADE' })
    @JoinColumn({ name: 'readersId' })
    readers: Readers;
}
