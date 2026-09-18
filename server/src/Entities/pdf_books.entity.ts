import { Entity, Column, PrimaryGeneratedColumn, ManyToOne, JoinColumn } from 'typeorm';
import { Books } from './books.entity';

@Entity('pdf_books')
export class PdfBooks {
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
