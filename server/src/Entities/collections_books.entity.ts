import { Entity, Column, PrimaryGeneratedColumn, ManyToOne, JoinColumn } from 'typeorm';
import { Books } from './books.entity';
import { Collections } from './collections.entity';

@Entity('collections_books')
export class CollectionsBooks {
    @PrimaryGeneratedColumn()
    id: number;

    @Column('integer', { nullable: true })
    collectionsId: number;

    @Column('integer', { nullable: true })
    booksId: number;

    @Column('text', { nullable: true })
    file: string;

    @ManyToOne(() => Collections, { onUpdate: 'CASCADE', onDelete: 'CASCADE' })
    @JoinColumn({ name: 'collectionsId' })
    collections: Collections;

    @ManyToOne(() => Books, { onUpdate: 'CASCADE', onDelete: 'CASCADE' })
    @JoinColumn({ name: 'booksId' })
    books: Books;
}
