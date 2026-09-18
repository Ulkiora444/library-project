import { Entity, Column, PrimaryGeneratedColumn, ManyToOne, JoinColumn } from 'typeorm';
import { Users } from './users.entity';

@Entity()
export class Supports {
    @PrimaryGeneratedColumn()
    id: number;

    @Column('integer', { nullable: true })
    usersId: number;

    @Column('text', { nullable: true })
    title: string;

    @Column('text', { nullable: true })
    description: string;

    @ManyToOne(() => Users)
    @JoinColumn({ name: 'usersId' })
    users: Users;
}
