import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

enum AppLanguage { system, russian, english }

extension AppLanguagePresentation on AppLanguage {
  Locale? get locale => switch (this) {
    AppLanguage.system => null,
    AppLanguage.russian => const Locale('ru'),
    AppLanguage.english => const Locale('en'),
  };

  String label(AppLocalizations l10n) => switch (this) {
    AppLanguage.system => l10n.languageSystem,
    AppLanguage.russian => l10n.languageRussian,
    AppLanguage.english => l10n.languageEnglish,
  };
}

class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = [Locale('ru'), Locale('en')];
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ];

  static AppLocalizations of(BuildContext context) {
    final value = Localizations.of<AppLocalizations>(context, AppLocalizations);
    assert(value != null, 'AppLocalizations not found in context');
    return value!;
  }

  bool get _isRu => locale.languageCode == 'ru';

  String get appTitle => _isRu ? 'Библиотека ридеров' : 'Reader Library';
  String get epubReaderTitle => 'EPUB';
  String get pdfReaderTitle => _isRu ? 'PDF-ридер' : 'PDF Reader';
  String get openEpub => _isRu ? 'Открыть EPUB' : 'Open EPUB';
  String get openZipCbz => _isRu ? 'Открыть ZIP/CBZ' : 'Open ZIP/CBZ';
  String get textSize => _isRu ? 'Размер текста' : 'Text size';
  String get textSizeHelp => _isRu
      ? 'Подберите комфортный размер для чтения.'
      : 'Choose a comfortable reading size.';
  String get decrease => _isRu ? 'Уменьшить' : 'Decrease';
  String get increase => _isRu ? 'Увеличить' : 'Increase';
  String get reset => _isRu ? 'Сбросить' : 'Reset';
  String get fullscreen => _isRu ? 'Полный экран' : 'Fullscreen';
  String get collapse => _isRu ? 'Свернуть' : 'Exit fullscreen';
  String get windowMode => _isRu ? 'Окно' : 'Window';
  String get screenMode => _isRu ? 'Экран' : 'Screen';
  String get hidePanel => _isRu ? 'Скрыть панель' : 'Hide panel';
  String get showPanel => _isRu ? 'Показать панель' : 'Show panel';
  String get comicReader => _isRu ? 'Комикс-ридер' : 'Comic reader';
  String get manhwaReader => _isRu ? '\u041c\u0430\u043d\u0445\u0432\u0430' : 'Manhwa';
  String get mangaReader => _isRu ? '\u041c\u0430\u043d\u0433\u0430' : 'Manga';
  String get toc => _isRu ? 'Оглавление' : 'Table of contents';
  String get theme => _isRu ? 'Тема' : 'Theme';
  String get language => _isRu ? 'Язык' : 'Language';
  String get chooseTheme => _isRu ? 'Выберите тему' : 'Choose theme';
  String get chooseLanguage => _isRu ? 'Выберите язык' : 'Choose language';
  String get languageSystem => _isRu ? 'Как в системе' : 'System default';
  String get languageRussian => _isRu ? 'Русский' : 'Russian';
  String get languageEnglish => _isRu ? 'Английский' : 'English';
  String get paperTheme => _isRu ? 'Бумага' : 'Paper';
  String get sepiaTheme => _isRu ? 'Сепия' : 'Sepia';
  String get nightTheme => _isRu ? 'Ночь' : 'Night';

  String get homeHeroTitle => _isRu
      ? 'Чтение EPUB, манги и манхвы в одном месте'
      : 'Read EPUB, manga, and manhwa in one place';
  String get homeHeroSubtitle => _isRu
      ? 'Открывайте локальные книги, переключайтесь между встроенными библиотеками и настраивайте интерфейс под себя.'
      : 'Open local books, browse built-in libraries, and tailor the interface to your reading style.';
  String get quickActions => _isRu ? 'Быстрые действия' : 'Quick actions';
  String get mainMenu => _isRu ? 'Главное меню' : 'Main menu';
  String get mainMenuSubtitle => _isRu
      ? 'Импорт, библиотеки и настройки в одном месте.'
      : 'Import, libraries, and settings in one place.';
  String get openMenu => _isRu ? 'Открыть меню' : 'Open menu';
  String get builtInLibraries =>
      _isRu ? 'Встроенные библиотеки' : 'Built-in libraries';
  String get librariesSection => _isRu ? 'Библиотеки' : 'Libraries';
  String get appearanceSection => _isRu ? 'Настройки интерфейса' : 'Appearance';
  String get dashboardActionEpub => _isRu ? 'Импорт книги' : 'Import a book';
  String get dashboardActionEpubHint => _isRu
      ? 'Откройте локальный EPUB-файл и продолжайте чтение.'
      : 'Open a local EPUB file and continue reading.';
  String get dashboardActionManhwaHint => _isRu
      ? 'Откройте встроенные или локальные ZIP/CBZ-главы.'
      : 'Browse bundled or local ZIP/CBZ chapters.';
  String get dashboardActionMangaHint => _isRu
      ? 'Перейдите в библиотеку манги и откройте главы.'
      : 'Open the manga library and jump into chapters.';
  String get dashboardActionThemeHint =>
      _isRu ? 'Переключите палитру чтения.' : 'Switch the reading palette.';
  String get dashboardActionLanguageHint =>
      _isRu ? 'Смените язык интерфейса.' : 'Change the interface language.';
  String get currentTheme => _isRu ? 'Текущая тема' : 'Current theme';
  String get currentLanguage => _isRu ? 'Текущий язык' : 'Current language';

  String get epubEmptyTitle => 'EPUB';
  String get pdfEmptyTitle => _isRu ? 'PDF-ридер' : 'PDF Reader';
  String get epubEmptyDescription => _isRu
      ? 'Открывает EPUB-файлы, аккуратно показывает изображения, поддерживает оглавление и устойчиво переживает неаккуратную вёрстку внутри книги.'
      : 'Opens EPUB files, keeps images readable, supports tables of contents, and tolerates messy book markup.';
  String get pdfEmptyDescription => _isRu
      ? 'Открывает PDF-книги внутри приложения с масштабированием, прокруткой и переходом по страницам.'
      : 'Opens PDF books in the app with zooming, scrolling, and page navigation.';
  String get featureTolerantHtml =>
      _isRu ? 'Мягкий разбор HTML/XHTML' : 'Tolerant HTML/XHTML parsing';
  String get featureImages =>
      _isRu ? 'Изображения без обрезки' : 'Images without cropping';
  String get featureToc => _isRu ? 'Переход по оглавлению' : 'TOC navigation';
  String get featureThemes =>
      _isRu ? 'Темы и размер текста' : 'Themes and text size';

  String get noExternalLinks => _isRu
      ? 'Внешние ссылки внутри приложения не открываются.'
      : 'External links are not opened inside the app.';
  String get linkNavigationFailed =>
      _isRu ? 'Не удалось перейти по ссылке.' : 'Could not follow the link.';

  String get manhwaNotFound => _isRu ? 'Манхва не найдена' : 'No manhwa found';
  String get mangaNotFound => _isRu ? 'Манга не найдена' : 'No manga found';
  String get manhwaLibraryDescription => _isRu
      ? 'Выберите тайтл из backend или откройте локальный ZIP/CBZ.'
      : 'Choose a title from the backend or open a local ZIP/CBZ.';
  String get mangaLibraryDescription => _isRu
      ? 'Выберите тайтл из backend или откройте локальный ZIP/CBZ.'
      : 'Choose a title from the backend or open a local ZIP/CBZ.';
  String get retry => _isRu ? 'Повторить' : 'Retry';
  String get chaptersTitle => _isRu ? 'Главы' : 'Chapters';
  String get manhwaChaptersTitle => _isRu ? 'Главы манхвы' : 'Manhwa chapters';
  String get previousChapter => _isRu ? 'Предыдущая глава' : 'Previous chapter';
  String get nextChapter => _isRu ? 'Следующая глава' : 'Next chapter';
  String get tryAgain => _isRu ? 'Попробовать снова' : 'Try again';
  String get illustrationLabel => _isRu ? 'Иллюстрация' : 'Illustration';
  String missingIllustration(String label) => _isRu
      ? 'Не удалось показать изображение: $label'
      : 'Could not display image: $label';
  String chaptersCount(int count) => _isRu ? '$count глав' : '$count chapters';
  String pagesCountShort(int count) => _isRu ? '$count стр.' : '$count pages';

  String get loginTitle =>
      _isRu ? 'Ваша библиотека в одном приложении' : 'Your library in one app';
  String get loginSubtitle => _isRu
      ? 'Пока без бэкенда: вход сохраняет локальный профиль на устройстве, а позже вы сможете подключить свою авторизацию.'
      : 'For now this is local-only: sign in stores a profile on this device, and you can wire in your backend later.';
  String get displayNameOptional =>
      _isRu ? 'Имя (необязательно)' : 'Display name (optional)';
  String get emailAddress => _isRu ? 'Почта' : 'Email';
  String get phoneNumber => _isRu ? 'Телефон' : 'Phone number';
  String get password => _isRu ? 'Пароль' : 'Password';
  String get signIn => _isRu ? 'Войти' : 'Sign in';
  String get continueAsGuest =>
      _isRu ? 'Продолжить как гость' : 'Continue as guest';
  String get localProfileHint => _isRu
      ? 'Это временный локальный вход для интерфейса библиотеки.'
      : 'This is a temporary local sign-in for the library interface.';
  String get emailRequired =>
      _isRu ? 'Введите почту' : 'Enter an email address';
  String get phoneRequired =>
      _isRu ? 'Введите номер телефона' : 'Enter a phone number';
  String get invalidEmail =>
      _isRu ? 'Введите корректную почту' : 'Enter a valid email address';
  String get invalidPhone =>
      _isRu ? 'Введите корректный номер' : 'Enter a valid phone number';
  String get passwordRequired => _isRu ? 'Введите пароль' : 'Enter a password';
  String get passwordTooShort => _isRu
      ? 'Пароль должен быть не короче 4 символов'
      : 'Password must be at least 4 characters';
  String get guestUser => _isRu ? 'Гость' : 'Guest';
  String get accountSection => _isRu ? 'Аккаунт' : 'Account';
  String get signOut => _isRu ? 'Выйти' : 'Sign out';
  String get accountStatusLocal =>
      _isRu ? 'Локальный профиль' : 'Local profile';
  String get contactInfo => _isRu ? 'Контакты' : 'Contact info';
  String get editContacts => _isRu ? 'Изменить контакты' : 'Edit contacts';
  String get saveChanges => _isRu ? 'Сохранить' : 'Save changes';
  String get cancelAction => _isRu ? 'Отмена' : 'Cancel';
  String get emailNotSet => _isRu ? 'Почта не указана' : 'Email not set';
  String get phoneNotSet => _isRu ? 'Номер не указан' : 'Phone number not set';
  String get libraryIntroSubtitle => _isRu
      ? 'Открывайте книги, мангу и манхву, переключайтесь между полками и собирайте удобную цифровую библиотеку.'
      : 'Open books, manga, and manhwa, move between shelves, and build a practical digital library.';
  String welcomeUser(String name) =>
      _isRu ? 'Добро пожаловать, $name' : 'Welcome, $name';
  String get libraryOverview => _isRu ? 'Обзор библиотеки' : 'Library overview';
  String get titlesLabel => _isRu ? 'Тайтлы' : 'Titles';
  String get chaptersLabel => _isRu ? 'Главы' : 'Chapters';
  String get formatsLabel => _isRu ? 'Форматы' : 'Formats';
  String get featuredBooks => _isRu ? 'Витрина книг' : 'Featured books';
  String get featuredBooksSubtitle => _isRu
      ? 'Листайте полку как живую витрину библиотеки.'
      : 'Browse a more cinematic front shelf.';
  String get promoBannersTitle => _isRu ? 'Рекламные баннеры' : 'Promo banners';
  String get promoBannersSubtitle => _isRu
      ? 'Быстрые сценарии для чтения и открытия библиотеки.'
      : 'Quick entry points for reading and discovery.';
  String get categoriesTitle => _isRu ? 'Категории' : 'Categories';
  String get categoriesSubtitle => _isRu
      ? 'Быстрый переход по типам и сценариям чтения.'
      : 'Jump across formats and reading moods.';
  String get popularBooksTitle => _isRu ? 'Популярные книги' : 'Popular books';
  String get popularBooksSubtitle => _isRu
      ? 'Самые объёмные и заметные тайтлы на полке.'
      : 'Long-running and standout titles on the shelf.';
  String get collectionsTitle => _isRu ? 'Сборники книг' : 'Book collections';
  String get collectionsSubtitle => _isRu
      ? 'Готовые полки, собранные по настроению.'
      : 'Curated shelves grouped by vibe.';
  String get categoryEpub => _isRu ? 'EPUB' : 'EPUB';
  String get categoryPdf => _isRu ? 'PDF' : 'PDF';
  String get categoryManga => _isRu ? 'Манга' : 'Manga';
  String get categoryManhwa => _isRu ? 'Манхва' : 'Manhwa';
  String get categoryLongReads => _isRu ? 'Длинные серии' : 'Long reads';
  String get categoryCurated => _isRu ? 'Кураторская полка' : 'Curated shelf';
  String get promoImportTitle =>
      _isRu ? 'Загрузите свою книгу' : 'Bring your own book';
  String get promoImportSubtitle => _isRu
      ? 'Импортируйте EPUB и продолжайте читать в том же приложении.'
      : 'Import an EPUB and continue reading in the same app.';
  String get promoComicsTitle =>
      _isRu ? 'Откройте комикс-полку' : 'Open the comic shelf';
  String get promoComicsSubtitle => _isRu
      ? 'Манхва и манга уже собраны в локальной библиотеке.'
      : 'Manhwa and manga are already bundled into the local library.';
  String get promoThemeTitle =>
      _isRu ? 'Настройте атмосферу' : 'Tune the atmosphere';
  String get promoThemeSubtitle => _isRu
      ? 'Смените тему чтения под вечер, день или бумажный стиль.'
      : 'Switch the reading palette for night, day, or paper moods.';
  String get collectionStarterTitle =>
      _isRu ? 'Стартовая полка' : 'Starter shelf';
  String get collectionStarterSubtitle => _isRu
      ? 'Короткие серии, чтобы быстро войти в ритм.'
      : 'Shorter series to get into the flow quickly.';
  String get collectionMarathonTitle =>
      _isRu ? 'Марафон чтения' : 'Reading marathon';
  String get collectionMarathonSubtitle => _isRu
      ? 'Серии на долгую дистанцию и запойное чтение.'
      : 'Long-form series built for binge sessions.';
  String get collectionBlendTitle => _isRu ? 'Смешанная полка' : 'Mixed shelf';
  String get collectionBlendSubtitle => _isRu
      ? 'Манга и манхва в одном аккуратном сборнике.'
      : 'A balanced mix of manga and manhwa.';
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'ru' || locale.languageCode == 'en';

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(
      locale.languageCode == 'ru' ? const Locale('ru') : const Locale('en'),
    );
  }

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}
