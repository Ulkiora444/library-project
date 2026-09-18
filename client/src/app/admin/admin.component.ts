import { Component, OnDestroy, OnInit } from '@angular/core';
import { Router } from '@angular/router';
import { forkJoin } from 'rxjs';
import { AppService, CurrentUser } from '../app.service';

type FieldType = 'text' | 'number' | 'password' | 'datetime-local' | 'file' | 'boolean';
type RowData = Record<string, unknown>;
type AdminPayload = Record<string, unknown> | FormData;
type Language = 'ru' | 'tm' | 'en';
type ThemeName = 'dark' | 'light' | 'amber';
type BookContentKind = 'epub' | 'pdf' | 'manga' | 'manhwa';
type TranslationKey =
  | 'admin'
  | 'records'
  | 'fields'
  | 'mode'
  | 'new'
  | 'edit'
  | 'delete'
  | 'create'
  | 'update'
  | 'saving'
  | 'clear'
  | 'data'
  | 'refresh'
  | 'loading'
  | 'noRecords'
  | 'logout'
  | 'search'
  | 'editor'
  | 'smartHint'
  | 'language'
  | 'theme'
  | 'dark'
  | 'light'
  | 'amber'
  | 'endpoint'
  | 'activeSection'
  | 'emptySearch'
  | 'created'
  | 'updated'
  | 'deleted'
  | 'saveFailed'
  | 'deleteFailed'
  | 'loadFailed'
  | 'backendSaveError'
  | 'backendDeleteError'
  | 'badId'
  | 'chooseImage'
  | 'replaceImage'
  | 'noImage'
  | 'bookContent'
  | 'bookContentHint'
  | 'chooseFile'
  | 'replaceFile'
  | 'noFile'
  | 'chooseImages'
  | 'mangaImagesHint'
  | 'selectedImages'
  | 'moveUp'
  | 'moveDown'
  | 'remove'
  | 'chapterNumber'
  | 'chapterNumberHint'
  | 'chapterRequired'
  | 'existingChapters'
  | 'noChapters'
  | 'shownInApp'
  | 'hiddenInApp';

interface AdminField {
  key: string;
  label: string;
  type: FieldType;
}

interface AdminResource {
  endpoint: string;
  label: string;
  fields: AdminField[];
  columns: string[];
  description: Record<Language, string>;
}

interface MangaImageFile {
  id: string;
  file: File;
  previewUrl: string;
}

@Component({
  selector: 'app-admin',
  templateUrl: './admin.component.html',
  styleUrl: './admin.component.css'
})
export class AdminComponent implements OnInit, OnDestroy {
  private readonly relationOptionEndpoints = ['roles', 'authors', 'readers', 'books', 'categories', 'collections', 'users'];

  readonly languages: { key: Language; label: string }[] = [
    { key: 'ru', label: 'RU' },
    { key: 'tm', label: 'TM' },
    { key: 'en', label: 'EN' }
  ];

  readonly themes: { key: ThemeName; labelKey: TranslationKey }[] = [
    { key: 'dark', labelKey: 'dark' },
    { key: 'light', labelKey: 'light' },
    { key: 'amber', labelKey: 'amber' }
  ];

  readonly translations: Record<Language, Record<TranslationKey, string>> = {
    ru: {
      admin: 'Админка',
      records: 'Записи',
      fields: 'Поля',
      mode: 'Режим',
      new: 'Новая',
      edit: 'Изменить',
      delete: 'Удалить',
      create: 'Создать',
      update: 'Обновить',
      saving: 'Сохранение...',
      clear: 'Очистить',
      data: 'Данные',
      refresh: 'Обновить',
      loading: 'Загрузка...',
      noRecords: 'Записей пока нет',
      logout: 'Выйти',
      search: 'Поиск по текущему разделу',
      editor: 'Редактор',
      smartHint: 'Подсказка',
      language: 'Язык',
      theme: 'Тема',
      dark: 'Темная',
      light: 'Светлая',
      amber: 'Книжная',
      endpoint: 'Адрес API',
      activeSection: 'Текущий раздел',
      emptySearch: 'Поиск ничего не нашел',
      created: 'Запись создана',
      updated: 'Запись обновлена',
      deleted: 'Запись удалена',
      saveFailed: 'Не удалось сохранить. Возможно, такая запись уже есть.',
      deleteFailed: 'Не удалось удалить запись',
      loadFailed: 'Не удалось загрузить раздел',
      backendSaveError: 'Backend вернул ошибку при сохранении',
      backendDeleteError: 'Backend вернул ошибку при удалении',
      badId: 'У записи нет корректного id',
      chooseImage: 'Выбрать изображение',
      replaceImage: 'Заменить изображение',
      noImage: 'Изображение не выбрано',
      bookContent: 'Файл книги',
      bookContentHint: 'Появляется для reader manga, manhwa или epub',
      chooseFile: 'Выбрать файл',
      replaceFile: 'Заменить файл',
      noFile: 'Файл не выбран',
      chooseImages: 'Выбрать изображения',
      mangaImagesHint: 'Изображения сохранятся сверху вниз. Перед сохранением можно поменять порядок.',
      selectedImages: 'Выбрано изображений',
      moveUp: 'Выше',
      moveDown: 'Ниже',
      remove: 'Убрать',
      chapterNumber: 'Номер главы',
      chapterNumberHint: 'Новая глава добавится отдельно. Можно вводить дробные номера, например 46.1. Если глава уже есть, заменятся только ее изображения.',
      chapterRequired: 'Укажите номер главы для изображений',
      existingChapters: 'Добавленные главы',
      noChapters: 'У этой книги еще нет глав',
      shownInApp: '\u041f\u043e\u043a\u0430\u0437\u044b\u0432\u0430\u0435\u0442\u0441\u044f \u0432 \u0442\u0435\u043b\u0435\u0444\u043e\u043d\u0435',
      hiddenInApp: '\u0421\u043a\u0440\u044b\u0442\u043e \u0432 \u0442\u0435\u043b\u0435\u0444\u043e\u043d\u0435'
    },
    tm: {
      admin: 'Admin panel',
      records: 'Yazgylar',
      fields: 'Meydanlar',
      mode: 'Tertip',
      new: 'Täze',
      edit: 'Üýtget',
      delete: 'Poz',
      create: 'Döret',
      update: 'Täzele',
      saving: 'Saklanylýar...',
      clear: 'Arassala',
      data: 'Maglumatlar',
      refresh: 'Täzele',
      loading: 'Ýüklenýär...',
      noRecords: 'Yazgy ýok',
      logout: 'Çykmak',
      search: 'Şu bölümden gözle',
      editor: 'Redaktor',
      smartHint: 'Maslahat',
      language: 'Dil',
      theme: 'Tema',
      dark: 'Garaňky',
      light: 'Ýagty',
      amber: 'Kitap',
      endpoint: 'API salgysy',
      activeSection: 'Işjeň bölüm',
      emptySearch: 'Gözleg netije bermedi',
      created: 'Yazgy döredildi',
      updated: 'Yazgy täzelendi',
      deleted: 'Yazgy pozuldy',
      saveFailed: 'Saklap bolmady. Şeýle ýazgy eýýäm bar bolmagy mümkin.',
      deleteFailed: 'Yazgyny pozup bolmady',
      loadFailed: 'Bölümi ýükläp bolmady',
      backendSaveError: 'Saklananda backend ýalňyşlyk gaýtardy',
      backendDeleteError: 'Pozulanda backend ýalňyşlyk gaýtardy',
      badId: 'Yazgyda dogry id ýok',
      chooseImage: 'Surat saýla',
      replaceImage: 'Suraty çalyş',
      noImage: 'Surat saýlanmady',
      bookContent: 'Kitap faýly',
      bookContentHint: 'Reader manga, manhwa ýa-da epub bolanda görünýär',
      chooseFile: 'Faýl saýla',
      replaceFile: 'Faýly çalyş',
      noFile: 'Faýl saýlanmady',
      chooseImages: 'Suratlary saýla',
      mangaImagesHint: 'Suratlar ýokardan aşak saklanar. Saklamazdan öň tertibini üýtgedip bolýar.',
      selectedImages: 'Saýlanan suratlar',
      moveUp: 'Ýokary',
      moveDown: 'Aşak',
      remove: 'Aýyr',
      chapterNumber: 'Bap belgisi',
      chapterNumberHint: 'Täze bap aýratyn goşular. Bölekli belgileri girizip bolýar, mysal üçin 46.1. Bap eýýäm bar bolsa, diňe onuň suratlary çalşylar.',
      chapterRequired: 'Suratlar üçin bap belgisini görkeziň',
      existingChapters: 'Goşulan baplar',
      noChapters: 'Bu kitapda entek bap ýok',
      shownInApp: 'Telefonda görkezilýär',
      hiddenInApp: 'Telefonda gizlenen'
    },
    en: {
      admin: 'Admin',
      records: 'Records',
      fields: 'Fields',
      mode: 'Mode',
      new: 'New',
      edit: 'Edit',
      delete: 'Delete',
      create: 'Create',
      update: 'Update',
      saving: 'Saving...',
      clear: 'Clear',
      data: 'Data',
      refresh: 'Refresh',
      loading: 'Loading...',
      noRecords: 'No records yet',
      logout: 'Logout',
      search: 'Search current section',
      editor: 'Editor',
      smartHint: 'Hint',
      language: 'Language',
      theme: 'Theme',
      dark: 'Dark',
      light: 'Light',
      amber: 'Book',
      endpoint: 'API endpoint',
      activeSection: 'Active section',
      emptySearch: 'No search results',
      created: 'Record created',
      updated: 'Record updated',
      deleted: 'Record deleted',
      saveFailed: 'Record was not saved. It may already exist.',
      deleteFailed: 'Record was not deleted',
      loadFailed: 'Could not load section',
      backendSaveError: 'Backend returned an error while saving',
      backendDeleteError: 'Backend returned an error while deleting',
      badId: 'Record has no valid id',
      chooseImage: 'Choose image',
      replaceImage: 'Replace image',
      noImage: 'No image selected',
      bookContent: 'Book file',
      bookContentHint: 'Shown for manga, manhwa, epub, or pdf readers',
      chooseFile: 'Choose file',
      replaceFile: 'Replace file',
      noFile: 'No file selected',
      chooseImages: 'Choose images',
      mangaImagesHint: 'Images will be saved from top to bottom. You can reorder them before saving.',
      selectedImages: 'Selected images',
      moveUp: 'Move up',
      moveDown: 'Move down',
      remove: 'Remove',
      chapterNumber: 'Chapter number',
      chapterNumberHint: 'A new chapter is added separately. Decimal chapter numbers are supported, for example 46.1. If the chapter exists, only its images are replaced.',
      chapterRequired: 'Enter the chapter number for images',
      existingChapters: 'Added chapters',
      noChapters: 'This book has no chapters yet',
      shownInApp: 'Visible in phone app',
      hiddenInApp: 'Hidden in phone app'
    }
  };

  readonly resourceLabels: Record<Language, Record<string, string>> = {
    ru: {
      roles: 'Роли',
      readers: 'Читатели',
      authors: 'Авторы',
      categories: 'Категории',
      collections: 'Коллекции',
      users: 'Пользователи',
      books: 'Книги',
      authors_books: 'Авторы и книги',
      categories_books: 'Категории и книги',
      collections_books: 'Коллекции и книги',
      epub_books: 'EPUB книги',
      manga_books: 'Манга',
      manhwa_books: 'Манхва',
      promo_code: 'Промокоды',
      supports: 'Поддержка'
    },
    tm: {
      roles: 'Rollar',
      readers: 'Okyjylar',
      authors: 'Awtorlar',
      categories: 'Kategoriýalar',
      collections: 'Toplumlar',
      users: 'Ulanyjylar',
      books: 'Kitaplar',
      authors_books: 'Awtorlar we kitaplar',
      categories_books: 'Kategoriýalar we kitaplar',
      collections_books: 'Toplumlar we kitaplar',
      epub_books: 'EPUB kitaplar',
      manga_books: 'Manga',
      manhwa_books: 'Manhwa',
      promo_code: 'Promo kodlar',
      supports: 'Goldaw'
    },
    en: {
      roles: 'Roles',
      readers: 'Readers',
      authors: 'Authors',
      categories: 'Categories',
      collections: 'Collections',
      users: 'Users',
      books: 'Books',
      authors_books: 'Authors books',
      categories_books: 'Categories books',
      collections_books: 'Collections books',
      epub_books: 'EPUB books',
      manga_books: 'Manga books',
      manhwa_books: 'Manhwa books',
      promo_code: 'Promo codes',
      supports: 'Support'
    }
  };

  readonly fieldLabels: Record<Language, Record<string, string>> = {
    ru: {
      id: 'ID',
      name: 'Название',
      description: 'Описание',
      language: 'Язык',
      likes_total: 'Лайки',
      do_not_likes_total: 'Дизлайки',
      show_in_app: '\u0412 \u0442\u0435\u043b\u0435\u0444\u043e\u043d\u0435',
      image: 'Изображение',
      username: 'Имя пользователя',
      phone: 'Телефон',
      email: 'Email',
      password: 'Пароль',
      rolesId: 'Роль',
      authorsId: 'Автор',
      readersId: 'Читатель',
      year: 'Год',
      recommended_age: 'Возраст',
      booksId: 'Книга',
      categoreisId: 'Категория',
      collectionsId: 'Коллекция',
      file: 'Файл',
      code: 'Код',
      month: 'Месяц',
      usersId: 'Пользователь',
      start: 'Начало',
      end: 'Конец',
      title: 'Заголовок',
      roles: 'Роль',
      authors: 'Автор',
      readers: 'Читатель',
      categories: 'Категория',
      collections: 'Коллекция',
      books: 'Книга',
      users: 'Пользователь'
    },
    tm: {
      id: 'ID',
      name: 'Ady',
      description: 'Düşündiriş',
      language: 'Dil',
      likes_total: 'Halanlar',
      do_not_likes_total: 'Halamadyklar',
      show_in_app: 'Telefonda',
      image: 'Surat',
      username: 'Ulanyjy ady',
      phone: 'Telefon',
      email: 'Email',
      password: 'Açar söz',
      rolesId: 'Rol',
      authorsId: 'Awtor',
      readersId: 'Okyjy',
      year: 'Ýyl',
      recommended_age: 'Ýaş',
      booksId: 'Kitap',
      categoreisId: 'Kategoriýa',
      collectionsId: 'Toplum',
      file: 'Faýl',
      code: 'Kod',
      month: 'Aý',
      usersId: 'Ulanyjy',
      start: 'Başlangyç',
      end: 'Tamamlanýar',
      title: 'Sözbaşy',
      roles: 'Rol',
      authors: 'Awtor',
      readers: 'Okyjy',
      categories: 'Kategoriýa',
      collections: 'Toplum',
      books: 'Kitap',
      users: 'Ulanyjy'
    },
    en: {
      id: 'ID',
      name: 'Name',
      description: 'Description',
      language: 'Language',
      likes_total: 'Likes',
      do_not_likes_total: 'Dislikes',
      show_in_app: 'Phone app',
      image: 'Image',
      username: 'Username',
      phone: 'Phone',
      email: 'Email',
      password: 'Password',
      rolesId: 'Role',
      authorsId: 'Author',
      readersId: 'Reader',
      year: 'Year',
      recommended_age: 'Age',
      booksId: 'Book',
      categoreisId: 'Category',
      collectionsId: 'Collection',
      file: 'File',
      code: 'Code',
      month: 'Month',
      usersId: 'User',
      start: 'Start',
      end: 'End',
      title: 'Title',
      roles: 'Role',
      authors: 'Author',
      readers: 'Reader',
      categories: 'Category',
      collections: 'Collection',
      books: 'Book',
      users: 'User'
    }
  };

  readonly resources: AdminResource[] = [
    this.resource('users', 'Users', [
      ['image', 'Image', 'file'],
      ['username', 'Username', 'text'],
      ['phone', 'Phone', 'text'],
      ['email', 'Email', 'text'],
      ['password', 'Password', 'password'],
      ['rolesId', 'Role', 'number']
    ], ['id', 'image', 'username', 'phone', 'email', 'roles'], {
      ru: 'Для доступа к админке пользователь должен иметь роль admin или rolesId = 1.',
      tm: 'Admin paneline girmek üçin ulanyjyda admin roly ýa-da rolesId = 1 bolmaly.',
      en: 'To access this admin, a user needs an admin role or rolesId = 1.'
    }),
    this.resource('categories', 'Categories', [
      ['image', 'Image', 'file'],
      ['name', 'Name', 'text'],
      ['description', 'Description', 'text']
    ], ['id', 'image', 'name', 'description'], {
      ru: 'Категории помогают фильтровать библиотеку и связываются с книгами отдельно.',
      tm: 'Kategoriýalar kitaphanany süzmäge kömek edýär we kitaplara aýratyn baglanýar.',
      en: 'Categories help filter the library and connect to books separately.'
    }),
    this.resource('books', 'Books', [
      ['image', 'Image', 'file'],
      ['show_in_app', 'Phone app', 'boolean'],
      ['name', 'Name', 'text'],
      ['description', 'Description', 'text'],
      ['language', 'Language', 'text'],
      ['readersId', 'Reader', 'number'],
      ['year', 'Year', 'number'],
      ['recommended_age', 'Age', 'number']
    ], ['id', 'image', 'show_in_app', 'name', 'language', 'authors', 'categories', 'readers', 'year', 'recommended_age'], {
      ru: 'Книги являются центром системы. После создания их можно связать с файлами и категориями.',
      tm: 'Kitaplar ulgamyň merkezidir. Döredilenden soň olary faýllar we kategoriýalar bilen baglap bolýar.',
      en: 'Books are the center of the system. After creation, link files and categories.'
    }),
    this.resource('authors', 'Authors', [
      ['image', 'Image', 'file'],
      ['name', 'Name', 'text'],
      ['description', 'Description', 'text']
    ], ['id', 'image', 'name', 'description'], {
      ru: 'Добавьте автора, затем свяжите его с книгой в разделе авторов и книг.',
      tm: 'Awtory goşuň, soň ony awtorlar we kitaplar bölüminde kitaba baglaň.',
      en: 'Create an author, then link it to a book in the authors books section.'
    }),
    this.resource('collections', 'Collections', [
      ['name', 'Name', 'text'],
      ['description', 'Description', 'text']
    ], ['id', 'name', 'description', 'books'], {
      ru: 'Коллекции подходят для подборок, серий и специальных полок.',
      tm: 'Toplumlar saýlanan sanawlar, seriýalar we ýörite tekjeler üçin amatly.',
      en: 'Collections work well for curated lists, series, and shelves.'
    }),
    this.resource('promo_code', 'Promo Code', [
      ['code', 'Code', 'text'],
      ['month', 'Month', 'number'],
      ['usersId', 'User', 'number']
    ], ['id', 'code', 'month', 'users'], {
      ru: 'Промокод связывается с пользователем и имеет период действия.',
      tm: 'Promo kod ulanyja baglanýar we hereket möhleti bolýar.',
      en: 'Promo codes link to a user and have an active period.'
    }),
    this.resource('supports', 'Supports', [
      ['usersId', 'User', 'number'],
      ['title', 'Title', 'text'],
      ['description', 'Description', 'text']
    ], ['id', 'users', 'title', 'description'], {
      ru: 'Обращения поддержки показывают, кто написал и с какой темой.',
      tm: 'Goldaw ýüzlenmeleri kimiň ýazandygyny we temasyny görkezýär.',
      en: 'Support tickets show who wrote and what the topic is.'
    })
  ];

  selectedResource = this.resources[0];
  rows: RowData[] = [];
  relationOptions: Record<string, RowData[]> = {};
  form: RowData = {};
  formFiles: Record<string, File | null> = {};
  filePreviewUrls: Record<string, string> = {};
  bookContentFile: File | null = null;
  bookChapterNumber = '';
  bookContentRows: RowData[] = [];
  mangaImageFiles: MangaImageFile[] = [];
  selectedBookAuthorIds: number[] = [];
  selectedBookCategoryIds: number[] = [];
  bookAuthorSearch = '';
  bookCategorySearch = '';
  selectedCollectionBookIds: number[] = [];
  collectionBookSearch = '';
  visibilitySavingIds = new Set<number>();
  editingId: number | null = null;
  currentUser: CurrentUser | null = null;
  language: Language = 'ru';
  theme: ThemeName = 'dark';
  searchTerm = '';
  readerFilter = '';
  authorFilter = '';
  categoryFilter = '';
  loading = false;
  saving = false;
  error = '';
  message = '';

  constructor(
    private appService: AppService,
    private router: Router
  ) {}

  get filteredRows(): RowData[] {
    let result = this.rows;

    // Фильтры для Books
    if (this.selectedResource.endpoint === 'books') {
      // Фильтр по читателю
      if (this.readerFilter) {
        result = result.filter((row) => Number(row['readersId']) === Number(this.readerFilter));
      }

      // Фильтр по авторам
      if (this.authorFilter) {
        const bookIds = result.map((row) => Number(row['id'])).filter((id) => Number.isFinite(id));
        const authorBookRows = (this.relationOptions['authors_books'] || []).filter(
          (row) => Number(row['authorsId']) === Number(this.authorFilter)
        );
        const allowedBookIds = new Set(authorBookRows.map((row) => Number(row['booksId'])));
        result = result.filter((row) => allowedBookIds.has(Number(row['id'])));
      }

      // Фильтр по категориям
      if (this.categoryFilter) {
        const categoryBookRows = (this.relationOptions['categories_books'] || []).filter(
          (row) => Number(row['categoreisId']) === Number(this.categoryFilter)
        );
        const allowedBookIds = new Set(categoryBookRows.map((row) => Number(row['booksId'])));
        result = result.filter((row) => allowedBookIds.has(Number(row['id'])));
      }
    }

    // Поиск по тексту
    const term = this.searchTerm.trim().toLowerCase();
    if (!term) {
      return result;
    }

    return result.filter((row) =>
      this.selectedResource.columns.some((column) =>
        this.displayValue(row, column).toLowerCase().includes(term)
      )
    );
  }

  ngOnInit(): void {
    this.language = this.readStoredLanguage();
    this.theme = this.readStoredTheme();
    this.currentUser = this.appService.getCurrentUser();
    if (!this.currentUser || !this.appService.isAdmin(this.currentUser)) {
      this.appService.logout();
      void this.router.navigate(['/login']);
      return;
    }

    this.loadRelationOptions();
    this.loadRows();
  }

  ngOnDestroy(): void {
    this.clearFilePreviews();
    this.clearMangaImages();
  }

  t(key: TranslationKey): string {
    return this.translations[this.language][key];
  }

  resourceLabel(resource: AdminResource): string {
    return this.resourceLabels[this.language][resource.endpoint] || resource.label;
  }

  fieldLabel(field: AdminField): string {
    return this.fieldLabels[this.language][field.key] || field.label;
  }

  columnLabel(column: string): string {
    return this.fieldLabels[this.language][column] || column;
  }

  isRelationField(field: AdminField): boolean {
    return this.relationEndpoint(field.key) !== null;
  }

  isFileField(field: AdminField): boolean {
    return field.type === 'file';
  }

  isBooleanField(field: AdminField): boolean {
    return field.type === 'boolean';
  }

  booleanFieldValue(field: AdminField): boolean {
    return this.booleanValue(this.form[field.key]);
  }

  setBooleanFieldValue(field: AdminField, value: boolean): void {
    this.form[field.key] = value;
  }

  booleanStateLabel(field: AdminField): string {
    return this.booleanFieldValue(field) ? this.t('shownInApp') : this.t('hiddenInApp');
  }

  isBooleanColumn(column: string): boolean {
    return this.selectedResource.fields.some((field) => field.key === column && field.type === 'boolean');
  }

  booleanCellValue(row: RowData, column: string): boolean {
    return this.booleanValue(row[column]);
  }

  booleanCellLabel(row: RowData, column: string): string {
    return this.booleanCellValue(row, column) ? this.t('shownInApp') : this.t('hiddenInApp');
  }

  isBookVisibilityColumn(column: string): boolean {
    return this.selectedResource.endpoint === 'books' && column === 'show_in_app';
  }

  isBookVisibilitySaving(row: RowData): boolean {
    const id = Number(row['id']);
    return Number.isFinite(id) && this.visibilitySavingIds.has(id);
  }

  toggleBookVisibility(row: RowData): void {
    const id = Number(row['id']);
    if (!Number.isFinite(id) || this.isBookVisibilitySaving(row)) {
      return;
    }

    const nextValue = !this.booleanCellValue(row, 'show_in_app');
    this.visibilitySavingIds = new Set([...this.visibilitySavingIds, id]);
    this.error = '';
    this.message = '';

    this.appService.updateBookVisibility(id, nextValue).subscribe({
      next: (response) => {
        this.visibilitySavingIds = new Set([...this.visibilitySavingIds].filter((savingId) => savingId !== id));
        if (!response.success) {
          this.error = this.t('saveFailed');
          return;
        }

        this.updateBookVisibilityLocally(id, response.datas?.show_in_app ?? nextValue);
      },
      error: () => {
        this.visibilitySavingIds = new Set([...this.visibilitySavingIds].filter((savingId) => savingId !== id));
        this.error = this.t('backendSaveError');
      }
    });
  }

  relationOptionsFor(field: AdminField): RowData[] {
    const endpoint = this.relationEndpoint(field.key);
    return endpoint ? this.relationOptions[endpoint] || [] : [];
  }

  relationOptionLabel(option: RowData): string {
    const readable = option['name'] ?? option['username'] ?? option['email'] ?? option['title'] ?? option['code'];
    return readable === undefined || readable === null || readable === '' ? `ID ${option['id']}` : String(readable);
  }

  optionId(option: RowData): number {
    return Number(option['id']);
  }

  isBooksResource(): boolean {
    return this.selectedResource.endpoint === 'books';
  }

  isCollectionsResource(): boolean {
    return this.selectedResource.endpoint === 'collections';
  }

  bookAuthorOptions(): RowData[] {
    return this.relationOptions['authors'] || [];
  }

  bookCategoryOptions(): RowData[] {
    return this.relationOptions['categories'] || [];
  }

  collectionBookOptions(): RowData[] {
    return this.relationOptions['books'] || [];
  }

  filteredBookAuthorOptions(): RowData[] {
    return this.filteredBookLinkOptions(this.bookAuthorOptions(), this.selectedBookAuthorIds, this.bookAuthorSearch);
  }

  filteredBookCategoryOptions(): RowData[] {
    return this.filteredBookLinkOptions(this.bookCategoryOptions(), this.selectedBookCategoryIds, this.bookCategorySearch);
  }

  filteredCollectionBookOptions(): RowData[] {
    return this.filteredBookLinkOptions(this.collectionBookOptions(), this.selectedCollectionBookIds, this.collectionBookSearch);
  }

  selectedBookAuthors(): RowData[] {
    return this.selectedBookAuthorIds
      .map((id) => this.bookAuthorOptions().find((option) => Number(option['id']) === id))
      .filter((option): option is RowData => Boolean(option));
  }

  selectedBookCategories(): RowData[] {
    return this.selectedBookCategoryIds
      .map((id) => this.bookCategoryOptions().find((option) => Number(option['id']) === id))
      .filter((option): option is RowData => Boolean(option));
  }

  selectedCollectionBooks(): RowData[] {
    return this.selectedCollectionBookIds
      .map((id) => this.collectionBookOptions().find((option) => Number(option['id']) === id))
      .filter((option): option is RowData => Boolean(option));
  }

  addBookAuthor(authorId: number): void {
    if (!this.selectedBookAuthorIds.includes(authorId)) {
      this.selectedBookAuthorIds = [...this.selectedBookAuthorIds, authorId];
    }
    this.bookAuthorSearch = '';
  }

  addBookCategory(categoryId: number): void {
    if (!this.selectedBookCategoryIds.includes(categoryId)) {
      this.selectedBookCategoryIds = [...this.selectedBookCategoryIds, categoryId];
    }
    this.bookCategorySearch = '';
  }

  addCollectionBook(bookId: number): void {
    if (!this.selectedCollectionBookIds.includes(bookId)) {
      this.selectedCollectionBookIds = [...this.selectedCollectionBookIds, bookId];
    }
    this.collectionBookSearch = '';
  }

  isBookAuthorSelected(authorId: number): boolean {
    return this.selectedBookAuthorIds.includes(authorId);
  }

  isBookCategorySelected(categoryId: number): boolean {
    return this.selectedBookCategoryIds.includes(categoryId);
  }

  toggleBookAuthor(authorId: number): void {
    this.selectedBookAuthorIds = this.toggleSelection(this.selectedBookAuthorIds, authorId);
  }

  toggleBookCategory(categoryId: number): void {
    this.selectedBookCategoryIds = this.toggleSelection(this.selectedBookCategoryIds, categoryId);
  }

  toggleCollectionBook(bookId: number): void {
    this.selectedCollectionBookIds = this.toggleSelection(this.selectedCollectionBookIds, bookId);
  }

  setFieldValue(field: AdminField, value: unknown): void {
    const readerChanged = field.key === 'readersId' && this.form[field.key] !== value;
    if (readerChanged) {
      this.clearBookContentFile();
    }

    this.form[field.key] = value;

    if (readerChanged) {
      this.refreshBookContentRows();
    }
  }

  bookContentKind(): BookContentKind | null {
    if (this.selectedResource.endpoint !== 'books') {
      return null;
    }

    const readerId = Number(this.form['readersId']);
    const reader = this.relationOptions['readers']?.find((item) => Number(item['id']) === readerId);
    const readerName = String(reader?.['name'] || '').toLowerCase();

    if (readerName.includes('pdf') || readerName.includes('пдф')) {
      return 'pdf';
    }

    if (readerName.includes('manhwa') || readerName.includes('манхва')) {
      return 'manhwa';
    }

    if (readerName.includes('manga') || readerName.includes('манга')) {
      return 'manga';
    }

    if (readerName.includes('epub') || readerName.includes('епуб') || readerName.includes('эпуб')) {
      return 'epub';
    }

    return null;
  }

  bookContentTitle(kind: BookContentKind): string {
    return `${this.t('bookContent')} ${kind.toUpperCase()}`;
  }

  isImageBookContentKind(kind: BookContentKind): boolean {
    return kind === 'manga' || kind === 'manhwa';
  }

  bookContentAccept(kind: BookContentKind): string {
    if (kind === 'pdf') {
      return '.pdf,application/pdf';
    }

    return '.epub,application/epub+zip';
  }

  bookContentActionLabel(): string {
    return this.bookContentFile ? this.t('replaceFile') : this.t('chooseFile');
  }

  bookContentFileLabel(): string {
    return this.bookContentFile?.name || this.t('noFile');
  }

  onBookContentFileChange(event: Event): void {
    const input = event.target as HTMLInputElement;
    this.bookContentFile = input.files?.item(0) || null;
  }

  mangaImageCountLabel(): string {
    return `${this.t('selectedImages')}: ${this.mangaImageFiles.length}`;
  }

  existingBookChapters(): string[] {
    const chapters = this.bookContentRows
      .map((row) => String(row['name'] ?? '').trim())
      .filter((chapter) => chapter.length > 0);

    return [...new Set(chapters)].sort((first, second) =>
      first.localeCompare(second, undefined, { numeric: true, sensitivity: 'base' })
    );
  }

  chapterPageCount(chapter: string): number {
    return this.bookContentRows.filter((row) => String(row['name'] ?? '').trim() === chapter).length;
  }

  selectChapter(chapter: string): void {
    this.bookChapterNumber = chapter;
  }

  onMangaImagesChange(event: Event): void {
    const input = event.target as HTMLInputElement;
    const files = Array.from(input.files || []);
    const nextFiles = files.map((file, index) => ({
      id: `${Date.now()}-${index}-${file.name}`,
      file,
      previewUrl: URL.createObjectURL(file)
    }));

    this.mangaImageFiles = [...this.mangaImageFiles, ...nextFiles];
    input.value = '';
  }

  moveMangaImage(index: number, direction: -1 | 1): void {
    const targetIndex = index + direction;
    if (targetIndex < 0 || targetIndex >= this.mangaImageFiles.length) {
      return;
    }

    const images = [...this.mangaImageFiles];
    [images[index], images[targetIndex]] = [images[targetIndex], images[index]];
    this.mangaImageFiles = images;
  }

  removeMangaImage(index: number): void {
    const image = this.mangaImageFiles[index];
    if (!image) {
      return;
    }

    URL.revokeObjectURL(image.previewUrl);
    this.mangaImageFiles = this.mangaImageFiles.filter((_, imageIndex) => imageIndex !== index);
  }

  formatFileSize(file: File): string {
    const kilobytes = file.size / 1024;
    if (kilobytes < 1024) {
      return `${Math.max(1, Math.round(kilobytes))} KB`;
    }

    return `${(kilobytes / 1024).toFixed(1)} MB`;
  }

  selectedFileLabel(field: AdminField): string {
    const file = this.formFiles[field.key];
    const value = this.form[field.key];
    return file?.name || (typeof value === 'string' ? value : '');
  }

  imageActionLabel(field: AdminField): string {
    return this.selectedFileLabel(field) ? this.t('replaceImage') : this.t('chooseImage');
  }

  imagePreview(field: AdminField): string {
    return this.filePreviewUrls[field.key] || this.imageUrl(this.form[field.key]);
  }

  isImageColumn(column: string): boolean {
    return column === 'image';
  }

  imageCellSrc(row: RowData, column: string): string {
    return this.imageUrl(row[column]);
  }

  onFileChange(event: Event, field: AdminField): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.item(0) || null;

    this.clearFilePreview(field.key);
    this.formFiles[field.key] = file;
    this.form[field.key] = file ? file.name : '';
    if (file) {
      this.filePreviewUrls[field.key] = URL.createObjectURL(file);
    }
  }

  selectResource(resource: AdminResource): void {
    this.selectedResource = resource;
    this.searchTerm = '';
    this.readerFilter = '';
    this.authorFilter = '';
    this.categoryFilter = '';
    this.resetForm();
    this.loadRows();
  }

  setLanguage(language: Language): void {
    this.language = language;
    localStorage.setItem('library_admin_language', language);
  }

  setLanguageValue(language: string): void {
    if (language === 'ru' || language === 'tm' || language === 'en') {
      this.setLanguage(language);
    }
  }

  setTheme(theme: ThemeName): void {
    this.theme = theme;
    localStorage.setItem('library_admin_theme', theme);
  }

  setThemeValue(theme: string): void {
    if (theme === 'dark' || theme === 'light' || theme === 'amber') {
      this.setTheme(theme);
    }
  }

  loadRows(resource: AdminResource = this.selectedResource): void {
    const endpoint = resource.endpoint;

    this.loading = true;
    this.error = '';
    this.message = '';
    this.loadRelationOptions(this.resourceRelationEndpoints(resource));

    this.appService.list<RowData>(endpoint).subscribe({
      next: (response) => {
        const rows = response.success && response.datas ? response.datas : [];
        this.syncRelationOptions(endpoint, rows);

        if (this.selectedResource.endpoint !== endpoint) {
          return;
        }

        this.loading = false;
        this.rows = rows;
        if (endpoint === 'books') {
          this.refreshBookRelationRows();
        }
        if (endpoint === 'collections') {
          this.refreshCollectionRelationRows();
        }
      },
      error: () => {
        this.syncRelationOptions(endpoint, []);

        if (this.selectedResource.endpoint !== endpoint) {
          return;
        }

        this.loading = false;
        this.rows = [];
        this.error = `${this.t('loadFailed')}: ${this.resourceLabel(resource)}`;
      }
    });
  }

  save(): void {
    const payload = this.buildPayload();
    this.saving = true;
    this.error = '';
    this.message = '';

    const request = this.editingId
      ? this.appService.update<RowData>(this.selectedResource.endpoint, this.withId(payload, this.editingId))
      : this.appService.create<RowData>(this.selectedResource.endpoint, payload);

    request.subscribe({
      next: (response) => {
        if (!response.success) {
          this.saving = false;
          this.error = this.t('saveFailed');
          return;
        }

        const savedId = this.savedRecordId(response.datas) || this.editingId;
        this.saveCollectionRelationsIfNeeded(savedId, () => {
          this.saveBookRelationsIfNeeded(savedId, () => {
            this.saveBookContentFileIfNeeded(savedId, () => {
              this.saving = false;
              this.message = this.editingId ? this.t('updated') : this.t('created');
              this.resetForm();
              this.loadRows();
            });
          });
        });
      },
      error: () => {
        this.saving = false;
        this.error = this.t('backendSaveError');
      }
    });
  }

  edit(row: RowData): void {
    const id = Number(row['id']);
    this.editingId = Number.isFinite(id) ? id : null;
    this.form = {};
    this.formFiles = {};
    this.clearBookContentFile();
    this.clearBookSelections();
    this.clearCollectionSelections();
    this.clearFilePreviews();

    for (const field of this.selectedResource.fields) {
      this.form[field.key] = row[field.key] ?? (field.type === 'boolean' ? true : '');
    }

    if (this.selectedResource.endpoint === 'books' && this.editingId) {
      this.setBookSelections(this.editingId);
      this.refreshBookContentRows();
    }

    if (this.selectedResource.endpoint === 'collections' && this.editingId) {
      this.setCollectionSelections(this.editingId);
    }
  }

  deleteRow(row: RowData): void {
    const id = Number(row['id']);
    if (!Number.isFinite(id)) {
      this.error = this.t('badId');
      return;
    }

    this.appService.delete(this.selectedResource.endpoint, id).subscribe({
      next: (response) => {
        if (!response.success) {
          this.error = this.t('deleteFailed');
          return;
        }

        if (this.editingId === id) {
          this.resetForm();
        }

        this.message = this.t('deleted');
        this.loadRows();
      },
      error: () => {
        this.error = this.t('backendDeleteError');
      }
    });
  }

  resetForm(): void {
    this.form = {};
    this.formFiles = {};
    this.clearBookContentFile();
    this.clearBookSelections();
    this.clearCollectionSelections();
    this.clearFilePreviews();
    this.editingId = null;
    for (const field of this.selectedResource.fields) {
      this.form[field.key] = field.type === 'boolean' ? true : '';
    }
  }

  logout(): void {
    this.appService.logout();
    void this.router.navigate(['/login']);
  }

  displayValue(row: RowData, column: string): string {
    if (this.selectedResource.endpoint === 'books' && column === 'authors') {
      return this.bookLinkedLabels(row, 'authors_books', 'authorsId', 'authors');
    }

    if (this.selectedResource.endpoint === 'books' && column === 'categories') {
      return this.bookLinkedLabels(row, 'categories_books', 'categoreisId', 'categories');
    }

    if (this.selectedResource.endpoint === 'collections' && column === 'books') {
      return this.collectionLinkedLabels(row);
    }

    const value = row[column];
    if (value === null || value === undefined || value === '') {
      return '-';
    }

    if (column === 'password') {
      return 'hidden';
    }

    if (this.isBooleanColumn(column)) {
      return this.booleanCellLabel(row, column);
    }

    if (typeof value === 'object') {
      const nested = value as RowData;
      const readable = nested['name'] ?? nested['username'] ?? nested['email'] ?? nested['id'];
      return readable === undefined ? JSON.stringify(value) : String(readable);
    }

    return String(value);
  }

  private buildPayload(): AdminPayload {
    if (this.selectedResource.fields.some((field) => field.type === 'file')) {
      return this.buildFormDataPayload();
    }

    const payload: Record<string, unknown> = {};

    for (const field of this.selectedResource.fields) {
      const value = this.form[field.key];
      if (value === '' || value === null || value === undefined) {
        continue;
      }

      payload[field.key] = this.payloadValue(field, value);
    }

    return payload;
  }

  private buildFormDataPayload(): FormData {
    const payload = new FormData();

    for (const field of this.selectedResource.fields) {
      if (field.type === 'file') {
        const file = this.formFiles[field.key];
        if (file) {
          payload.append(field.key, file);
        }
        continue;
      }

      const value = this.form[field.key];
      if (value === '' || value === null || value === undefined) {
        continue;
      }

      payload.append(field.key, String(this.payloadValue(field, value)));
    }

    return payload;
  }

  private payloadValue(field: AdminField, value: unknown): unknown {
    if (field.type === 'number') {
      return Number(value);
    }

    if (field.type === 'boolean') {
      return this.booleanValue(value);
    }

    return value;
  }

  private withId(payload: AdminPayload, id: number): AdminPayload {
    if (payload instanceof FormData) {
      payload.append('id', String(id));
      return payload;
    }

    return { ...payload, id };
  }

  private savedRecordId(data: unknown): number | null {
    if (!data || typeof data !== 'object') {
      return null;
    }

    const id = Number((data as RowData)['id']);
    return Number.isFinite(id) ? id : null;
  }

  private saveBookRelationsIfNeeded(bookId: number | null, onSuccess: () => void): void {
    if (this.selectedResource.endpoint !== 'books' || !bookId) {
      onSuccess();
      return;
    }

    const requests = [
      ...this.buildJunctionRequests('authors_books', 'authorsId', bookId, this.selectedBookAuthorIds),
      ...this.buildJunctionRequests('categories_books', 'categoreisId', bookId, this.selectedBookCategoryIds)
    ];

    if (!requests.length) {
      this.refreshBookRelationRows(onSuccess);
      return;
    }

    forkJoin(requests).subscribe({
      next: (responses) => {
        if (responses.some((response) => !response.success)) {
          this.saving = false;
          this.error = this.t('saveFailed');
          return;
        }

        this.refreshBookRelationRows(onSuccess);
      },
      error: () => {
        this.saving = false;
        this.error = this.t('backendSaveError');
      }
    });
  }

  private saveCollectionRelationsIfNeeded(collectionId: number | null, onSuccess: () => void): void {
    if (this.selectedResource.endpoint !== 'collections' || !collectionId) {
      onSuccess();
      return;
    }

    const requests = this.buildOwnerJunctionRequests(
      'collections_books',
      'collectionsId',
      collectionId,
      'booksId',
      this.selectedCollectionBookIds
    );

    if (!requests.length) {
      this.refreshCollectionRelationRows(onSuccess);
      return;
    }

    forkJoin(requests).subscribe({
      next: (responses) => {
        if (responses.some((response) => !response.success)) {
          this.saving = false;
          this.error = this.t('saveFailed');
          return;
        }

        this.refreshCollectionRelationRows(onSuccess);
      },
      error: () => {
        this.saving = false;
        this.error = this.t('backendSaveError');
      }
    });
  }

  private buildJunctionRequests(endpoint: string, idKey: string, bookId: number, selectedIds: number[]) {
    const rows = this.bookJunctionRows(endpoint, bookId);
    const selectedSet = new Set(selectedIds);
    const requests = [];

    for (const row of rows) {
      const relationId = Number(row[idKey]);
      const rowId = Number(row['id']);
      if (Number.isFinite(rowId) && !selectedSet.has(relationId)) {
        requests.push(this.appService.delete(endpoint, rowId));
      }
    }

    for (const selectedId of selectedIds) {
      const exists = rows.some((row) => Number(row[idKey]) === selectedId);
      if (!exists) {
        requests.push(this.appService.create<RowData>(endpoint, { [idKey]: selectedId, booksId: bookId }));
      }
    }

    return requests;
  }

  private buildOwnerJunctionRequests(endpoint: string, ownerKey: string, ownerId: number, linkedKey: string, selectedIds: number[]) {
    const rows = (this.relationOptions[endpoint] || []).filter((row) => Number(row[ownerKey]) === ownerId);
    const selectedSet = new Set(selectedIds);
    const requests = [];

    for (const row of rows) {
      const linkedId = Number(row[linkedKey]);
      const rowId = Number(row['id']);
      if (Number.isFinite(rowId) && !selectedSet.has(linkedId)) {
        requests.push(this.appService.delete(endpoint, rowId));
      }
    }

    for (const selectedId of selectedIds) {
      const exists = rows.some((row) => Number(row[linkedKey]) === selectedId);
      if (!exists) {
        requests.push(this.appService.create<RowData>(endpoint, { [ownerKey]: ownerId, [linkedKey]: selectedId }));
      }
    }

    return requests;
  }

  private saveBookContentFileIfNeeded(bookId: number | null, onSuccess: () => void): void {
    const kind = this.bookContentKind();
    if (!kind || !bookId) {
      onSuccess();
      return;
    }

    if (this.isImageBookContentKind(kind)) {
      this.saveBookImagesIfNeeded(kind, bookId, onSuccess);
      return;
    }

    if (!this.bookContentFile) {
      onSuccess();
      return;
    }

    const endpoint = `${kind}_books`;
    this.appService.list<RowData>(endpoint).subscribe({
      next: (response) => {
        const rows = response.success && response.datas ? response.datas : [];
        const existing = rows.find((row) => Number(row['booksId']) === bookId);
        const existingId = existing ? Number(existing['id']) : null;
        const payload = this.buildBookContentPayload(bookId);
        const request = existingId && Number.isFinite(existingId)
          ? this.appService.update<RowData>(endpoint, this.withId(payload, existingId))
          : this.appService.create<RowData>(endpoint, payload);

        request.subscribe({
          next: (saveResponse) => {
            if (!saveResponse.success) {
              this.saving = false;
              this.error = this.t('saveFailed');
              return;
            }

            onSuccess();
          },
          error: () => {
            this.saving = false;
            this.error = this.t('backendSaveError');
          }
        });
      },
      error: () => {
        this.saving = false;
        this.error = this.t('backendSaveError');
      }
    });
  }

  private saveBookImagesIfNeeded(kind: BookContentKind, bookId: number, onSuccess: () => void): void {
    if (!this.mangaImageFiles.length) {
      onSuccess();
      return;
    }

    const chapterNumber = this.bookChapterNumber.trim();
    if (!chapterNumber) {
      this.saving = false;
      this.error = this.t('chapterRequired');
      return;
    }

    const endpoint = `${kind}_books`;
    this.appService.list<RowData>(endpoint).subscribe({
      next: (response) => {
        const rows = response.success && response.datas ? response.datas : [];
        const existingRows = rows.filter((row) =>
          Number(row['booksId']) === bookId && String(row['name'] ?? '').trim() === chapterNumber
        );
        const deleteRequests = existingRows
          .map((row) => Number(row['id']))
          .filter((id) => Number.isFinite(id))
          .map((id) => this.appService.delete(endpoint, id));

        const saveImages = () => this.saveBookImageByIndex(endpoint, bookId, chapterNumber, 0, onSuccess);
        if (!deleteRequests.length) {
          saveImages();
          return;
        }

        forkJoin(deleteRequests).subscribe({
          next: (deleteResponses) => {
            if (deleteResponses.some((deleteResponse) => !deleteResponse.success)) {
              this.saving = false;
              this.error = this.t('deleteFailed');
              return;
            }

            saveImages();
          },
          error: () => {
            this.saving = false;
            this.error = this.t('backendDeleteError');
          }
        });
      },
      error: () => {
        this.saving = false;
        this.error = this.t('backendSaveError');
      }
    });
  }

  private saveBookImageByIndex(
    endpoint: string,
    bookId: number,
    chapterNumber: string,
    index: number,
    onSuccess: () => void
  ): void {
    const image = this.mangaImageFiles[index];
    if (!image) {
      onSuccess();
      return;
    }

    this.appService.create<RowData>(endpoint, this.buildBookContentPayload(bookId, image.file, chapterNumber)).subscribe({
      next: (response) => {
        if (!response.success) {
          this.saving = false;
          this.error = this.t('saveFailed');
          return;
        }

        this.saveBookImageByIndex(endpoint, bookId, chapterNumber, index + 1, onSuccess);
      },
      error: () => {
        this.saving = false;
        this.error = this.t('backendSaveError');
      }
    });
  }

  private buildBookContentPayload(bookId: number, file: File | null = this.bookContentFile, name = ''): FormData {
    const payload = new FormData();
    payload.append('booksId', String(bookId));
    if (name) {
      payload.append('name', name);
    }
    if (file) {
      payload.append('file', file);
    }
    return payload;
  }

  private clearBookContentFile(): void {
    this.bookContentFile = null;
    this.bookChapterNumber = '';
    this.bookContentRows = [];
    this.clearMangaImages();
  }

  private refreshBookContentRows(): void {
    const kind = this.bookContentKind();
    const bookId = this.editingId;
    if (!kind || !this.isImageBookContentKind(kind) || !bookId) {
      this.bookContentRows = [];
      return;
    }

    const endpoint = `${kind}_books`;
    this.appService.list<RowData>(endpoint).subscribe({
      next: (response) => {
        if (this.editingId !== bookId || this.bookContentKind() !== kind) {
          return;
        }

        const rows = response.success && response.datas ? response.datas : [];
        this.bookContentRows = rows.filter((row) => Number(row['booksId']) === bookId);
      },
      error: () => {
        if (this.editingId === bookId && this.bookContentKind() === kind) {
          this.bookContentRows = [];
        }
      }
    });
  }

  private clearMangaImages(): void {
    for (const image of this.mangaImageFiles) {
      URL.revokeObjectURL(image.previewUrl);
    }

    this.mangaImageFiles = [];
  }

  private toggleSelection(values: number[], id: number): number[] {
    if (!Number.isFinite(id)) {
      return values;
    }

    return values.includes(id) ? values.filter((value) => value !== id) : [...values, id];
  }

  private booleanValue(value: unknown): boolean {
    if (typeof value === 'boolean') {
      return value;
    }

    if (typeof value === 'number') {
      return value !== 0;
    }

    const normalized = String(value ?? '').trim().toLowerCase();
    return ['true', '1', 'yes', 'on'].includes(normalized);
  }

  private filteredBookLinkOptions(options: RowData[], selectedIds: number[], searchTerm: string): RowData[] {
    const term = searchTerm.trim().toLowerCase();
    if (!term) {
      return [];
    }

    return options
      .filter((option) => !selectedIds.includes(Number(option['id'])))
      .filter((option) => this.relationOptionLabel(option).toLowerCase().includes(term))
      .slice(0, 8);
  }

  private clearBookSelections(): void {
    this.selectedBookAuthorIds = [];
    this.selectedBookCategoryIds = [];
    this.bookAuthorSearch = '';
    this.bookCategorySearch = '';
  }

  private clearCollectionSelections(): void {
    this.selectedCollectionBookIds = [];
    this.collectionBookSearch = '';
  }

  private setBookSelections(bookId: number): void {
    this.selectedBookAuthorIds = this.bookJunctionRows('authors_books', bookId)
      .map((row) => Number(row['authorsId']))
      .filter((id) => Number.isFinite(id));

    this.selectedBookCategoryIds = this.bookJunctionRows('categories_books', bookId)
      .map((row) => Number(row['categoreisId']))
      .filter((id) => Number.isFinite(id));
  }

  private setCollectionSelections(collectionId: number): void {
    this.selectedCollectionBookIds = (this.relationOptions['collections_books'] || [])
      .filter((row) => Number(row['collectionsId']) === collectionId)
      .map((row) => Number(row['booksId']))
      .filter((id) => Number.isFinite(id));
  }

  private bookJunctionRows(endpoint: string, bookId: number): RowData[] {
    return (this.relationOptions[endpoint] || []).filter((row) => Number(row['booksId']) === bookId);
  }

  private bookLinkedLabels(row: RowData, junctionEndpoint: string, idKey: string, optionEndpoint: string): string {
    const bookId = Number(row['id']);
    if (!Number.isFinite(bookId)) {
      return '-';
    }

    const ids = this.bookJunctionRows(junctionEndpoint, bookId).map((item) => Number(item[idKey]));
    const labels = ids
      .map((id) => (this.relationOptions[optionEndpoint] || []).find((option) => Number(option['id']) === id))
      .filter((option): option is RowData => Boolean(option))
      .map((option) => this.relationOptionLabel(option));

    return labels.length ? labels.join(', ') : '-';
  }

  private collectionLinkedLabels(row: RowData): string {
    const collectionId = Number(row['id']);
    if (!Number.isFinite(collectionId)) {
      return '-';
    }

    const ids = (this.relationOptions['collections_books'] || [])
      .filter((item) => Number(item['collectionsId']) === collectionId)
      .map((item) => Number(item['booksId']));

    const labels = ids
      .map((id) => (this.relationOptions['books'] || []).find((option) => Number(option['id']) === id))
      .filter((option): option is RowData => Boolean(option))
      .map((option) => this.relationOptionLabel(option));

    return labels.length ? labels.join(', ') : '-';
  }

  private refreshBookRelationRows(onSuccess?: () => void): void {
    forkJoin([
      this.appService.list<RowData>('authors_books'),
      this.appService.list<RowData>('categories_books')
    ]).subscribe({
      next: ([authorsResponse, categoriesResponse]) => {
        this.relationOptions['authors_books'] = authorsResponse.success && authorsResponse.datas ? authorsResponse.datas : [];
        this.relationOptions['categories_books'] = categoriesResponse.success && categoriesResponse.datas ? categoriesResponse.datas : [];

        if (this.selectedResource.endpoint === 'books' && this.editingId) {
          this.setBookSelections(this.editingId);
        }

        onSuccess?.();
      },
      error: () => {
        this.relationOptions['authors_books'] = [];
        this.relationOptions['categories_books'] = [];
        onSuccess?.();
      }
    });
  }

  private refreshCollectionRelationRows(onSuccess?: () => void): void {
    this.appService.list<RowData>('collections_books').subscribe({
      next: (response) => {
        this.relationOptions['collections_books'] = response.success && response.datas ? response.datas : [];

        if (this.selectedResource.endpoint === 'collections' && this.editingId) {
          this.setCollectionSelections(this.editingId);
        }

        onSuccess?.();
      },
      error: () => {
        this.relationOptions['collections_books'] = [];
        onSuccess?.();
      }
    });
  }

  private imageUrl(value: unknown): string {
    if (typeof value !== 'string' || !value.trim()) {
      return '';
    }

    return this.appService.fileUrl(value.trim());
  }

  private clearFilePreview(fieldKey: string): void {
    const previewUrl = this.filePreviewUrls[fieldKey];
    if (!previewUrl) {
      return;
    }

    URL.revokeObjectURL(previewUrl);
    delete this.filePreviewUrls[fieldKey];
  }

  private clearFilePreviews(): void {
    for (const previewUrl of Object.values(this.filePreviewUrls)) {
      URL.revokeObjectURL(previewUrl);
    }

    this.filePreviewUrls = {};
  }

  private loadRelationOptions(endpoints: string[] = this.relationOptionEndpoints): void {
    for (const endpoint of [...new Set(endpoints)]) {
      this.appService.list<RowData>(endpoint).subscribe({
        next: (response) => {
          this.relationOptions[endpoint] = response.success && response.datas ? response.datas : [];
        },
        error: () => {
          this.relationOptions[endpoint] = [];
        }
      });
    }
  }

  private syncRelationOptions(endpoint: string, rows: RowData[]): void {
    if (this.relationOptionEndpoints.includes(endpoint)) {
      this.relationOptions[endpoint] = rows;
    }
  }

  private updateBookVisibilityLocally(bookId: number, showInApp: boolean): void {
    this.rows = this.rows.map((row) =>
      Number(row['id']) === bookId ? { ...row, show_in_app: showInApp } : row
    );

    this.relationOptions['books'] = (this.relationOptions['books'] || []).map((row) =>
      Number(row['id']) === bookId ? { ...row, show_in_app: showInApp } : row
    );

    if (this.selectedResource.endpoint === 'books' && this.editingId === bookId) {
      this.form['show_in_app'] = showInApp;
    }
  }

  private resourceRelationEndpoints(resource: AdminResource): string[] {
    const endpoints = new Set<string>();

    for (const field of resource.fields) {
      const endpoint = this.relationEndpoint(field.key);
      if (endpoint) {
        endpoints.add(endpoint);
      }
    }

    if (resource.endpoint === 'books') {
      endpoints.add('authors');
      endpoints.add('categories');
      endpoints.add('readers');
    }

    if (resource.endpoint === 'collections') {
      endpoints.add('books');
    }

    endpoints.delete(resource.endpoint);
    return [...endpoints];
  }

  private relationEndpoint(fieldKey: string): string | null {
    const relations: Record<string, string> = {
      rolesId: 'roles',
      authorsId: 'authors',
      readersId: 'readers',
      booksId: 'books',
      categoreisId: 'categories',
      collectionsId: 'collections',
      usersId: 'users'
    };

    return relations[fieldKey] || null;
  }

  private resource(
    endpoint: string,
    label: string,
    fieldData: [string, string, FieldType][],
    columns: string[],
    description: Record<Language, string>
  ): AdminResource {
    return {
      endpoint,
      label,
      fields: fieldData.map(([key, fieldLabel, type]) => ({ key, label: fieldLabel, type })),
      columns,
      description
    };
  }

  private readStoredLanguage(): Language {
    const value = localStorage.getItem('library_admin_language');
    if (value === 'uz') {
      localStorage.setItem('library_admin_language', 'tm');
      return 'tm';
    }
    return value === 'ru' || value === 'tm' || value === 'en' ? value : 'ru';
  }

  private readStoredTheme(): ThemeName {
    const value = localStorage.getItem('library_admin_theme');
    return value === 'dark' || value === 'light' || value === 'amber' ? value : 'dark';
  }
}
