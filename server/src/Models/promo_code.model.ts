export interface PromoCodeModel {
    id?: number;
    code: string;
    month?: number;
    usersId?: number;
    start?: Date;
    end?: Date;
}
