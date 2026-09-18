import { Entity, Column, PrimaryGeneratedColumn, ManyToOne, JoinColumn } from 'typeorm';
import { Authors } from './authors.entity';
import { Books } from './books.entity';

@Entity('authors_books')
export class AuthorsBooks {
    @PrimaryGeneratedColumn()
    id: number;

    @Column('integer', { nullable: true })
    authorsId: number;

    @Column('integer', { nullable: true })
    booksId: number;

    @ManyToOne(() => Authors, { onUpdate: 'CASCADE', onDelete: 'CASCADE' })
    @JoinColumn({ name: 'authorsId' })
    authors: Authors;

    @ManyToOne(() => Books, { onUpdate: 'CASCADE', onDelete: 'CASCADE' })
    @JoinColumn({ name: 'booksId' })
    books: Books;
}
