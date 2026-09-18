import { Entity, Column, PrimaryGeneratedColumn, ManyToOne, JoinColumn } from 'typeorm';
import { Books } from './books.entity';
import { Categories } from './categories.entity';

@Entity('categories_books')
export class CategoriesBooks {
    @PrimaryGeneratedColumn()
    id: number;

    @Column('integer', { nullable: true })
    categoreisId: number;

    @Column('integer', { nullable: true })
    booksId: number;

    @ManyToOne(() => Categories, { onUpdate: 'CASCADE', onDelete: 'CASCADE' })
    @JoinColumn({ name: 'categoreisId' })
    categories: Categories;

    @ManyToOne(() => Books, { onUpdate: 'CASCADE', onDelete: 'CASCADE' })
    @JoinColumn({ name: 'booksId' })
    books: Books;
}
