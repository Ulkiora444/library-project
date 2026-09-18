import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Roles } from './Entities/roles.entity';
import { RolesModule } from './roles/roles.module';
import { Readers } from './Entities/readers.entity';
import { ReadersModule } from './readers/readers.module';
import { Authors } from './Entities/authors.entity';
import { AuthorsModule } from './authors/authors.module';
import { Categories } from './Entities/categories.entity';
import { CategoriesModule } from './categories/categories.module';
import { Collections } from './Entities/collections.entity';
import { CollectionsModule } from './collections/collections.module';
import { Users } from './Entities/users.entity';
import { UsersModule } from './users/users.module';
import { AuthorsBooks } from './Entities/authors_books.entity';
import { AuthorsBooksModule } from './authors_books/authors_books.module';
import { Books } from './Entities/books.entity';
import { BooksModule } from './books/books.module';
import { CategoriesBooks } from './Entities/categories_books.entity';
import { CategoriesBooksModule } from './categories_books/categories_books.module';
import { CollectionsBooks } from './Entities/collections_books.entity';
import { CollectionsBooksModule } from './collections_books/collections_books.module';
import { EpubBooks } from './Entities/epub_books.entity';
import { EpubBooksModule } from './epub_books/epub_books.module';
import { PdfBooks } from './Entities/pdf_books.entity';
import { PdfBooksModule } from './pdf_books/pdf_books.module';
import { MangaBooks } from './Entities/manga_books.entity';
import { MangaBooksModule } from './manga_books/manga_books.module';
import { ManhwaBooks } from './Entities/manhwa_books.entity';
import { ManhwaBooksModule } from './manhwa_books/manhwa_books.module';
import { PromoCode } from './Entities/promo_code.entity';
import { PromoCodeModule } from './promo_code/promo_code.module';
import { Supports } from './Entities/supports.entity';
import { SupportsModule } from './supports/supports.module';

@Module({
  imports: [
    TypeOrmModule.forRoot({
      type: 'postgres',
      host: 'localhost',
      port: 5432,
      username: 'postgres',
      password: 'postgres',
      database: 'library_project',
      entities: [
        Roles,
        Readers,
        Authors,
        Categories,
        Collections,
        Users,
        AuthorsBooks,
        Books,
        CategoriesBooks,
        CollectionsBooks,
        EpubBooks,
        PdfBooks,
        MangaBooks,
        ManhwaBooks,
        PromoCode,
        Supports
      ],
      autoLoadEntities: true,
    }),
    RolesModule,
    ReadersModule,
    AuthorsModule,
    CategoriesModule,
    CollectionsModule,
    UsersModule,
    AuthorsBooksModule,
    BooksModule,
    CategoriesBooksModule,
    CollectionsBooksModule,
    EpubBooksModule,
    PdfBooksModule,
    MangaBooksModule,
    ManhwaBooksModule,
    PromoCodeModule,
    SupportsModule
  ],
  providers: [],
})
export class AppModule {}
