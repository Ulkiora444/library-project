import { Entity, Column, PrimaryGeneratedColumn, ManyToOne, JoinColumn } from 'typeorm';
import { Books } from './books.entity';

@Entity('epub_books')
export class EpubBooks {
    @PrimaryGeneratedColumn()
    id: number;

    @Column('integer', { nullable: true })
    booksId: number;

    @Column('text', { nullable: true })
    file: string;

    @ManyToOne(() => Books, { onUpdate: 'CASCADE', onDelete: 'CASCADE' })
    @JoinColumn({ name: 'booksId' })
    books: Books;
}
