export interface BooksModel {
    id?: number;
    name: string;
    image: string;
    description: string;
    language?: string;
    readersId?: number;
    likes_total?: number;
    do_not_likes_total?: number;
    year?: number;
    recommended_age?: number;
    show_in_app?: boolean;
}
