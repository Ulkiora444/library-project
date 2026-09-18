import { Entity, Column, PrimaryGeneratedColumn, ManyToOne, JoinColumn } from 'typeorm';
import { Roles } from './roles.entity';

@Entity()
export class Users {
    @PrimaryGeneratedColumn()
    id: number;

    @Column('text', { nullable: true })
    username: string;

    @Column('text', { nullable: true })
    phone: string;

    @Column('text', { nullable: true })
    email: string;

    @Column('text', { nullable: true })
    password: string;

    @Column('text', { nullable: true })
    image: string;

    @Column('integer', { nullable: true })
    rolesId: number;

    @ManyToOne(() => Roles, { onUpdate: 'CASCADE', onDelete: 'CASCADE' })
    @JoinColumn({ name: 'rolesId' })
    roles: Roles;
}
