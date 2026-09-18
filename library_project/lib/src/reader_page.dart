import 'dart:async';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_localizations.dart';
import 'epub_parser.dart';
import 'library_api.dart';
import 'manhwa_archive.dart';
import 'manhwa_library_page.dart';
import 'manhwa_reader_page.dart';
import 'offline_archive_store.dart';
import 'offline_document_store.dart';
import 'pdf_reader_page.dart';
import 'reader_profile_page.dart';
import 'reader_preferences.dart';
import 'reading_library_store.dart';
import 'reader_theme.dart';
import 'reader_user_session.dart';

class ReaderHomePage extends StatefulWidget {
  const ReaderHomePage({
    super.key,
    required this.themeChoice,
    required this.onThemeChanged,
    required this.fontScale,
    required this.onFontScaleChanged,
    required this.languageChoice,
    required this.onLanguageChanged,
    required this.currentUser,
    required this.onUserChanged,
    required this.onSignOut,
  });

  final ReaderThemeChoice themeChoice;
  final ValueChanged<ReaderThemeChoice> onThemeChanged;
  final double fontScale;
  final ValueChanged<double> onFontScaleChanged;
  final AppLanguage languageChoice;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final ReaderUserSession currentUser;
  final ValueChanged<ReaderUserSession> onUserChanged;
  final VoidCallback onSignOut;

  @override
  State<ReaderHomePage> createState() => _ReaderHomePageState();
}

class _ReaderHomePageState extends State<ReaderHomePage> {
  static const Duration _readerPanelAutoHideDelay = Duration(seconds: 3);

  final EpubParser _parser = EpubParser();
  final ScrollController _scrollController = ScrollController();
  final PageController _featuredBooksController = PageController(
    viewportFraction: 0.84,
  );
  final PageController _newBooksController = PageController(
    viewportFraction: 0.84,
  );
  final PageController _promoBannersController = PageController(
    viewportFraction: 0.92,
  );
  final GlobalKey _htmlAnchorKey = GlobalKey();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ReaderPreferences _preferences = ReaderPreferences();
  final ReadingLibraryStore _readingStore = ReadingLibraryStore();

  EpubBook? _book;
  bool _isLoading = false;
  bool _isFullscreenReading = false;
  bool _isReaderPanelVisible = true;
  bool _isBundledSeriesLoading = true;
  String? _homeConnectionError;
  String? _errorMessage;
  int _currentChapterIndex = 0;
  int? _scrubberPreviewIndex;
  String? _pendingAnchorId;
  double _horizontalSwipeDragOffset = 0;
  Timer? _readerPanelAutoHideTimer;
  int _featuredBookIndex = 0;
  int _newBookIndex = 0;
  int _promoBannerIndex = 0;
  List<_BundledSeriesPreview> _bundledManhwaSeries = const [];
  List<_BundledSeriesPreview> _bundledMangaSeries = const [];
  List<_BundledSeriesPreview> _bundledEpubSeries = const [];
  List<_BundledSeriesPreview> _bundledPdfSeries = const [];
  List<RemoteCategory> _backendCategories = const [];
  List<RemoteBookCollection> _backendCollections = const [];
  List<ReadingListBook> _readLaterBooks = const [];
  List<ReadingBookmark> _savedBookmarks = const [];
  Set<String> _selectedHomeCategoryIds = <String>{};
  bool _homeCategoryPreferencesLoaded = false;
  bool _categoryPickerScheduled = false;

  ReaderPalette get _palette => widget.themeChoice.palette;
  double get _fontScale => widget.fontScale;

  String _userLabel(AppLocalizations l10n) {
    if (widget.currentUser.isGuest) {
      return l10n.guestUser;
    }

    final name = widget.currentUser.displayName.trim();
    return name.isEmpty ? _unnamedUserLabel(l10n) : name;
  }

  String _unnamedUserLabel(AppLocalizations l10n) =>
      l10n.locale.languageCode == 'ru'
      ? '\u041f\u043e\u043b\u044c\u0437\u043e\u0432\u0430\u0442\u0435\u043b\u044c'
      : 'User';

  String _userSubtitle(AppLocalizations l10n) => widget.currentUser.isGuest
      ? l10n.accountStatusLocal
      : (widget.currentUser.email.trim().isNotEmpty
            ? widget.currentUser.email.trim()
            : l10n.accountStatusLocal);

  String _userPhoneSubtitle(AppLocalizations l10n) {
    final phone = widget.currentUser.phoneNumber.trim();
    return phone.isEmpty ? l10n.phoneNotSet : phone;
  }

  String _userInitials(AppLocalizations l10n) {
    final source = _userLabel(l10n).trim();
    if (source.isEmpty) {
      return 'R';
    }

    final parts = source.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
    final firstTwo = parts.take(2).toList();
    if (firstTwo.isEmpty) {
      return source.substring(0, 1).toUpperCase();
    }

    return firstTwo.map((part) => part.substring(0, 1).toUpperCase()).join();
  }

  List<_BundledSeriesPreview> get _allBundledSeries => [
    ..._bundledManhwaSeries,
    ..._bundledMangaSeries,
    ..._bundledEpubSeries,
    ..._bundledPdfSeries,
  ];

  List<_BundledSeriesPreview> _seriesSortedByChaptersDesc() {
    final items = _allBundledSeries.toList()
      ..sort((a, b) {
        final chapterCompare = b.displayChapterCount.compareTo(
          a.displayChapterCount,
        );
        if (chapterCompare != 0) {
          return chapterCompare;
        }
        return naturalCompare(a.title, b.title);
      });
    return items;
  }

  List<_BundledSeriesPreview> _seriesSortedByNewest() {
    final items = _allBundledSeries.toList()
      ..sort((a, b) {
        final idCompare = b.bookId.compareTo(a.bookId);
        if (idCompare != 0) {
          return idCompare;
        }
        return naturalCompare(a.title, b.title);
      });
    return items;
  }

  IconData _iconForSeriesKind(ArchiveLibraryKind kind) => switch (kind) {
    ArchiveLibraryKind.manhwa => Icons.collections_bookmark_rounded,
    ArchiveLibraryKind.manga => Icons.photo_library_rounded,
    ArchiveLibraryKind.epub => Icons.menu_book_rounded,
    ArchiveLibraryKind.pdf => Icons.picture_as_pdf_rounded,
  };

  Color _accentForSeriesKind(ArchiveLibraryKind kind) => switch (kind) {
    ArchiveLibraryKind.manhwa => _palette.accent,
    ArchiveLibraryKind.manga => _palette.titleColor.withValues(alpha: 0.82),
    ArchiveLibraryKind.epub => const Color(0xFF4D7C9D),
    ArchiveLibraryKind.pdf => const Color(0xFFD95757),
  };

  EpubChapter? get _currentChapter {
    final book = _book;
    if (book == null || book.chapters.isEmpty) {
      return null;
    }
    if (_currentChapterIndex < 0 ||
        _currentChapterIndex >= book.chapters.length) {
      return null;
    }
    return book.chapters[_currentChapterIndex];
  }

  String _chapterDisplayTitleAt(int index) {
    final book = _book;
    if (book == null || index < 0 || index >= book.chapters.length) {
      return '';
    }

    final chapter = book.chapters[index];
    for (final entry in book.tocEntries) {
      if (entry.path != chapter.path) {
        continue;
      }
      final label = _readableTocLabel(entry);
      if (label != null) {
        return label;
      }
    }

    final nearestLabel = _nearestReadableTocLabel(book, index);
    if (nearestLabel != null) {
      return nearestLabel;
    }

    final chapterTitle = chapter.title.trim();
    if (chapterTitle.isNotEmpty &&
        !_isTechnicalChapterLabel(chapterTitle, chapter.path)) {
      return chapterTitle;
    }

    return _ReadingLibraryCopy.chapterNumber(context, index);
  }

  String? _nearestReadableTocLabel(EpubBook book, int chapterIndex) {
    String? previousLabel;
    var previousDistance = 1 << 30;
    String? nextLabel;
    var nextDistance = 1 << 30;

    for (final entry in book.tocEntries) {
      final label = _readableTocLabel(entry);
      if (label == null) {
        continue;
      }

      final entryIndex = book.chapterIndexByPath[entry.path];
      if (entryIndex == null) {
        continue;
      }

      if (entryIndex <= chapterIndex) {
        final distance = chapterIndex - entryIndex;
        if (distance < previousDistance) {
          previousDistance = distance;
          previousLabel = label;
        }
      } else {
        final distance = entryIndex - chapterIndex;
        if (distance < nextDistance) {
          nextDistance = distance;
          nextLabel = label;
        }
      }
    }

    return previousLabel ?? nextLabel;
  }

  String? _readableTocLabel(EpubTocEntry entry) {
    final label = entry.label.trim();
    if (label.isEmpty || _isTechnicalChapterLabel(label, entry.path)) {
      return null;
    }

    return label;
  }

  bool _isTechnicalChapterLabel(String label, String chapterPath) {
    final compactLabel = _compactTechnicalLabel(label);
    if (compactLabel.isEmpty) {
      return true;
    }

    final pathPart = chapterPath.split(RegExp(r'[\\/]')).last;
    final pathStem = pathPart.replaceFirst(RegExp(r'\.[^.]+$'), '');
    if (compactLabel == _compactTechnicalLabel(pathStem)) {
      return true;
    }

    return RegExp(r'^part0+\d+$').hasMatch(compactLabel) ||
        RegExp(r'^part\d{4,}$').hasMatch(compactLabel) ||
        RegExp(r'^x?html0*\d+$').hasMatch(compactLabel) ||
        RegExp(r'^body0*\d+$').hasMatch(compactLabel) ||
        RegExp(r'^section0*\d+$').hasMatch(compactLabel) ||
        RegExp(r'^text0*\d+$').hasMatch(compactLabel);
  }

  String _compactTechnicalLabel(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\.[a-z0-9]+$'), '')
        .replaceAll(RegExp(r'[\s_\-./\\]+'), '');
  }

  @override
  void initState() {
    super.initState();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    unawaited(_loadHomeCategoryPreferences());
    unawaited(_loadBundledSeries());
    unawaited(_loadSavedReadingLibrary());
  }

  @override
  void didUpdateWidget(covariant ReaderHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUser.categoryPickerPending !=
        widget.currentUser.categoryPickerPending) {
      _scheduleCategoryPickerAfterRegistration();
    }
  }

  Future<void> _loadHomeCategoryPreferences() async {
    final ids = await _preferences.loadHomeCategoryIds();
    if (!mounted) {
      return;
    }

    setState(() {
      _selectedHomeCategoryIds = ids.toSet();
      _homeCategoryPreferencesLoaded = true;
    });
    _scheduleCategoryPickerAfterRegistration();
  }

  void _scheduleCategoryPickerAfterRegistration() {
    if (!_homeCategoryPreferencesLoaded ||
        _categoryPickerScheduled ||
        widget.currentUser.isGuest ||
        !widget.currentUser.categoryPickerPending) {
      return;
    }

    _categoryPickerScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_showHomeCategoryPicker());
    });
  }

  void _cancelReaderPanelAutoHideTimer() {
    _readerPanelAutoHideTimer?.cancel();
    _readerPanelAutoHideTimer = null;
  }

  void _restartReaderPanelAutoHideTimer() {
    _cancelReaderPanelAutoHideTimer();

    if (!mounted || _currentChapter == null || !_isReaderPanelVisible) {
      return;
    }

    _readerPanelAutoHideTimer = Timer(_readerPanelAutoHideDelay, () {
      if (!mounted || !_isReaderPanelVisible) {
        return;
      }

      setState(() {
        _isReaderPanelVisible = false;
      });
    });
  }

  void _handleReaderActivity() {
    if (_currentChapter == null || !_isReaderPanelVisible) {
      return;
    }

    _restartReaderPanelAutoHideTimer();
  }

  void _hideReaderPanel() {
    if (!_isReaderPanelVisible) {
      return;
    }

    _cancelReaderPanelAutoHideTimer();
    setState(() {
      _isReaderPanelVisible = false;
    });
  }

  void _showReaderPanel({bool restartAutoHide = true}) {
    if (!_isReaderPanelVisible) {
      setState(() {
        _isReaderPanelVisible = true;
      });
    }

    if (restartAutoHide) {
      _restartReaderPanelAutoHideTimer();
    }
  }

  Future<void> _pickEpubFile() async {
    _cancelReaderPanelAutoHideTimer();
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['epub'],
        withData: false,
      );

      if (!mounted) {
        return;
      }

      if (result == null || result.files.single.path == null) {
        setState(() {
          _isLoading = false;
        });
        _restartReaderPanelAutoHideTimer();
        return;
      }

      final book = await _parser.parseFile(result.files.single.path!);
      setState(() {
        _book = book;
        _isLoading = false;
        _isReaderPanelVisible = true;
        _currentChapterIndex = book.suggestedStartChapterIndex;
        _scrubberPreviewIndex = null;
        _pendingAnchorId = null;
      });
      _restartReaderPanelAutoHideTimer();
      _scrollToTop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _isLoading = false;
        _errorMessage = message;
      });
      _showReadingLibrarySnack(message);
      _restartReaderPanelAutoHideTimer();
    }
  }

  Future<void> _openEpubFromPath(String sourcePath, {int? chapterIndex}) async {
    if (sourcePath.trim().isEmpty) {
      _showReadingLibrarySnack(_ReadingLibraryCopy.fileNotFound(context));
      return;
    }

    _cancelReaderPanelAutoHideTimer();
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    try {
      final book = await _parser.parseFile(sourcePath);
      if (!mounted) {
        return;
      }

      final nextIndex = book.chapters.isEmpty
          ? 0
          : (chapterIndex == null
                ? book.suggestedStartChapterIndex
                : chapterIndex.clamp(0, book.chapters.length - 1).toInt());
      setState(() {
        _book = book;
        _isLoading = false;
        _isReaderPanelVisible = true;
        _currentChapterIndex = nextIndex;
        _scrubberPreviewIndex = null;
        _pendingAnchorId = null;
      });
      _restartReaderPanelAutoHideTimer();
      _scrollToTop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _isLoading = false;
        _errorMessage = message;
      });
      _showReadingLibrarySnack(message);
      _restartReaderPanelAutoHideTimer();
    }
  }

  bool _isRemoteSource(String sourcePath) {
    final value = sourcePath.trim().toLowerCase();
    return value.startsWith('http://') || value.startsWith('https://');
  }

  Future<void> _openEpubFromSource(
    String sourcePath, {
    int? chapterIndex,
    String? fileName,
  }) async {
    if (_isRemoteSource(sourcePath)) {
      await _openEpubFromRemote(
        sourcePath,
        chapterIndex: chapterIndex,
        fileName: fileName,
      );
      return;
    }

    await _openEpubFromPath(sourcePath, chapterIndex: chapterIndex);
  }

  Future<void> _openEpubFromRemote(
    String sourceUrl, {
    int? chapterIndex,
    String? fileName,
  }) async {
    if (sourceUrl.trim().isEmpty) {
      _showReadingLibrarySnack(_ReadingLibraryCopy.fileNotFound(context));
      return;
    }

    _cancelReaderPanelAutoHideTimer();
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    try {
      final bytes = await LibraryApiClient.instance.downloadFileBytes(
        sourceUrl,
      );
      final book = _parser.parseBytes(
        bytes,
        sourcePath: sourceUrl,
        fileName: fileName ?? sourceUrl.split('/').last,
      );
      if (!mounted) {
        return;
      }

      final nextIndex = book.chapters.isEmpty
          ? 0
          : (chapterIndex == null
                ? book.suggestedStartChapterIndex
                : chapterIndex.clamp(0, book.chapters.length - 1).toInt());
      setState(() {
        _book = book;
        _isLoading = false;
        _isReaderPanelVisible = true;
        _currentChapterIndex = nextIndex;
        _scrubberPreviewIndex = null;
        _pendingAnchorId = null;
      });
      _restartReaderPanelAutoHideTimer();
      _scrollToTop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _isLoading = false;
        _errorMessage = message;
      });
      _showReadingLibrarySnack(message);
      _restartReaderPanelAutoHideTimer();
    }
  }

  Future<void> _loadSavedReadingLibrary() async {
    final readLater = await _readingStore.loadReadLater();
    final bookmarks = await _readingStore.loadBookmarks();
    if (!mounted) {
      return;
    }

    setState(() {
      _readLaterBooks = readLater;
      _savedBookmarks = bookmarks;
    });
  }

  Future<void> _refreshHome() async {
    await Future.wait([_loadBundledSeries(), _loadSavedReadingLibrary()]);
  }

  String _epubBookId(EpubBook book) {
    final source = (book.sourcePath?.trim().isNotEmpty ?? false)
        ? book.sourcePath!.trim()
        : book.fileName;
    return 'epub:$source';
  }

  String _seriesBookId(_BundledSeriesPreview series) =>
      'archive:${series.kind.name}:${series.id}';

  bool _isReadLaterBook(String id) {
    return _readLaterBooks.any((item) => item.id == id);
  }

  ReadingListBook _readingListBookForEpub(EpubBook book) {
    return ReadingListBook(
      id: _epubBookId(book),
      title: book.title,
      author: book.author?.trim().isNotEmpty == true
          ? book.author!.trim()
          : _ReadingLibraryCopy.unknownAuthor(context),
      category: 'EPUB',
      sourceType: 'epub',
      sourcePath: book.sourcePath ?? '',
      chapterCount: book.chapters.length,
      addedAt: DateTime.now(),
    );
  }

  Future<void> _toggleReadLaterBook(ReadingListBook book) async {
    final exists = _isReadLaterBook(book.id);
    if (exists) {
      await _readingStore.removeReadLater(book.id);
    } else {
      await _readingStore.addOrUpdateReadLater(book);
    }

    await _loadSavedReadingLibrary();
    if (!mounted) {
      return;
    }
    _showReadingLibrarySnack(
      exists
          ? _ReadingLibraryCopy.removedFromReadLater(context)
          : _ReadingLibraryCopy.addedToReadLater(context),
    );
  }

  Future<void> _saveCurrentEpubReadLater() async {
    final book = _book;
    if (book == null) {
      return;
    }
    await _toggleReadLaterBook(_readingListBookForEpub(book));
  }

  Future<void> _saveCurrentEpubBookmark() async {
    final book = _book;
    final chapter = _currentChapter;
    if (book == null || chapter == null) {
      return;
    }

    final bookId = _epubBookId(book);
    await _readingStore.addOrUpdateBookmark(
      ReadingBookmark(
        id: '$bookId:${chapter.path}',
        bookId: bookId,
        bookTitle: book.title,
        chapterTitle: chapter.title,
        chapterIndex: _currentChapterIndex,
        chapterPath: chapter.path,
        sourceType: 'epub',
        sourcePath: book.sourcePath ?? '',
        createdAt: DateTime.now(),
      ),
    );
    await _loadSavedReadingLibrary();
    if (mounted) {
      _showReadingLibrarySnack(_ReadingLibraryCopy.bookmarkSaved(context));
    }
  }

  Future<void> _openSavedReadingPage() async {
    await _loadSavedReadingLibrary();
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SavedReadingPage(
          palette: _palette,
          readLaterBooks: _readLaterBooks,
          bookmarks: _savedBookmarks,
          onOpenBook: _openStoredReadLater,
          onRemoveBook: _removeReadLater,
          onOpenBookmark: _openStoredBookmark,
          onRemoveBookmark: _removeBookmark,
        ),
      ),
    );

    if (mounted) {
      await _loadSavedReadingLibrary();
    }
  }

  Future<void> _openDownloadedArchivePage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _DownloadedArchivePage(
          palette: _palette,
          onOpenEpub: (document) => _openEpubFromPath(document.localPath),
          onOpenPdf: (document) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PdfReaderPage(
                title: document.title,
                pdfUrl: document.localPath,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _removeReadLater(String id) async {
    await _readingStore.removeReadLater(id);
    await _loadSavedReadingLibrary();
  }

  Future<void> _removeBookmark(String id) async {
    await _readingStore.removeBookmark(id);
    await _loadSavedReadingLibrary();
  }

  Future<void> _closeCurrentRouteBeforeOpening() async {
    final navigator = Navigator.of(context);
    if (!navigator.canPop()) {
      return;
    }

    navigator.pop();
    await Future<void>.delayed(const Duration(milliseconds: 140));
  }

  void _openCatalogBookDetails(_BundledSeriesPreview series) {
    unawaited(_openCatalogBookDetailsLoaded(series));
  }

  Future<void> _openCatalogBookDetailsLoaded(
    _BundledSeriesPreview series,
  ) async {
    final loadedSeries = await _ensureSeriesChaptersLoaded(series);
    if (!mounted) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _BookDetailsPage(
          palette: _palette,
          series: loadedSeries,
          popularSeries: _seriesSortedByChaptersDesc()
              .where((item) => item.id != loadedSeries.id)
              .take(6)
              .toList(),
          onPopularSeriesTap: _openCatalogBookDetails,
          onOpenEpub: _openCatalogEpubSeries,
          onOpenPdf: _openCatalogPdfSeries,
          onSeriesChanged: _updateCatalogSeries,
        ),
      ),
    );
  }

  void _updateCatalogSeries(_BundledSeriesPreview series) {
    if (!mounted) {
      return;
    }

    setState(() {
      _replaceLoadedSeries(series);
    });
  }

  Future<void> _openCatalogEpubSeries(_BundledSeriesPreview series) async {
    if (series.epubFileUrl.trim().isEmpty) {
      _showReadingLibrarySnack(_ReadingLibraryCopy.fileNotFound(context));
      return;
    }

    await _openEpubFromRemote(
      series.epubFileUrl,
      fileName: '${series.title}.epub',
    );
  }

  Future<void> _openCatalogPdfSeries(_BundledSeriesPreview series) async {
    if (series.pdfFileUrl.trim().isEmpty) {
      _showReadingLibrarySnack(_ReadingLibraryCopy.fileNotFound(context));
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PdfReaderPage(title: series.title, pdfUrl: series.pdfFileUrl),
      ),
    );
  }

  Future<void> _openStoredReadLater(ReadingListBook book) async {
    await _closeCurrentRouteBeforeOpening();
    if (!mounted) {
      return;
    }

    if (book.sourceType == 'epub') {
      await _openEpubFromSource(book.sourcePath, fileName: book.title);
      return;
    }

    if (book.sourceType == 'pdf') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              PdfReaderPage(title: book.title, pdfUrl: book.sourcePath),
        ),
      );
      return;
    }

    if (_isBundledSeriesLoading) {
      await _loadBundledSeries();
    }
    final series = _findSeriesForStoredBook(book);
    if (series == null) {
      _showReadingLibrarySnack(_ReadingLibraryCopy.bookNotFound(context));
      return;
    }
    await _openBundledSeries(series);
  }

  Future<void> _openStoredBookmark(ReadingBookmark bookmark) async {
    await _closeCurrentRouteBeforeOpening();
    if (!mounted) {
      return;
    }

    if (bookmark.sourceType == 'epub') {
      await _openEpubFromSource(
        bookmark.sourcePath,
        chapterIndex: bookmark.chapterIndex,
        fileName: bookmark.bookTitle,
      );
      return;
    }

    if (_isBundledSeriesLoading) {
      await _loadBundledSeries();
    }
    final series = _findSeriesForBookmark(bookmark);
    if (series == null) {
      _showReadingLibrarySnack(_ReadingLibraryCopy.bookNotFound(context));
      return;
    }
    final loadedSeries = await _ensureSeriesChaptersLoaded(series);
    if (loadedSeries.chapters.isEmpty) {
      _showReadingLibrarySnack(_ReadingLibraryCopy.bookNotFound(context));
      return;
    }

    final exactIndex = loadedSeries.chapters.indexWhere(
      (item) =>
          item.sourcePath == bookmark.chapterPath ||
          item.sourcePath == bookmark.sourcePath,
    );
    final initialIndex = exactIndex >= 0
        ? exactIndex
        : bookmark.chapterIndex
              .clamp(0, loadedSeries.chapters.length - 1)
              .toInt();

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ManhwaReaderPage(
          libraryItems: loadedSeries.chapters,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  _BundledSeriesPreview? _findSeriesForStoredBook(ReadingListBook book) {
    for (final series in _allBundledSeries) {
      if (_seriesBookId(series) == book.id || series.id == book.sourcePath) {
        return series;
      }
    }
    return null;
  }

  int? _remoteBookIdFromArchivePath(String value) {
    final match = RegExp(
      r'remote:(?:manga|manhwa):(\d+)(?::|$)',
    ).firstMatch(value);
    return match == null ? null : int.tryParse(match.group(1) ?? '');
  }

  _BundledSeriesPreview? _findSeriesForBookmark(ReadingBookmark bookmark) {
    final remoteBookId =
        _remoteBookIdFromArchivePath(bookmark.sourcePath) ??
        _remoteBookIdFromArchivePath(bookmark.chapterPath) ??
        _remoteBookIdFromArchivePath(bookmark.bookId);
    for (final series in _allBundledSeries) {
      if (_seriesBookId(series) == bookmark.bookId ||
          series.id == bookmark.sourcePath ||
          (remoteBookId != null && series.bookId == remoteBookId) ||
          series.chapters.any(
            (item) =>
                item.sourcePath == bookmark.chapterPath ||
                item.sourcePath == bookmark.sourcePath,
          )) {
        return series;
      }
    }
    return null;
  }

  void _showReadingLibrarySnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadBundledSeries() async {
    if (mounted) {
      setState(() {
        _isBundledSeriesLoading = true;
        _homeConnectionError = null;
      });
    }

    try {
      final catalog = await LibraryApiClient.instance.loadCatalogSeries();
      var backendCategories = const <RemoteCategory>[];
      try {
        backendCategories = await LibraryApiClient.instance.loadCategories();
      } catch (_) {
        backendCategories = const [];
      }
      var backendCollections = const <RemoteBookCollection>[];
      try {
        backendCollections = await LibraryApiClient.instance
            .loadBookCollections();
      } catch (_) {
        backendCollections = const [];
      }

      final manhwa = _remoteSeriesToPreviews(
        catalog.where((series) => series.kind == RemoteArchiveKind.manhwa),
        ArchiveLibraryKind.manhwa,
      );
      final manga = _remoteSeriesToPreviews(
        catalog.where((series) => series.kind == RemoteArchiveKind.manga),
        ArchiveLibraryKind.manga,
      );
      final epub = _remoteSeriesToPreviews(
        catalog.where((series) => series.kind == RemoteArchiveKind.epub),
        ArchiveLibraryKind.epub,
      );
      final pdf = _remoteSeriesToPreviews(
        catalog.where((series) => series.kind == RemoteArchiveKind.pdf),
        ArchiveLibraryKind.pdf,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _bundledManhwaSeries = manhwa;
        _bundledMangaSeries = manga;
        _bundledEpubSeries = epub;
        _bundledPdfSeries = pdf;
        _backendCategories = backendCategories;
        _backendCollections = backendCollections;
        _isBundledSeriesLoading = false;
        _homeConnectionError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isBundledSeriesLoading = false;
        _homeConnectionError = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<List<_BundledSeriesPreview>> _loadRemoteSeries(
    RemoteArchiveKind remoteKind,
  ) async {
    final series = await LibraryApiClient.instance.loadArchiveSeries(
      remoteKind,
    );
    final kind = switch (remoteKind) {
      RemoteArchiveKind.manhwa => ArchiveLibraryKind.manhwa,
      RemoteArchiveKind.manga => ArchiveLibraryKind.manga,
      RemoteArchiveKind.epub => ArchiveLibraryKind.epub,
      RemoteArchiveKind.pdf => ArchiveLibraryKind.pdf,
    };

    return _remoteSeriesToPreviews(series, kind);
  }

  List<_BundledSeriesPreview> _remoteSeriesToPreviews(
    Iterable<RemoteArchiveSeries> series,
    ArchiveLibraryKind kind,
  ) {
    return [
      for (final item in series)
        _BundledSeriesPreview(
          id: item.id,
          bookId: item.bookId,
          title: item.title,
          description: item.description,
          language: item.language,
          coverImageUrl: item.imageUrl,
          authorNames: item.authors,
          categoryNames: item.categories,
          releaseYear: item.releaseYear,
          recommendedAge: item.recommendedAge,
          likesTotal: item.likesTotal,
          dislikesTotal: item.dislikesTotal,
          epubFileUrl: item.epubFileUrl,
          pdfFileUrl: item.pdfFileUrl,
          chapterCount: item.chapterCount,
          chapters: [
            for (final chapter in item.chapters)
              ManhwaLibraryItem.network(
                sourcePath: chapter.sourcePath,
                title: chapter.title,
                networkPages: chapter.pages,
              ),
          ],
          kind: kind,
        ),
    ];
  }

  RemoteArchiveKind _remoteKindForSeries(_BundledSeriesPreview series) =>
      switch (series.kind) {
        ArchiveLibraryKind.manhwa => RemoteArchiveKind.manhwa,
        ArchiveLibraryKind.manga => RemoteArchiveKind.manga,
        ArchiveLibraryKind.epub => RemoteArchiveKind.epub,
        ArchiveLibraryKind.pdf => RemoteArchiveKind.pdf,
      };

  RemoteArchiveSeries _previewToRemoteSeries(_BundledSeriesPreview series) {
    return RemoteArchiveSeries(
      id: series.id,
      bookId: series.bookId,
      kind: _remoteKindForSeries(series),
      title: series.title,
      description: series.description,
      language: series.language,
      imageUrl: series.coverImageUrl,
      authors: series.authorNames,
      categories: series.categoryNames,
      releaseYear: series.releaseYear,
      recommendedAge: series.recommendedAge,
      likesTotal: series.likesTotal,
      dislikesTotal: series.dislikesTotal,
      chapterCount: series.chapterCount,
      chapters: const [],
      epubFileUrl: series.epubFileUrl,
      pdfFileUrl: series.pdfFileUrl,
    );
  }

  void _replaceLoadedSeries(_BundledSeriesPreview loaded) {
    List<_BundledSeriesPreview> replaceIn(List<_BundledSeriesPreview> items) {
      return [
        for (final item in items)
          if (item.id == loaded.id) loaded else item,
      ];
    }

    _bundledManhwaSeries = replaceIn(_bundledManhwaSeries);
    _bundledMangaSeries = replaceIn(_bundledMangaSeries);
    _bundledEpubSeries = replaceIn(_bundledEpubSeries);
    _bundledPdfSeries = replaceIn(_bundledPdfSeries);
  }

  Future<_BundledSeriesPreview> _ensureSeriesChaptersLoaded(
    _BundledSeriesPreview series,
  ) async {
    if (series.isEpub ||
        series.isPdf ||
        series.chapters.isNotEmpty ||
        series.chapterCount == 0) {
      return series;
    }

    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    try {
      final remote = await LibraryApiClient.instance.loadSeriesChapters(
        _previewToRemoteSeries(series),
      );
      final loaded = _remoteSeriesToPreviews([remote], series.kind).first;

      if (!mounted) {
        return loaded;
      }

      setState(() {
        _replaceLoadedSeries(loaded);
        _isLoading = false;
      });
      return loaded;
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _showReadingLibrarySnack(
          error.toString().replaceFirst('Exception: ', ''),
        );
      }
      return series;
    }
  }

  Future<void> _openBundledSeries(_BundledSeriesPreview series) async {
    if (series.isEpub) {
      await _openCatalogEpubSeries(series);
      return;
    }

    if (series.isPdf) {
      await _openCatalogPdfSeries(series);
      return;
    }

    final loadedSeries = await _ensureSeriesChaptersLoaded(series);
    if (loadedSeries.chapters.isEmpty) {
      _showReadingLibrarySnack(_ReadingLibraryCopy.bookNotFound(context));
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArchiveSeriesPage(
          seriesId: loadedSeries.id,
          title: loadedSeries.title,
          kind: _remoteKindForSeries(loadedSeries),
          coverImageUrl: loadedSeries.coverImageUrl,
          chapters: loadedSeries.chapters,
        ),
      ),
    );
  }

  void _goToChapter(int index, {String? anchorId}) {
    final book = _book;
    if (book == null || index < 0 || index >= book.chapters.length) {
      return;
    }

    setState(() {
      _currentChapterIndex = index;
      _pendingAnchorId = anchorId;
    });

    _scheduleAnchorJump(anchorId);
  }

  void _goToAdjacentChapter(int offset) {
    final book = _book;
    if (book == null || book.chapters.length < 2) {
      return;
    }

    final nextIndex = _currentChapterIndex + offset;
    if (nextIndex < 0 || nextIndex >= book.chapters.length) {
      return;
    }

    _goToChapter(nextIndex);
  }

  void _openTocEntry(EpubTocEntry entry) {
    final book = _book;
    if (book == null) {
      return;
    }

    final index = book.chapterIndexByPath[entry.path];
    if (index == null) {
      return;
    }

    _scaffoldKey.currentState?.closeDrawer();
    _showReaderPanel();
    _goToChapter(index, anchorId: entry.fragment);
  }

  void _openTocDrawer() {
    _handleReaderActivity();
    _scaffoldKey.currentState?.openDrawer();
  }

  Future<void> _openManhwaLibrary() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ArchiveLibraryPage.manhwa(),
      ),
    );
  }

  Future<void> _openMangaLibrary() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ArchiveLibraryPage.manga()),
    );
  }

  List<_LibraryCategoryEntry> _buildCatalogCategories(BuildContext context) {
    final grouped = <String, List<_BundledSeriesPreview>>{};
    for (final series in _allBundledSeries) {
      final names = series.categoryNames.isEmpty
          ? [_kindLabelForSeries(context, series.kind)]
          : series.categoryNames;
      for (final name in names) {
        grouped.putIfAbsent(name, () => <_BundledSeriesPreview>[]).add(series);
      }
    }

    final categories =
        grouped.entries
            .map(
              (entry) => _LibraryCategoryEntry(
                title: entry.key,
                description: _CatalogCopy.booksCount(
                  context,
                  entry.value.length,
                ),
                icon: Icons.category_rounded,
                accent: _authorAccentForName(entry.key),
                series: entry.value
                  ..sort((a, b) => naturalCompare(a.title, b.title)),
              ),
            )
            .toList()
          ..sort((a, b) => naturalCompare(a.title, b.title));

    return categories;
  }

  List<_LibraryAuthorEntry> _buildCatalogAuthors(BuildContext context) {
    final grouped = <String, List<_BundledSeriesPreview>>{};
    for (final series in _allBundledSeries) {
      final authors = series.authorNames.isEmpty
          ? [_authorNameForSeries(context, series)]
          : series.authorNames;
      for (final author in authors) {
        grouped
            .putIfAbsent(author, () => <_BundledSeriesPreview>[])
            .add(series);
      }
    }

    final authors =
        grouped.entries
            .map(
              (entry) => _LibraryAuthorEntry(
                name: entry.key,
                description: _authorDescriptionForSeries(
                  context,
                  entry.key,
                  entry.value,
                ),
                imageIcon: _authorImageIcon(entry.value),
                imageAccent: _authorAccentForName(entry.key),
                series: entry.value
                  ..sort((a, b) => naturalCompare(a.title, b.title)),
              ),
            )
            .toList()
          ..sort((a, b) => naturalCompare(a.name, b.name));

    return authors;
  }

  Future<void> _openCatalogSearchPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _LibrarySearchPage(
          palette: _palette,
          series: _seriesSortedByChaptersDesc(),
          categories: _buildCatalogCategories(context),
          authors: _buildCatalogAuthors(context),
          onOpenBook: _openCatalogBookDetails,
        ),
      ),
    );
  }

  Future<void> _openCatalogCategoriesPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CatalogCategoriesPage(
          palette: _palette,
          categories: _buildCatalogCategories(context),
          onOpenBook: _openCatalogBookDetails,
        ),
      ),
    );
  }

  Future<void> _openCatalogAuthorsPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CatalogAuthorsPage(
          palette: _palette,
          authors: _buildCatalogAuthors(context),
          onOpenBook: _openCatalogBookDetails,
        ),
      ),
    );
  }

  Future<void> _openCatalogBooksPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CatalogBooksPage(
          palette: _palette,
          series: _seriesSortedByChaptersDesc(),
          onOpenBook: _openCatalogBookDetails,
        ),
      ),
    );
  }

  Future<void> _openCatalogCollectionsPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CatalogCollectionsPage(
          palette: _palette,
          collections: _buildLibraryCollections(context),
          onOpenBook: _openCatalogBookDetails,
        ),
      ),
    );
  }

  Future<void> _openAboutPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _AboutUsPage(palette: _palette)),
    );
  }

  Future<void> _openContactsPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _ContactsPage(palette: _palette)),
    );
  }

  int get _totalBundledSeriesCount => _allBundledSeries.length;

  int get _totalBundledChapterCount => _allBundledSeries.fold<int>(
    0,
    (sum, item) => sum + item.displayChapterCount,
  );

  Future<void> _openProfilePage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderProfilePage(
          palette: _palette,
          user: widget.currentUser,
          themeChoice: widget.themeChoice,
          languageChoice: widget.languageChoice,
          totalTitles: _totalBundledSeriesCount,
          totalChapters: _totalBundledChapterCount,
          totalFormats: 3,
          activeBookTitle: _book?.title,
          activeChapterTitle: _currentChapter?.title,
          onThemeTap: _openThemeSheet,
          onLanguageTap: _openLanguageSheet,
          onUserChanged: widget.onUserChanged,
          onSignOut: widget.onSignOut,
        ),
      ),
    );
  }

  Future<void> _runAfterClosingDrawer(FutureOr<void> Function() action) async {
    Navigator.of(context).maybePop();
    await Future<void>.delayed(const Duration(milliseconds: 160));
    await action();
  }

  void _scheduleAnchorJump(String? anchorId, {int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      if (anchorId == null || anchorId.isEmpty) {
        _scrollToTop();
        return;
      }

      final anchorContext = AnchorKey.forId(
        _htmlAnchorKey,
        anchorId,
      )?.currentContext;
      if (anchorContext != null) {
        Scrollable.ensureVisible(
          anchorContext,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: 0.08,
        );
        _pendingAnchorId = null;
        return;
      }

      if (attempt == 0) {
        _scrollToTop();
      }

      if (attempt < 4) {
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 70), () {
            _scheduleAnchorJump(anchorId, attempt: attempt + 1);
          }),
        );
      }
    });
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _handleLinkTap(String? url, Map<String, String> _, dynamic _) {
    final book = _book;
    final chapter = _currentChapter;
    if (book == null || chapter == null || url == null || url.trim().isEmpty) {
      return;
    }

    final location = book.resolveLocation(url, currentPath: chapter.path);
    if (location == null) {
      final l10n = AppLocalizations.of(context);
      final message = isExternalReference(url)
          ? l10n.noExternalLinks
          : l10n.linkNavigationFailed;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    _goToChapter(location.chapterIndex, anchorId: location.fragment);
  }

  void _setFontScale(double value) {
    widget.onFontScaleChanged(value.clamp(0.8, 1.8));
  }

  void _stepFontScale(double delta) {
    _setFontScale(_fontScale + delta);
  }

  Future<void> _openTextScaleSheet() async {
    _cancelReaderPanelAutoHideTimer();
    final l10n = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: _palette.panelBackground,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.textSize,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _palette.titleColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.textSizeHelp,
                    style: TextStyle(color: _palette.mutedColor, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      IconButton(
                        tooltip: l10n.decrease,
                        onPressed: () {
                          _stepFontScale(-0.1);
                          setSheetState(() {});
                        },
                        icon: const Icon(Icons.text_decrease_rounded),
                      ),
                      Expanded(
                        child: Slider(
                          min: 0.8,
                          max: 1.8,
                          divisions: 10,
                          value: _fontScale,
                          label: '${(_fontScale * 100).round()}%',
                          onChanged: (value) {
                            _setFontScale(value);
                            setSheetState(() {});
                          },
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.increase,
                        onPressed: () {
                          _stepFontScale(0.1);
                          setSheetState(() {});
                        },
                        icon: const Icon(Icons.text_increase_rounded),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        _setFontScale(1.0);
                        setSheetState(() {});
                      },
                      child: Text(l10n.reset),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (mounted) {
      _restartReaderPanelAutoHideTimer();
    }
  }

  Future<void> _openThemeSheet() async {
    final l10n = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: _palette.panelBackground,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text(
                  l10n.chooseTheme,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              for (final choice in ReaderThemeChoice.values)
                RadioListTile<ReaderThemeChoice>(
                  value: choice,
                  groupValue: widget.themeChoice,
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    widget.onThemeChanged(value);
                    Navigator.of(context).pop();
                  },
                  secondary: Icon(choice.icon),
                  title: Text(choice.label(l10n)),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openLanguageSheet() async {
    final l10n = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: _palette.panelBackground,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text(
                  l10n.chooseLanguage,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              for (final choice in AppLanguage.values)
                RadioListTile<AppLanguage>(
                  value: choice,
                  groupValue: widget.languageChoice,
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    widget.onLanguageChanged(value);
                    Navigator.of(context).pop();
                  },
                  secondary: const Icon(Icons.language_rounded),
                  title: Text(choice.label(l10n)),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggleFullscreenReading() async {
    final nextValue = !_isFullscreenReading;
    setState(() {
      _isFullscreenReading = nextValue;
      _isReaderPanelVisible = true;
    });

    await SystemChrome.setEnabledSystemUIMode(
      nextValue ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );

    if (mounted) {
      _restartReaderPanelAutoHideTimer();
    }
  }

  Future<void> _closeCurrentEpubBook() async {
    _cancelReaderPanelAutoHideTimer();

    if (_isFullscreenReading) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _book = null;
      _isLoading = false;
      _errorMessage = null;
      _isFullscreenReading = false;
      _isReaderPanelVisible = true;
      _currentChapterIndex = 0;
      _scrubberPreviewIndex = null;
      _pendingAnchorId = null;
    });
  }

  void _handleScrubberChangeStart(double value) {
    _cancelReaderPanelAutoHideTimer();
    setState(() {
      _scrubberPreviewIndex = value.round();
    });
  }

  void _handleScrubberChanged(double value) {
    final nextIndex = value.round();
    setState(() {
      _scrubberPreviewIndex = nextIndex;
    });

    if (nextIndex != _currentChapterIndex) {
      _goToChapter(nextIndex);
    }

    _restartReaderPanelAutoHideTimer();
  }

  void _handleScrubberChangeEnd(double value) {
    setState(() {
      _scrubberPreviewIndex = null;
    });
    _restartReaderPanelAutoHideTimer();
  }

  void _handleChapterSwipeStart(DragStartDetails details) {
    _horizontalSwipeDragOffset = 0;
    _handleReaderActivity();
  }

  void _handleChapterSwipeUpdate(DragUpdateDetails details) {
    _horizontalSwipeDragOffset += details.primaryDelta ?? 0;
    _handleReaderActivity();
  }

  void _handleChapterSwipeEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final dragOffset = _horizontalSwipeDragOffset;
    _horizontalSwipeDragOffset = 0;

    const minSwipeDistance = 72.0;
    const minSwipeVelocity = 320.0;
    final isSwipeStrongEnough =
        dragOffset.abs() >= minSwipeDistance ||
        velocity.abs() >= minSwipeVelocity;
    if (!isSwipeStrongEnough) {
      return;
    }

    if (dragOffset > 0 || velocity > 0) {
      _goToAdjacentChapter(-1);
      return;
    }

    if (dragOffset < 0 || velocity < 0) {
      _goToAdjacentChapter(1);
    }
  }

  double _scaled(double base) => base * _fontScale;

  @override
  void dispose() {
    _cancelReaderPanelAutoHideTimer();
    _scrollController.dispose();
    _featuredBooksController.dispose();
    _newBooksController.dispose();
    _promoBannersController.dispose();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final currentChapter = _currentChapter;
    final book = _book;
    final primaryMedia = currentChapter?.primaryMedia;
    final isHomeScreen = currentChapter == null;
    final isHomeConnectionUnavailable =
        isHomeScreen &&
        _homeConnectionError != null &&
        _allBundledSeries.isEmpty &&
        !_isBundledSeriesLoading;
    final appBarUserLabel = _userLabel(l10n);
    final isCurrentBookSaved =
        book != null && _isReadLaterBook(_epubBookId(book));

    return WillPopScope(
      onWillPop: () async {
        if (!isHomeScreen) {
          await _closeCurrentEpubBook();
          return false;
        }

        return true;
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: isHomeConnectionUnavailable
            ? null
            : isHomeScreen
            ? _buildHomeActionDrawer(context)
            : (book == null ? null : _buildTocDrawer(context, book)),
        endDrawer: null,
        drawerEnableOpenDragGesture:
            !isHomeConnectionUnavailable && (isHomeScreen || book != null),
        appBar:
            _isFullscreenReading || _isLoading || isHomeConnectionUnavailable
            ? null
            : _HomeAppBarShadow(
                child: AppBar(
                  leading: isHomeScreen
                      ? null
                      : IconButton(
                          tooltip: l10n.toc,
                          onPressed: book == null ? null : _openTocDrawer,
                          icon: const Icon(Icons.list_alt_rounded),
                        ),
                  elevation: isHomeScreen ? 12 : null,
                  shadowColor: isHomeScreen
                      ? _palette.shadow.withValues(alpha: 0.55)
                      : Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  backgroundColor: isHomeScreen
                      ? _palette.panelBackground.withValues(alpha: 0.94)
                      : null,
                  shape: isHomeScreen
                      ? const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(24),
                          ),
                        )
                      : null,
                  title: isHomeScreen
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.appTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              appBarUserLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: _palette.mutedColor),
                            ),
                          ],
                        )
                      : Text(book?.title ?? l10n.epubReaderTitle),
                  actions: isHomeScreen
                      ? [
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Center(
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(999),
                                  onTap: _openProfilePage,
                                  child: Container(
                                    width: 42,
                                    height: 42,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _palette.accent.withValues(
                                        alpha: 0.13,
                                      ),
                                      border: Border.all(
                                        color: _palette.divider,
                                      ),
                                    ),
                                    child: Text(
                                      _userInitials(l10n),
                                      style: TextStyle(
                                        color: _palette.titleColor,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ]
                      : [
                          PopupMenuButton<int>(
                            tooltip: _ReadingLibraryCopy.savedTitle(context),
                            icon: Icon(
                              isCurrentBookSaved
                                  ? Icons.bookmarks_rounded
                                  : Icons.bookmarks_outlined,
                            ),
                            onSelected: (value) {
                              if (value == 0) {
                                unawaited(_saveCurrentEpubReadLater());
                                return;
                              }
                              if (value == 1) {
                                unawaited(_saveCurrentEpubBookmark());
                                return;
                              }
                              unawaited(_openSavedReadingPage());
                            },
                            itemBuilder: (context) {
                              return [
                                PopupMenuItem(
                                  value: 0,
                                  enabled: book != null,
                                  child: Row(
                                    children: [
                                      Icon(
                                        isCurrentBookSaved
                                            ? Icons.playlist_add_check_rounded
                                            : Icons.playlist_add_rounded,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        isCurrentBookSaved
                                            ? _ReadingLibraryCopy.removeReadLater(
                                                context,
                                              )
                                            : _ReadingLibraryCopy.addReadLater(
                                                context,
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 1,
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.bookmark_add_rounded,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        _ReadingLibraryCopy.addBookmark(
                                          context,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 2,
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.inventory_2_rounded,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        _ReadingLibraryCopy.openSaved(context),
                                      ),
                                    ],
                                  ),
                                ),
                              ];
                            },
                          ),
                          IconButton(
                            tooltip: l10n.theme,
                            icon: Icon(widget.themeChoice.icon),
                            onPressed: _openThemeSheet,
                          ),
                        ],
                ),
              ),
        body: SafeArea(
          top: true,
          bottom: false,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _isLoading
                ? _ReaderLoadingScene(
                    palette: _palette,
                    title: _ReaderLoadingCopy.title(context),
                    subtitle: _ReaderLoadingCopy.subtitle(context),
                  )
                : isHomeConnectionUnavailable
                ? _HomeConnectionScreen(
                    palette: _palette,
                    message: _homeConnectionError!,
                    onRetry: () => unawaited(_refreshHome()),
                    onOpenDownloads: _openDownloadedArchivePage,
                  )
                : currentChapter == null
                ? _buildEmptyState(context)
                : Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) => _handleReaderActivity(),
                    onPointerMove: (_) => _handleReaderActivity(),
                    child: Column(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onHorizontalDragStart: _handleChapterSwipeStart,
                            onHorizontalDragUpdate: _handleChapterSwipeUpdate,
                            onHorizontalDragEnd: _handleChapterSwipeEnd,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: KeyedSubtree(
                                key: ValueKey(
                                  'chapter-body-${currentChapter.path}-${_fontScale.toStringAsFixed(2)}-${_isFullscreenReading ? 'full' : 'window'}',
                                ),
                                child: Scrollbar(
                                  controller: _scrollController,
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                    controller: _scrollController,
                                    padding: EdgeInsets.fromLTRB(
                                      _isFullscreenReading ? 8 : 16,
                                      _isFullscreenReading ? 8 : 6,
                                      _isFullscreenReading ? 8 : 16,
                                      24,
                                    ),
                                    child: Center(
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: _isFullscreenReading
                                              ? 1100
                                              : 920,
                                        ),
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: _palette.pageBackground,
                                            borderRadius: BorderRadius.circular(
                                              _isFullscreenReading ? 22 : 30,
                                            ),
                                            border: Border.all(
                                              color: _palette.divider,
                                            ),
                                            boxShadow: _isFullscreenReading
                                                ? const []
                                                : [
                                                    BoxShadow(
                                                      color: _palette.shadow,
                                                      blurRadius: 36,
                                                      offset: const Offset(
                                                        0,
                                                        16,
                                                      ),
                                                    ),
                                                  ],
                                          ),
                                          child: Padding(
                                            padding: EdgeInsets.fromLTRB(
                                              _isFullscreenReading ? 18 : 26,
                                              _isFullscreenReading ? 18 : 24,
                                              _isFullscreenReading ? 18 : 26,
                                              _isFullscreenReading ? 28 : 32,
                                            ),
                                            child: primaryMedia != null
                                                ? _PrimaryChapterMediaView(
                                                    book: book!,
                                                    chapterPath:
                                                        currentChapter.path,
                                                    media: primaryMedia,
                                                    fallbackLabel:
                                                        currentChapter.title,
                                                  )
                                                : SelectionArea(
                                                    child: Html(
                                                      key: ValueKey(
                                                        'chapter-html-${currentChapter.path}-${_fontScale.toStringAsFixed(2)}',
                                                      ),
                                                      data: currentChapter.html,
                                                      anchorKey: _htmlAnchorKey,
                                                      onLinkTap: _handleLinkTap,
                                                      style: _buildHtmlStyles(
                                                        theme,
                                                      ),
                                                      extensions: [
                                                        TagExtension(
                                                          tagsToExtend: const {
                                                            'img',
                                                            'image',
                                                            'object',
                                                          },
                                                          builder: (extensionContext) {
                                                            final source =
                                                                imageSourceFromAttributes(
                                                                  extensionContext
                                                                      .attributes,
                                                                );
                                                            return _EpubImageView(
                                                              book: book!,
                                                              chapterPath:
                                                                  currentChapter
                                                                      .path,
                                                              reference: source,
                                                              label:
                                                                  extensionContext
                                                                      .attributes['alt'] ??
                                                                  extensionContext
                                                                      .id,
                                                            );
                                                          },
                                                        ),
                                                        TagExtension(
                                                          tagsToExtend: const {
                                                            'svg',
                                                          },
                                                          builder: (extensionContext) {
                                                            return _InlineSvgView(
                                                              svgMarkup:
                                                                  extensionContext
                                                                      .element
                                                                      ?.outerHtml,
                                                              label:
                                                                  currentChapter
                                                                      .title,
                                                            );
                                                          },
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: !_isReaderPanelVisible
                              ? _ReaderPanelHandle(
                                  key: const ValueKey('reader-panel-handle'),
                                  palette: _palette,
                                  onTap: () => _showReaderPanel(),
                                )
                              : _AdaptiveChapterScrubber(
                                  key: const ValueKey('chapter-scrubber'),
                                  palette: _palette,
                                  chapterCount: book?.chapters.length ?? 0,
                                  currentChapterIndex: _currentChapterIndex,
                                  previewChapterIndex:
                                      _scrubberPreviewIndex ??
                                      _currentChapterIndex,
                                  previewTitle: _chapterDisplayTitleAt(
                                    _scrubberPreviewIndex ??
                                        _currentChapterIndex,
                                  ),
                                  fontScale: _fontScale,
                                  isFullscreenReading: _isFullscreenReading,
                                  onOpenToc: book == null
                                      ? null
                                      : _openTocDrawer,
                                  onTextScaleTap: _openTextScaleSheet,
                                  onFullscreenTap: _toggleFullscreenReading,
                                  onHideTap: _hideReaderPanel,
                                  onChangedStart:
                                      book != null && book.chapters.length > 1
                                      ? _handleScrubberChangeStart
                                      : null,
                                  onChanged:
                                      book != null && book.chapters.length > 1
                                      ? _handleScrubberChanged
                                      : null,
                                  onChangedEnd:
                                      book != null && book.chapters.length > 1
                                      ? _handleScrubberChangeEnd
                                      : null,
                                ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Drawer _buildTocDrawer(BuildContext context, EpubBook book) {
    final l10n = AppLocalizations.of(context);
    return Drawer(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: _palette.divider)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.toc,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: _palette.titleColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  book.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _palette.bodyColor,
                  ),
                ),
                if (book.author != null && book.author!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    book.author!,
                    style: TextStyle(color: _palette.mutedColor),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: book.tocEntries.length,
              itemBuilder: (context, index) {
                final entry = book.tocEntries[index];
                final isSelected =
                    _currentChapter?.path == entry.path &&
                    (_pendingAnchorId == entry.fragment ||
                        entry.fragment == null);
                return ListTile(
                  selected: isSelected,
                  minLeadingWidth: 10,
                  contentPadding: EdgeInsets.only(
                    left: 18 + (entry.depth * 18),
                    right: 16,
                  ),
                  title: Text(
                    entry.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                  onTap: () => _openTocEntry(entry),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeActionDrawer(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final userLabel = _userLabel(l10n);
    final userSubtitle = _userPhoneSubtitle(l10n);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final width = screenWidth < 360
        ? screenWidth - 12
        : screenWidth < 430
        ? screenWidth * 0.92
        : screenWidth < 720
        ? screenWidth * 0.72
        : 380.0;

    return Drawer(
      width: width,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(34)),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _palette.pageBackground,
              _palette.accent.withValues(alpha: 0.08),
              _palette.panelBackground,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
            children: [
              _DrawerProfileDeck(
                palette: _palette,
                initials: _userInitials(l10n),
                title: userLabel,
                subtitle: userSubtitle,
                menuLabel: l10n.mainMenu,
                statusPills: const [],
                onTap: () =>
                    unawaited(_runAfterClosingDrawer(_openProfilePage)),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 10.0;
                  final itemWidth = (constraints.maxWidth - spacing) / 2;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      _DrawerQuickActionButton(
                        width: itemWidth,
                        icon: Icons.manage_search_rounded,
                        title: _CatalogCopy.searchTitle(context),
                        accent: _palette.accent,
                        palette: _palette,
                        onTap: () => unawaited(
                          _runAfterClosingDrawer(_openCatalogSearchPage),
                        ),
                      ),
                      _DrawerQuickActionButton(
                        width: itemWidth,
                        icon: Icons.inventory_2_rounded,
                        title: _ReadingLibraryCopy.savedTitle(context),
                        accent: const Color(0xFFD46844),
                        palette: _palette,
                        onTap: () => unawaited(
                          _runAfterClosingDrawer(_openSavedReadingPage),
                        ),
                      ),
                      _DrawerQuickActionButton(
                        width: itemWidth,
                        icon: Icons.offline_pin_rounded,
                        title: _ArchiveDownloadsCopy.title(context),
                        accent: const Color(0xFF2E8B78),
                        palette: _palette,
                        onTap: () => unawaited(
                          _runAfterClosingDrawer(_openDownloadedArchivePage),
                        ),
                      ),
                      _DrawerQuickActionButton(
                        width: itemWidth,
                        icon: Icons.tune_rounded,
                        title: _HomeCategoryPreferenceCopy.drawerButton(
                          context,
                        ),
                        accent: const Color(0xFF7C6BC5),
                        palette: _palette,
                        onTap: () => unawaited(
                          _runAfterClosingDrawer(_showHomeCategoryPicker),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              _DrawerCommandGroup(
                label: _CatalogCopy.catalogSection(context),
                palette: _palette,
                children: [
                  _HomeDrawerActionTile(
                    icon: Icons.category_rounded,
                    title: _CatalogCopy.categoriesTitle(context),
                    accent: const Color(0xFF2E8B78),
                    onTap: () => unawaited(
                      _runAfterClosingDrawer(_openCatalogCategoriesPage),
                    ),
                  ),
                  _HomeDrawerActionTile(
                    icon: Icons.menu_book_rounded,
                    title: _CatalogCopy.booksTitle(context),
                    accent: const Color(0xFFD46844),
                    onTap: () => unawaited(
                      _runAfterClosingDrawer(_openCatalogBooksPage),
                    ),
                  ),
                  _HomeDrawerActionTile(
                    icon: Icons.badge_rounded,
                    title: _CatalogCopy.authorsTitle(context),
                    accent: const Color(0xFF7C6BC5),
                    onTap: () => unawaited(
                      _runAfterClosingDrawer(_openCatalogAuthorsPage),
                    ),
                  ),
                  _HomeDrawerActionTile(
                    icon: Icons.library_books_rounded,
                    title: _CollectionCopy.collectionsTitle(context),
                    accent: const Color(0xFF4D7C9D),
                    onTap: () => unawaited(
                      _runAfterClosingDrawer(_openCatalogCollectionsPage),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _DrawerCommandGroup(
                label: _InfoCopy.infoSection(context),
                palette: _palette,
                children: [
                  _HomeDrawerActionTile(
                    icon: Icons.auto_awesome_rounded,
                    title: _InfoCopy.aboutTitle(context),
                    accent: const Color(0xFF4D7C9D),
                    onTap: () =>
                        unawaited(_runAfterClosingDrawer(_openAboutPage)),
                  ),
                  _HomeDrawerActionTile(
                    icon: Icons.contact_support_rounded,
                    title: _InfoCopy.contactsTitle(context),
                    accent: const Color(0xFFB45A78),
                    onTap: () =>
                        unawaited(_runAfterClosingDrawer(_openContactsPage)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _DrawerCommandGroup(
                label: l10n.appearanceSection,
                palette: _palette,
                children: [
                  _HomeDrawerActionTile(
                    icon: widget.themeChoice.icon,
                    title: l10n.theme,
                    accent: _palette.accent,
                    onTap: () =>
                        unawaited(_runAfterClosingDrawer(_openThemeSheet)),
                  ),
                  _HomeDrawerActionTile(
                    icon: Icons.language_rounded,
                    title: l10n.language,
                    accent: const Color(0xFF2E8B78),
                    onTap: () =>
                        unawaited(_runAfterClosingDrawer(_openLanguageSheet)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _DrawerCommandGroup(
                label: l10n.accountSection,
                palette: _palette,
                children: [
                  _HomeDrawerActionTile(
                    icon: Icons.person_rounded,
                    title: l10n.accountSection,
                    accent: _palette.accent,
                    onTap: () =>
                        unawaited(_runAfterClosingDrawer(_openProfilePage)),
                  ),
                  _HomeDrawerActionTile(
                    icon: Icons.logout_rounded,
                    title: l10n.signOut,
                    accent: const Color(0xFFD46844),
                    onTap: () => unawaited(
                      _runAfterClosingDrawer(() async {
                        widget.onSignOut();
                      }),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBundledSeriesSection({
    required BuildContext context,
    required String title,
    required List<_BundledSeriesPreview> series,
    required IconData icon,
  }) {
    final l10n = AppLocalizations.of(context);
    if (series.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: _palette.accent),
            const SizedBox(width: 10),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: _palette.titleColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final item in series) ...[
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 8,
              ),
              leading: const Icon(Icons.menu_book_rounded),
              title: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                l10n.chaptersCount(item.displayChapterCount),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _openBundledSeries(item),
            ),
          ),
        ],
      ],
    );
  }

  List<_HomePromoBannerData> _buildPromoBanners(AppLocalizations l10n) {
    return [
      _HomePromoBannerData(
        title: l10n.promoImportTitle,
        subtitle: l10n.promoImportSubtitle,
        icon: Icons.file_open_rounded,
        accent: _palette.accent,
        onTap: _pickEpubFile,
      ),
      _HomePromoBannerData(
        title: l10n.promoComicsTitle,
        subtitle: l10n.promoComicsSubtitle,
        icon: Icons.auto_stories_rounded,
        accent: _palette.titleColor.withValues(alpha: 0.82),
        onTap: _openManhwaLibrary,
      ),
      _HomePromoBannerData(
        title: l10n.promoThemeTitle,
        subtitle: l10n.promoThemeSubtitle,
        icon: widget.themeChoice.icon,
        accent: _palette.accent,
        onTap: _openThemeSheet,
      ),
    ];
  }

  List<_HomeCategoryData> _buildHomeCategories(BuildContext context) {
    final catalogCategories = _buildCatalogCategories(context);
    final catalogByName = {
      for (final category in catalogCategories)
        _normalizeCatalogQuery(category.title): category,
    };

    if (_backendCategories.isEmpty) {
      return [
        for (final category in catalogCategories)
          _HomeCategoryData(
            id: 'catalog:${_normalizeCatalogQuery(category.title)}',
            title: category.title,
            icon: category.icon,
            accent: category.accent,
            onTap: () => _openCategoryDetails(
              context,
              _palette,
              category,
              _openCatalogBookDetails,
            ),
          ),
      ];
    }

    return [
      for (final category in _backendCategories)
        _HomeCategoryData(
          id: 'backend:${category.id}',
          title: category.name,
          icon: Icons.category_rounded,
          accent: _authorAccentForName(category.name),
          imageUrl: category.imageUrl,
          onTap: () {
            final catalogCategory =
                catalogByName[_normalizeCatalogQuery(category.name)] ??
                _LibraryCategoryEntry(
                  title: category.name,
                  description: category.description.trim().isEmpty
                      ? _CatalogCopy.booksCount(context, 0)
                      : category.description.trim(),
                  icon: Icons.category_rounded,
                  accent: _authorAccentForName(category.name),
                  series: const [],
                );
            _openCategoryDetails(
              context,
              _palette,
              catalogCategory,
              _openCatalogBookDetails,
            );
          },
        ),
    ];
  }

  List<_HomeCategoryData> _visibleHomeCategories(
    List<_HomeCategoryData> categories,
  ) {
    if (_selectedHomeCategoryIds.isEmpty) {
      return categories;
    }

    final filtered = categories
        .where((category) => _selectedHomeCategoryIds.contains(category.id))
        .toList();
    return filtered.isEmpty ? categories : filtered;
  }

  Future<void> _showHomeCategoryPicker() async {
    final allCategories = _buildHomeCategories(context);
    final result = await showDialog<Set<String>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _HomeCategoryPreferenceDialog(
        palette: _palette,
        categories: allCategories,
        selectedIds: _selectedHomeCategoryIds,
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    await _preferences.saveHomeCategoryIds(result);
    if (!mounted) {
      return;
    }

    setState(() {
      _selectedHomeCategoryIds = result;
    });

    if (widget.currentUser.categoryPickerPending) {
      widget.onUserChanged(
        widget.currentUser.copyWith(categoryPickerPending: false),
      );
    }
  }

  void _dismissWelcomeHero() {
    if (!widget.currentUser.welcomeBannerPending) {
      return;
    }

    widget.onUserChanged(
      widget.currentUser.copyWith(welcomeBannerPending: false),
    );
  }

  List<_HomeCollectionData> _buildHomeCollections(AppLocalizations l10n) {
    final ranked = _seriesSortedByChaptersDesc();
    final shortest = _allBundledSeries.toList()
      ..sort((a, b) {
        final chapterCompare = a.displayChapterCount.compareTo(
          b.displayChapterCount,
        );
        if (chapterCompare != 0) {
          return chapterCompare;
        }
        return naturalCompare(a.title, b.title);
      });

    List<_BundledSeriesPreview> takeUnique(List<_BundledSeriesPreview> source) {
      final seen = <String>{};
      final result = <_BundledSeriesPreview>[];
      for (final item in source) {
        if (seen.add(item.id)) {
          result.add(item);
        }
      }
      return result;
    }

    final starterShelf = takeUnique(shortest);
    final marathonShelf = takeUnique(ranked);
    final mixedShelf = takeUnique([
      ..._bundledMangaSeries,
      ..._bundledManhwaSeries,
      ..._bundledEpubSeries,
      ...ranked,
    ]);

    return [
      _HomeCollectionData(
        title: l10n.collectionStarterTitle,
        subtitle: l10n.collectionStarterSubtitle,
        accent: _palette.accent,
        icon: Icons.explore_rounded,
        series: starterShelf,
      ),
      _HomeCollectionData(
        title: l10n.collectionMarathonTitle,
        subtitle: l10n.collectionMarathonSubtitle,
        accent: const Color(0xFFD46844),
        icon: Icons.bolt_rounded,
        series: marathonShelf,
      ),
      _HomeCollectionData(
        title: l10n.collectionBlendTitle,
        subtitle: l10n.collectionBlendSubtitle,
        accent: const Color(0xFF2E8B78),
        icon: Icons.auto_awesome_mosaic_rounded,
        series: mixedShelf,
      ),
    ];
  }

  List<_HomeCollectionData> _buildLibraryCollections(BuildContext context) {
    final byBookId = {
      for (final series in _allBundledSeries)
        if (series.bookId > 0) series.bookId: series,
    };
    return [
      for (final collection in _backendCollections)
        _HomeCollectionData(
          title: collection.name,
          subtitle: collection.description.trim().isNotEmpty
              ? collection.description.trim()
              : _CollectionCopy.remoteCollectionSubtitle(
                  context,
                  collection.bookIds.length,
                ),
          accent: _collectionAccentForName(collection.name),
          icon: Icons.auto_stories_rounded,
          series: [
            for (final bookId in collection.bookIds)
              if (byBookId[bookId] != null) byBookId[bookId]!,
          ],
        ),
    ].where((collection) => collection.series.isNotEmpty).toList();
  }

  Widget _buildEmptyState(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final userLabel = _userLabel(l10n);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 640;
        final horizontalPadding = isCompact ? 16.0 : 20.0;
        return RefreshIndicator(
          color: _palette.accent,
          onRefresh: _refreshHome,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(horizontalPadding),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - (horizontalPadding * 2),
                  maxWidth: 1040,
                ),
                child: LayoutBuilder(
                  builder: (context, innerConstraints) {
                    final showConnectionError =
                        _homeConnectionError != null &&
                        _allBundledSeries.isEmpty &&
                        !_isBundledSeriesLoading;
                    final featuredSeries = _seriesSortedByChaptersDesc()
                        .take(5)
                        .toList();
                    final newestSeries = _seriesSortedByNewest()
                        .take(6)
                        .toList();
                    final popularSeries = _seriesSortedByChaptersDesc()
                        .take(6)
                        .toList();
                    final promoBanners = _buildPromoBanners(l10n);
                    final allCategories = _buildHomeCategories(context);
                    final categories = _visibleHomeCategories(allCategories);
                    final collections = _buildLibraryCollections(context)
                        .where((collection) => collection.series.isNotEmpty)
                        .toList();
                    final collectionColumns = innerConstraints.maxWidth >= 930
                        ? 3
                        : innerConstraints.maxWidth >= 620
                        ? 2
                        : 1;
                    final actionsSpacing = 12.0;
                    final collectionCardWidth =
                        (innerConstraints.maxWidth -
                            ((collectionColumns - 1) * actionsSpacing)) /
                        collectionColumns;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showConnectionError)
                          _HomeConnectionScreen(
                            palette: _palette,
                            message: _homeConnectionError!,
                            onRetry: () => unawaited(_refreshHome()),
                            onOpenDownloads: _openDownloadedArchivePage,
                          )
                        else ...[
                          if (widget.currentUser.welcomeBannerPending &&
                              !widget.currentUser.isGuest) ...[
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    _palette.panelBackground,
                                    _palette.accent.withValues(alpha: 0.1),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(
                                  isCompact ? 24 : 30,
                                ),
                                border: Border.all(color: _palette.divider),
                              ),
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                  isCompact ? 18 : 24,
                                  isCompact ? 18 : 24,
                                  isCompact ? 18 : 24,
                                  isCompact ? 18 : 22,
                                ),
                                child: _HomeHeroBody(
                                  palette: _palette,
                                  title: l10n.welcomeUser(userLabel),
                                  subtitle: l10n.libraryIntroSubtitle,
                                  onClose: _dismissWelcomeHero,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                          if (featuredSeries.isNotEmpty) ...[
                            _SectionHeader(
                              title: l10n.featuredBooks,
                              subtitle: l10n.featuredBooksSubtitle,
                              palette: _palette,
                            ),
                            const SizedBox(height: 12),
                            _FeaturedSeriesCarousel(
                              controller: _featuredBooksController,
                              currentIndex:
                                  _featuredBookIndex >= featuredSeries.length
                                  ? featuredSeries.length - 1
                                  : _featuredBookIndex,
                              palette: _palette,
                              series: featuredSeries,
                              kindIconBuilder: _iconForSeriesKind,
                              kindAccentBuilder: _accentForSeriesKind,
                              onPageChanged: (value) {
                                setState(() {
                                  _featuredBookIndex = value;
                                });
                              },
                              onSeriesTap: _openCatalogBookDetails,
                              onReadTap: _openBundledSeries,
                            ),
                            const SizedBox(height: 22),
                          ],
                          _SectionHeader(
                            title: l10n.promoBannersTitle,
                            subtitle: l10n.promoBannersSubtitle,
                            palette: _palette,
                          ),
                          const SizedBox(height: 12),
                          _PromoBannerCarousel(
                            controller: _promoBannersController,
                            currentIndex:
                                _promoBannerIndex >= promoBanners.length
                                ? promoBanners.length - 1
                                : _promoBannerIndex,
                            palette: _palette,
                            banners: promoBanners,
                            onPageChanged: (value) {
                              setState(() {
                                _promoBannerIndex = value;
                              });
                            },
                          ),
                          const SizedBox(height: 22),
                          if (newestSeries.isNotEmpty) ...[
                            _SectionHeader(
                              title: _HomeNewBooksCopy.title(context),
                              subtitle: _HomeNewBooksCopy.subtitle(context),
                              palette: _palette,
                            ),
                            const SizedBox(height: 12),
                            _FeaturedSeriesCarousel(
                              controller: _newBooksController,
                              currentIndex: _newBookIndex >= newestSeries.length
                                  ? newestSeries.length - 1
                                  : _newBookIndex,
                              palette: _palette,
                              series: newestSeries,
                              kindIconBuilder: _iconForSeriesKind,
                              kindAccentBuilder: _accentForSeriesKind,
                              onPageChanged: (value) {
                                setState(() {
                                  _newBookIndex = value;
                                });
                              },
                              onSeriesTap: _openCatalogBookDetails,
                              onReadTap: _openBundledSeries,
                            ),
                            const SizedBox(height: 22),
                          ],
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _SectionHeader(
                                  title: l10n.categoriesTitle,
                                  subtitle: l10n.categoriesSubtitle,
                                  palette: _palette,
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: _HomeCategoryPreferenceCopy.manage(
                                  context,
                                ),
                                onPressed: () =>
                                    unawaited(_showHomeCategoryPicker()),
                                icon: const Icon(Icons.tune_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final category in categories)
                                _HomeCategoryChip(
                                  data: category,
                                  palette: _palette,
                                ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          if (popularSeries.isNotEmpty) ...[
                            _SectionHeader(
                              title: l10n.popularBooksTitle,
                              subtitle: l10n.popularBooksSubtitle,
                              palette: _palette,
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: isCompact ? 280 : 286,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: popularSeries.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 12),
                                itemBuilder: (context, index) {
                                  final item = popularSeries[index];
                                  final info = _bookInfoForSeries(
                                    context,
                                    _palette,
                                    item,
                                  );
                                  final metaLabel =
                                      _chapterCountLabelForSeries(
                                        context,
                                        item,
                                      ) ??
                                      '${info.releaseYear} · ${info.ageRating}';
                                  return _PopularSeriesCard(
                                    width: isCompact ? 172 : 188,
                                    palette: _palette,
                                    title: item.title,
                                    subtitle: _authorNameForSeries(
                                      context,
                                      item,
                                    ),
                                    coverImageUrl: item.coverImageUrl,
                                    categoryLabel: info.category,
                                    chaptersLabel: metaLabel,
                                    accent: _accentForSeriesKind(item.kind),
                                    icon: _iconForSeriesKind(item.kind),
                                    indexLabel: '${index + 1}',
                                    onTap: () => _openBundledSeries(item),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 22),
                          ],
                          if (collections.isNotEmpty) ...[
                            _SectionHeader(
                              title: l10n.collectionsTitle,
                              subtitle: l10n.collectionsSubtitle,
                              palette: _palette,
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: actionsSpacing,
                              runSpacing: actionsSpacing,
                              children: [
                                for (final collection in collections)
                                  _CollectionShelfCard(
                                    width: collectionCardWidth,
                                    palette: _palette,
                                    data: collection,
                                    onCollectionTap: () =>
                                        _openCollectionDetails(
                                          context,
                                          _palette,
                                          collection,
                                          _openCatalogBookDetails,
                                        ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 22),
                          ],
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 18),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFE7E7),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    color: Color(0xFF7A1B1B),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Map<String, Style> _buildHtmlStyles(ThemeData theme) {
    return {
      'html': Style(
        backgroundColor: Colors.transparent,
        color: _palette.bodyColor,
        fontFamily: 'Georgia',
        lineHeight: LineHeight.number(1.6),
      ),
      'body': Style(
        margin: Margins.zero,
        padding: HtmlPaddings.zero,
        backgroundColor: Colors.transparent,
        color: _palette.bodyColor,
        fontFamily: 'Georgia',
        fontSize: FontSize(_scaled(18)),
        lineHeight: LineHeight.number(1.7),
      ),
      'p': Style(margin: Margins.only(bottom: 18)),
      'h1': Style(
        color: _palette.titleColor,
        fontSize: FontSize(_scaled(24)),
        fontWeight: FontWeight.w700,
        margin: Margins.only(top: 8, bottom: 14),
      ),
      'h2': Style(
        color: _palette.titleColor,
        fontSize: FontSize(_scaled(22)),
        fontWeight: FontWeight.w700,
        margin: Margins.only(top: 8, bottom: 12),
      ),
      'h3': Style(
        color: _palette.titleColor,
        fontSize: FontSize(_scaled(20)),
        fontWeight: FontWeight.w700,
        margin: Margins.only(top: 6, bottom: 10),
      ),
      '.title': Style(
        color: _palette.titleColor,
        fontSize: FontSize(_scaled(22)),
        fontWeight: FontWeight.w700,
        textAlign: TextAlign.center,
        margin: Margins.only(top: 6, bottom: 12),
      ),
      '.title1': Style(
        color: _palette.titleColor,
        fontSize: FontSize(_scaled(21)),
        fontWeight: FontWeight.w700,
        textAlign: TextAlign.center,
        margin: Margins.only(top: 6, bottom: 10),
      ),
      '.subtitle': Style(
        color: _palette.titleColor,
        fontSize: FontSize(_scaled(19)),
        fontWeight: FontWeight.w600,
        textAlign: TextAlign.center,
        margin: Margins.only(top: 6, bottom: 10),
      ),
      'a': Style(
        color: _palette.accent,
        textDecoration: TextDecoration.underline,
      ),
      'blockquote': Style(
        backgroundColor: _palette.quoteBackground,
        margin: Margins.only(top: 10, bottom: 18),
        padding: HtmlPaddings.only(left: 16, right: 16, top: 12, bottom: 12),
        border: Border(left: BorderSide(color: _palette.accent, width: 4)),
      ),
      'pre': Style(
        backgroundColor: _palette.codeBackground,
        margin: Margins.only(top: 8, bottom: 16),
        padding: HtmlPaddings.all(14),
        whiteSpace: WhiteSpace.pre,
      ),
      'code': Style(
        backgroundColor: _palette.codeBackground,
        fontFamily: 'Consolas',
        fontSize: FontSize(_scaled(15)),
      ),
      'ul': Style(margin: Margins.only(bottom: 18)),
      'ol': Style(margin: Margins.only(bottom: 18)),
      'li': Style(margin: Margins.only(bottom: 8)),
      'hr': Style(margin: Margins.only(top: 18, bottom: 18)),
      'table': Style(margin: Margins.only(top: 8, bottom: 18)),
      'th': Style(
        backgroundColor: _palette.quoteBackground,
        padding: HtmlPaddings.all(8),
      ),
      'td': Style(padding: HtmlPaddings.all(8)),
      'img': Style(margin: Margins.only(top: 14, bottom: 14)),
    };
  }
}

class _HomeAppBarShadow extends StatelessWidget implements PreferredSizeWidget {
  const _HomeAppBarShadow({required this.child});

  final PreferredSizeWidget child;

  @override
  Size get preferredSize => child.preferredSize;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

// ignore: unused_element
class _ChapterScrubber extends StatelessWidget {
  const _ChapterScrubber({
    required this.palette,
    required this.chapterCount,
    required this.currentChapterIndex,
    required this.previewChapterIndex,
    required this.previewTitle,
    required this.fontScale,
    required this.isFullscreenReading,
    required this.onOpenToc,
    required this.onTextScaleTap,
    required this.onFullscreenTap,
    required this.onHideTap,
    required this.onChangedStart,
    required this.onChanged,
    required this.onChangedEnd,
  });

  final ReaderPalette palette;
  final int chapterCount;
  final int currentChapterIndex;
  final int previewChapterIndex;
  final String previewTitle;
  final double fontScale;
  final bool isFullscreenReading;
  final VoidCallback? onOpenToc;
  final VoidCallback onTextScaleTap;
  final VoidCallback onFullscreenTap;
  final VoidCallback? onHideTap;
  final ValueChanged<double>? onChangedStart;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangedEnd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canScrub = chapterCount > 1;
    final sliderValue = canScrub ? previewChapterIndex.toDouble() : 0.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        isFullscreenReading ? 6 : 0,
        16,
        isFullscreenReading ? 16 : 16,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.panelBackground.withValues(
            alpha: isFullscreenReading ? 0.96 : 1.0,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: palette.divider),
          boxShadow: [
            BoxShadow(
              color: palette.shadow,
              blurRadius: isFullscreenReading ? 26 : 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      previewTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: palette.titleColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${previewChapterIndex + 1} / $chapterCount',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: palette.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor: palette.accent,
                  inactiveTrackColor: palette.divider.withValues(alpha: 0.8),
                  thumbColor: palette.accent,
                  overlayColor: palette.accent.withValues(alpha: 0.12),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 18,
                  ),
                ),
                child: Slider(
                  min: 0,
                  max: canScrub ? (chapterCount - 1).toDouble() : 1,
                  divisions: canScrub ? chapterCount - 1 : null,
                  value: sliderValue,
                  label: '${previewChapterIndex + 1} / $chapterCount',
                  onChangeStart: onChangedStart,
                  onChanged: onChanged,
                  onChangeEnd: onChangedEnd,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  IconButton(
                    tooltip: l10n.toc,
                    onPressed: onOpenToc,
                    icon: const Icon(Icons.list_alt_rounded),
                  ),
                  IconButton(
                    tooltip: l10n.textSize,
                    onPressed: onTextScaleTap,
                    icon: const Icon(Icons.format_size_rounded),
                  ),
                  Text(
                    '${(fontScale * 100).round()}%',
                    style: TextStyle(
                      color: palette.mutedColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    onPressed: onFullscreenTap,
                    icon: Icon(
                      isFullscreenReading
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                    ),
                    label: Text(
                      isFullscreenReading ? l10n.collapse : l10n.fullscreen,
                    ),
                  ),
                  if (isFullscreenReading) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: l10n.hidePanel,
                      onPressed: onHideTap,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdaptiveChapterScrubber extends StatelessWidget {
  const _AdaptiveChapterScrubber({
    super.key,
    required this.palette,
    required this.chapterCount,
    required this.currentChapterIndex,
    required this.previewChapterIndex,
    required this.previewTitle,
    required this.fontScale,
    required this.isFullscreenReading,
    required this.onOpenToc,
    required this.onTextScaleTap,
    required this.onFullscreenTap,
    required this.onHideTap,
    required this.onChangedStart,
    required this.onChanged,
    required this.onChangedEnd,
  });

  final ReaderPalette palette;
  final int chapterCount;
  final int currentChapterIndex;
  final int previewChapterIndex;
  final String previewTitle;
  final double fontScale;
  final bool isFullscreenReading;
  final VoidCallback? onOpenToc;
  final VoidCallback onTextScaleTap;
  final VoidCallback onFullscreenTap;
  final VoidCallback? onHideTap;
  final ValueChanged<double>? onChangedStart;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangedEnd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canScrub = chapterCount > 1;
    final sliderValue = canScrub ? previewChapterIndex.toDouble() : 0.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, isFullscreenReading ? 6 : 0, 16, 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.panelBackground.withValues(
            alpha: isFullscreenReading ? 0.96 : 1.0,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: palette.divider),
          boxShadow: [
            BoxShadow(
              color: palette.shadow,
              blurRadius: isFullscreenReading ? 26 : 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      previewTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: palette.titleColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${previewChapterIndex + 1} / $chapterCount',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: palette.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor: palette.accent,
                  inactiveTrackColor: palette.divider.withValues(alpha: 0.8),
                  thumbColor: palette.accent,
                  overlayColor: palette.accent.withValues(alpha: 0.12),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 18,
                  ),
                ),
                child: Slider(
                  min: 0,
                  max: canScrub ? (chapterCount - 1).toDouble() : 1,
                  divisions: canScrub ? chapterCount - 1 : null,
                  value: sliderValue,
                  label: '${previewChapterIndex + 1} / $chapterCount',
                  onChangeStart: onChangedStart,
                  onChanged: onChanged,
                  onChangeEnd: onChangedEnd,
                ),
              ),
              const SizedBox(height: 2),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 430;
                  final scaleBadge = DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.pageBackground,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: palette.divider),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Text(
                        '${(fontScale * 100).round()}%',
                        style: TextStyle(
                          color: palette.mutedColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );

                  final fullscreenButton = FilledButton.tonalIcon(
                    onPressed: onFullscreenTap,
                    icon: Icon(
                      isFullscreenReading
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                    ),
                    label: Text(
                      isCompact
                          ? (isFullscreenReading
                                ? l10n.windowMode
                                : l10n.screenMode)
                          : (isFullscreenReading
                                ? l10n.collapse
                                : l10n.fullscreen),
                    ),
                  );

                  final hideButton = IconButton(
                    tooltip: l10n.hidePanel,
                    onPressed: onHideTap,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  );

                  final leadingControls = Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      IconButton(
                        tooltip: l10n.toc,
                        onPressed: onOpenToc,
                        icon: const Icon(Icons.list_alt_rounded),
                      ),
                      IconButton(
                        tooltip: l10n.textSize,
                        onPressed: onTextScaleTap,
                        icon: const Icon(Icons.format_size_rounded),
                      ),
                      scaleBadge,
                    ],
                  );

                  if (isCompact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        leadingControls,
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [fullscreenButton, hideButton],
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: leadingControls),
                      const SizedBox(width: 12),
                      fullscreenButton,
                      const SizedBox(width: 8),
                      hideButton,
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderPanelHandle extends StatelessWidget {
  const _ReaderPanelHandle({
    super.key,
    required this.palette,
    required this.onTap,
  });

  final ReaderPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      child: Center(
        child: GestureDetector(
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.panelBackground.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: palette.divider),
              boxShadow: [
                BoxShadow(
                  color: palette.shadow,
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.keyboard_arrow_up_rounded,
                    color: palette.titleColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l10n.showPanel,
                    style: TextStyle(
                      color: palette.titleColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderLoadingCopy {
  const _ReaderLoadingCopy._();

  static bool _isRu(BuildContext context) =>
      AppLocalizations.of(context).locale.languageCode == 'ru';

  static String title(BuildContext context) => _isRu(context)
      ? '\u041e\u0442\u043a\u0440\u044b\u0432\u0430\u044e \u043a\u043d\u0438\u0433\u0443'
      : 'Opening the book';

  static String subtitle(BuildContext context) => _isRu(context)
      ? '\u0421\u043a\u0430\u0447\u0438\u0432\u0430\u044e EPUB \u0438 \u0433\u043e\u0442\u043e\u0432\u043b\u044e \u0441\u0442\u0440\u0430\u043d\u0438\u0446\u044b'
      : 'Downloading the EPUB and preparing pages';
}

class _ReaderLoadingScene extends StatefulWidget {
  const _ReaderLoadingScene({
    required this.palette,
    required this.title,
    required this.subtitle,
  });

  final ReaderPalette palette;
  final String title;
  final String subtitle;

  @override
  State<_ReaderLoadingScene> createState() => _ReaderLoadingSceneState();
}

class _ReaderLoadingSceneState extends State<_ReaderLoadingScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              palette.pageBackground,
              palette.accent.withValues(alpha: 0.12),
              palette.panelBackground,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final phase = _controller.value;
                  final wave = math.sin(phase * math.pi * 2);
                  final orbit = phase * math.pi * 2;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 190,
                        height: 142,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            for (var index = 0; index < 5; index++)
                              Transform.translate(
                                offset: Offset(
                                  math.cos(orbit + index * 1.25) * 76,
                                  math.sin(orbit + index * 1.25) * 42,
                                ),
                                child: Container(
                                  width: 8 + index.toDouble(),
                                  height: 8 + index.toDouble(),
                                  decoration: BoxDecoration(
                                    color: palette.accent.withValues(
                                      alpha: 0.18 + index * 0.09,
                                    ),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: palette.accent.withValues(
                                          alpha: 0.18,
                                        ),
                                        blurRadius: 12,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            Positioned(
                              bottom: 10,
                              child: Container(
                                width: 148,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: palette.shadow.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                            Transform.translate(
                              offset: Offset(0, wave * 5),
                              child: Container(
                                width: 134,
                                height: 96,
                                decoration: BoxDecoration(
                                  color: palette.titleColor,
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: palette.shadow.withValues(
                                        alpha: 0.24,
                                      ),
                                      blurRadius: 24,
                                      offset: const Offset(0, 14),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            for (var index = 0; index < 4; index++)
                              Transform.translate(
                                offset: Offset(
                                  18.0 - (index * 8),
                                  -4 +
                                      (math.sin(
                                            (phase + index * 0.18) *
                                                math.pi *
                                                2,
                                          ) *
                                          9),
                                ),
                                child: Transform.rotate(
                                  angle:
                                      -0.22 +
                                      (index * 0.10) +
                                      (math.sin(
                                            (phase + index * 0.24) *
                                                math.pi *
                                                2,
                                          ) *
                                          0.18),
                                  child: Container(
                                    width: 86,
                                    height: 104,
                                    decoration: BoxDecoration(
                                      color: Color.lerp(
                                        palette.panelBackground,
                                        palette.accent,
                                        0.10 + index * 0.05,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: palette.divider.withValues(
                                          alpha: 0.8,
                                        ),
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 34 + index * 6,
                                            height: 5,
                                            decoration: BoxDecoration(
                                              color: palette.accent.withValues(
                                                alpha: 0.42,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                          ),
                                          const SizedBox(height: 9),
                                          for (
                                            var line = 0;
                                            line < 4;
                                            line++
                                          ) ...[
                                            Container(
                                              width:
                                                  46 + (line.isEven ? 18 : 6),
                                              height: 4,
                                              decoration: BoxDecoration(
                                                color: palette.mutedColor
                                                    .withValues(alpha: 0.24),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                            ),
                                            const SizedBox(height: 7),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            Transform.translate(
                              offset: Offset(
                                math.sin(orbit) * 42,
                                -2 + math.cos(orbit * 1.3) * 8,
                              ),
                              child: Transform.rotate(
                                angle: math.sin(orbit) * 0.42,
                                child: Container(
                                  width: 12,
                                  height: 86,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        palette.accent.withValues(alpha: 0.95),
                                        palette.accent.withValues(alpha: 0.18),
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                    boxShadow: [
                                      BoxShadow(
                                        color: palette.accent.withValues(
                                          alpha: 0.35,
                                        ),
                                        blurRadius: 18,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: palette.titleColor,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.subtitle,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.bodyColor,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var index = 0; index < 5; index++)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Transform.scale(
                                scale:
                                    0.72 +
                                    (math.sin(
                                              (phase + index * 0.14) *
                                                  math.pi *
                                                  2,
                                            ) +
                                            1) *
                                        0.22,
                                child: Container(
                                  width: 9,
                                  height: 9,
                                  decoration: BoxDecoration(
                                    color: palette.accent.withValues(
                                      alpha: 0.34 + (index * 0.08),
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BundledSeriesPreview {
  const _BundledSeriesPreview({
    required this.id,
    required this.bookId,
    required this.title,
    required this.chapters,
    required this.kind,
    required this.chapterCount,
    this.description = '',
    this.language = '',
    this.coverImageUrl = '',
    this.authorNames = const [],
    this.categoryNames = const [],
    this.releaseYear,
    this.recommendedAge,
    this.likesTotal = 0,
    this.dislikesTotal = 0,
    this.epubFileUrl = '',
    this.pdfFileUrl = '',
  });

  final String id;
  final int bookId;
  final String title;
  final List<ManhwaLibraryItem> chapters;
  final ArchiveLibraryKind kind;
  final int chapterCount;
  final String description;
  final String language;
  final String coverImageUrl;
  final List<String> authorNames;
  final List<String> categoryNames;
  final int? releaseYear;
  final int? recommendedAge;
  final int likesTotal;
  final int dislikesTotal;
  final String epubFileUrl;
  final String pdfFileUrl;

  bool get isEpub => kind == ArchiveLibraryKind.epub;
  bool get isPdf => kind == ArchiveLibraryKind.pdf;

  int get displayChapterCount =>
      chapters.isNotEmpty ? chapters.length : chapterCount;

  _BundledSeriesPreview copyWith({
    List<ManhwaLibraryItem>? chapters,
    int? chapterCount,
    int? likesTotal,
    int? dislikesTotal,
  }) {
    return _BundledSeriesPreview(
      id: id,
      bookId: bookId,
      title: title,
      description: description,
      language: language,
      coverImageUrl: coverImageUrl,
      authorNames: authorNames,
      categoryNames: categoryNames,
      releaseYear: releaseYear,
      recommendedAge: recommendedAge,
      likesTotal: likesTotal ?? this.likesTotal,
      dislikesTotal: dislikesTotal ?? this.dislikesTotal,
      epubFileUrl: epubFileUrl,
      pdfFileUrl: pdfFileUrl,
      chapters: chapters ?? this.chapters,
      kind: kind,
      chapterCount: chapterCount ?? this.chapterCount,
    );
  }
}

class _LibraryCategoryEntry {
  const _LibraryCategoryEntry({
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    required this.series,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color accent;
  final List<_BundledSeriesPreview> series;
}

class _LibraryAuthorEntry {
  const _LibraryAuthorEntry({
    required this.name,
    required this.description,
    required this.imageIcon,
    required this.imageAccent,
    required this.series,
  });

  final String name;
  final String description;
  final IconData imageIcon;
  final Color imageAccent;
  final List<_BundledSeriesPreview> series;
}

class _CatalogBookInfo {
  const _CatalogBookInfo({
    required this.author,
    required this.releaseYear,
    required this.description,
    required this.language,
    required this.ageRating,
    required this.category,
    required this.categoryIcon,
    required this.coverAccent,
  });

  final String author;
  final int releaseYear;
  final String description;
  final String language;
  final String ageRating;
  final String category;
  final IconData categoryIcon;
  final Color coverAccent;
}

enum _LibrarySearchScope { all, categories, authors, books }

enum _CatalogViewMode { spotlight, list, twoColumn }

class _CatalogCopy {
  const _CatalogCopy._();

  static bool _isRu(BuildContext context) =>
      AppLocalizations.of(context).locale.languageCode == 'ru';

  static String catalogSection(BuildContext context) =>
      _isRu(context) ? 'Каталог' : 'Catalog';

  static String searchTitle(BuildContext context) =>
      _isRu(context) ? 'Поиск' : 'Search';

  static String categoriesTitle(BuildContext context) =>
      _isRu(context) ? 'Категории' : 'Categories';

  static String authorsTitle(BuildContext context) =>
      _isRu(context) ? 'Авторы' : 'Authors';

  static String booksTitle(BuildContext context) =>
      _isRu(context) ? 'Книги' : 'Books';

  static String allScope(BuildContext context) =>
      _isRu(context) ? 'Все' : 'All';

  static String categoryScope(BuildContext context) =>
      _isRu(context) ? 'Категория' : 'Category';

  static String authorScope(BuildContext context) =>
      _isRu(context) ? 'Автор' : 'Author';

  static String bookScope(BuildContext context) =>
      _isRu(context) ? 'Книга' : 'Book';

  static String searchHint(BuildContext context) => _isRu(context)
      ? 'Введите название, автора или тип...'
      : 'Type a title, author, or type...';

  static String searchLead(BuildContext context) => _isRu(context)
      ? 'Выберите режим поиска и сразу прыгайте в нужную полку.'
      : 'Choose a search mode and jump straight into the right shelf.';

  static String emptySearch(BuildContext context) =>
      _isRu(context) ? 'Ничего не найдено' : 'Nothing found';

  static String noBooks(BuildContext context) =>
      _isRu(context) ? 'Здесь пока нет книг' : 'No books here yet';

  static String unknownAuthor(BuildContext context) =>
      _isRu(context) ? 'Неизвестный автор' : 'Unknown author';

  static String categoryManhwaDescription(BuildContext context) =>
      _isRu(context)
      ? 'Вертикальные цветные главы из встроенной полки.'
      : 'Vertical color chapters from the bundled shelf.';

  static String categoryMangaDescription(BuildContext context) => _isRu(context)
      ? 'Манга и короткие архивные главы в локальной библиотеке.'
      : 'Manga and short archive chapters in the local library.';

  static String categoryLongReadsDescription(BuildContext context) =>
      _isRu(context)
      ? 'Серии с большим количеством глав для долгого чтения.'
      : 'Series with many chapters for longer reading sessions.';

  static String shortReads(BuildContext context) =>
      _isRu(context) ? 'Короткие серии' : 'Short reads';

  static String shortReadsDescription(BuildContext context) => _isRu(context)
      ? 'Небольшие истории, которые удобно открыть быстро.'
      : 'Small stories that are easy to open quickly.';

  static String categoryCuratedDescription(BuildContext context) =>
      _isRu(context)
      ? 'Смешанная полка из разных форматов и настроений.'
      : 'A mixed shelf across formats and reading moods.';

  static String categoryResult(BuildContext context) =>
      _isRu(context) ? 'Категория' : 'Category';

  static String authorResult(BuildContext context) =>
      _isRu(context) ? 'Автор' : 'Author';

  static String bookResult(BuildContext context) =>
      _isRu(context) ? 'Книга' : 'Book';

  static String openChapters(BuildContext context) =>
      _isRu(context) ? 'Открыть главы' : 'Open chapters';

  static String readBook(BuildContext context) => _isRu(context)
      ? '\u0427\u0438\u0442\u0430\u0442\u044c \u043a\u043d\u0438\u0433\u0443'
      : 'Read book';

  static String booksCount(BuildContext context, int count) => _isRu(context)
      ? '$count книг'
      : count == 1
      ? '1 book'
      : '$count books';

  static String authorsCount(BuildContext context, int count) => _isRu(context)
      ? '$count авторов'
      : count == 1
      ? '1 author'
      : '$count authors';

  static String categoriesCount(BuildContext context, int count) =>
      _isRu(context) ? '$count категорий' : '$count categories';
}

class _CatalogBrowseCopy {
  const _CatalogBrowseCopy._();

  static bool _isRu(BuildContext context) =>
      AppLocalizations.of(context).locale.languageCode == 'ru';

  static String browseHint(BuildContext context) => _isRu(context)
      ? 'Поиск по названию, автору, описанию...'
      : 'Search by title, author, description...';

  static String viewBlock(BuildContext context) =>
      _isRu(context) ? 'Блочный' : 'Blocks';

  static String viewList(BuildContext context) =>
      _isRu(context) ? 'Строчный' : 'Rows';

  static String viewTwoColumns(BuildContext context) =>
      _isRu(context) ? '2 в ряд' : '2 per row';
}

class _CollectionCopy {
  const _CollectionCopy._();

  static bool _isRu(BuildContext context) =>
      AppLocalizations.of(context).locale.languageCode == 'ru';

  static String collectionsTitle(BuildContext context) =>
      _isRu(context) ? 'Коллекции' : 'Collections';

  static String collectionsLead(BuildContext context) => _isRu(context)
      ? 'Серии и подборки, где внутри перечислены все книги одной линии.'
      : 'Series and shelves where every related book is listed together.';

  static String openCollection(BuildContext context) =>
      _isRu(context) ? 'Открыть коллекцию' : 'Open collection';

  static String emptyCollections(BuildContext context) =>
      _isRu(context) ? 'Коллекций пока нет' : 'No collections yet';

  static String booksInCollection(BuildContext context, int count) =>
      _isRu(context)
      ? '$count книг в коллекции'
      : count == 1
      ? '1 book in this collection'
      : '$count books in this collection';

  static String collectionCount(BuildContext context, int count) =>
      _isRu(context)
      ? '$count книг'
      : count == 1
      ? '1 book'
      : '$count books';

  static String authorCollectionSubtitle(BuildContext context, int count) =>
      _isRu(context)
      ? 'Все книги этого автора в одной коллекции'
      : 'All books by this author in one collection';
  static String remoteCollectionSubtitle(BuildContext context, int count) =>
      _isRu(context)
      ? '\u041f\u043e\u0434\u0431\u043e\u0440\u043a\u0430 \u0438\u0437 $count \u043a\u043d\u0438\u0433'
      : count == 1
      ? 'A curated collection with 1 book'
      : 'A curated collection with $count books';
}

class _ReadingLibraryCopy {
  const _ReadingLibraryCopy._();

  static bool _isRu(BuildContext context) =>
      AppLocalizations.of(context).locale.languageCode == 'ru';

  static String savedTitle(BuildContext context) =>
      _isRu(context) ? 'Сохраненное' : 'Saved';

  static String savedLead(BuildContext context) => _isRu(context)
      ? 'Книги на потом и закладки хранятся на этом устройстве.'
      : 'Read-later books and bookmarks are stored on this device.';

  static String readLater(BuildContext context) =>
      _isRu(context) ? 'Прочитать потом' : 'Read later';

  static String bookmarks(BuildContext context) =>
      _isRu(context) ? 'Закладки' : 'Bookmarks';

  static String addReadLater(BuildContext context) =>
      _isRu(context) ? 'Добавить на потом' : 'Add to read later';

  static String removeReadLater(BuildContext context) =>
      _isRu(context) ? 'Убрать из потом' : 'Remove from read later';

  static String addBookmark(BuildContext context) =>
      _isRu(context) ? 'Поставить закладку' : 'Add bookmark';

  static String openSaved(BuildContext context) =>
      _isRu(context) ? 'Открыть сохраненное' : 'Open saved';

  static String open(BuildContext context) =>
      _isRu(context) ? 'Открыть' : 'Open';

  static String delete(BuildContext context) =>
      _isRu(context) ? 'Удалить' : 'Delete';

  static String emptyReadLater(BuildContext context) => _isRu(context)
      ? 'Список пуст. Добавьте книгу, которую хотите прочитать позже.'
      : 'The list is empty. Add a book you want to read later.';

  static String emptyBookmarks(BuildContext context) => _isRu(context)
      ? 'Закладок пока нет. Откройте главу и сохраните место чтения.'
      : 'No bookmarks yet. Open a chapter and save your place.';

  static String chapters(BuildContext context, int count) => _isRu(context)
      ? '$count глав'
      : count == 1
      ? '1 chapter'
      : '$count chapters';

  static String chapterNumber(BuildContext context, int index) =>
      _isRu(context) ? 'Глава ${index + 1}' : 'Chapter ${index + 1}';

  static String unknownAuthor(BuildContext context) =>
      _isRu(context) ? 'Неизвестный автор' : 'Unknown author';

  static String addedToReadLater(BuildContext context) =>
      _isRu(context) ? 'Книга добавлена в список' : 'Book added to the list';

  static String removedFromReadLater(BuildContext context) =>
      _isRu(context) ? 'Книга убрана из списка' : 'Book removed from the list';

  static String bookmarkSaved(BuildContext context) =>
      _isRu(context) ? 'Закладка сохранена' : 'Bookmark saved';

  static String removed(BuildContext context) =>
      _isRu(context) ? 'Удалено' : 'Removed';

  static String bookNotFound(BuildContext context) => _isRu(context)
      ? 'Не удалось найти эту книгу в библиотеке'
      : 'Could not find this book in the library';

  static String fileNotFound(BuildContext context) =>
      _isRu(context) ? 'Файл книги не найден' : 'Book file was not found';
}

class _InfoCopy {
  const _InfoCopy._();

  static bool _isRu(BuildContext context) =>
      AppLocalizations.of(context).locale.languageCode == 'ru';

  static String infoSection(BuildContext context) =>
      _isRu(context) ? 'О приложении' : 'Info';

  static String aboutTitle(BuildContext context) =>
      _isRu(context) ? 'О нас' : 'About us';

  static String contactsTitle(BuildContext context) =>
      _isRu(context) ? 'Контакты' : 'Contacts';

  static String aboutLead(BuildContext context) => _isRu(context)
      ? 'Мы собираем EPUB, мангу и манхву в одну спокойную библиотеку, где важны скорость, комфорт и понятная навигация.'
      : 'We bring EPUB, manga, and manhwa into one calm library where speed, comfort, and clear navigation matter.';

  static String aboutBadge(BuildContext context) =>
      _isRu(context) ? 'Локальная библиотека' : 'Local library';

  static String missionTitle(BuildContext context) =>
      _isRu(context) ? 'Наш подход' : 'Our approach';

  static String missionBody(BuildContext context) => _isRu(context)
      ? 'Приложение помогает быстро открыть нужную полку, перейти к автору, книге или главе и читать без лишнего шума.'
      : 'The app helps you open the right shelf, jump to an author, book, or chapter, and keep reading without noise.';

  static String designTitle(BuildContext context) =>
      _isRu(context) ? 'Дизайн' : 'Design';

  static String designBody(BuildContext context) => _isRu(context)
      ? 'Карточки, обложки и страницы сделаны как рабочая библиотечная система: визуально богато, но без перегруза.'
      : 'Cards, covers, and pages are built like a practical library system: visually rich, but not overloaded.';

  static String privacyTitle(BuildContext context) =>
      _isRu(context) ? 'Приватность' : 'Privacy';

  static String privacyBody(BuildContext context) => _isRu(context)
      ? 'Профиль и настройки работают локально на устройстве. Это удобно для прототипа и не требует сервера.'
      : 'Profile and settings work locally on the device. It is practical for the prototype and does not require a server.';

  static String contactsLead(BuildContext context) => _isRu(context)
      ? 'Выберите удобный канал. Нажатие на карточку скопирует контакт.'
      : 'Choose a channel. Tapping a card copies the contact.';

  static String copied(BuildContext context) =>
      _isRu(context) ? 'Контакт скопирован' : 'Contact copied';

  static String titlesMetric(BuildContext context) =>
      _isRu(context) ? 'тайтлов' : 'titles';

  static String chaptersMetric(BuildContext context) =>
      _isRu(context) ? 'глав' : 'chapters';

  static String formatsMetric(BuildContext context) =>
      _isRu(context) ? 'формата' : 'formats';
}

String _normalizeCatalogQuery(String value) {
  return value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

bool _matchesCatalogQuery(String query, Iterable<String> fields) {
  if (query.isEmpty) {
    return true;
  }

  return fields.any((field) => _normalizeCatalogQuery(field).contains(query));
}

String? _chapterCountLabelForSeries(
  BuildContext context,
  _BundledSeriesPreview series,
) {
  if (series.displayChapterCount == 0) {
    return null;
  }

  return AppLocalizations.of(context).chaptersCount(series.displayChapterCount);
}

String _formatContributorName(String value) {
  final cleaned = value
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) {
    return value;
  }

  return cleaned
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _authorNameForSeries(
  BuildContext context,
  _BundledSeriesPreview series,
) {
  if (series.authorNames.isNotEmpty) {
    return series.authorNames.join(', ');
  }

  final contributorPattern = RegExp(r'\[([^\]]+)\]');
  for (final chapter in series.chapters) {
    final match = contributorPattern.firstMatch(chapter.sourcePath);
    final value = match?.group(1)?.trim();
    if (value != null && value.isNotEmpty) {
      return _formatContributorName(value);
    }
  }

  return _CatalogCopy.unknownAuthor(context);
}

String _authorDescriptionForSeries(
  BuildContext context,
  String name,
  List<_BundledSeriesPreview> series,
) {
  final isRu = AppLocalizations.of(context).locale.languageCode == 'ru';
  final totalChapters = series.fold<int>(
    0,
    (sum, item) => sum + item.displayChapterCount,
  );
  final formats = {
    for (final item in series) _kindLabelForSeries(context, item.kind),
  }.join(', ');

  if (name == _CatalogCopy.unknownAuthor(context)) {
    return isRu
        ? 'Материалы без указанного автора: $formats, $totalChapters глав.'
        : 'Items without a named author: $formats, $totalChapters chapters.';
  }

  return isRu
      ? '$name ведет полку в формате $formats: ${series.length} книг и $totalChapters глав.'
      : '$name curates a $formats shelf with ${series.length} books and $totalChapters chapters.';
}

IconData _authorImageIcon(List<_BundledSeriesPreview> series) {
  final hasManhwa = series.any(
    (item) => item.kind == ArchiveLibraryKind.manhwa,
  );
  final hasManga = series.any((item) => item.kind == ArchiveLibraryKind.manga);
  final hasEpub = series.any((item) => item.kind == ArchiveLibraryKind.epub);
  final hasPdf = series.any((item) => item.kind == ArchiveLibraryKind.pdf);
  if (hasManhwa && hasManga) {
    return Icons.auto_awesome_mosaic_rounded;
  }
  if (hasManhwa) {
    return Icons.collections_bookmark_rounded;
  }
  if (hasEpub && !hasManga) {
    return Icons.menu_book_rounded;
  }
  if (hasPdf && !hasManga) {
    return Icons.picture_as_pdf_rounded;
  }
  return Icons.photo_library_rounded;
}

Color _authorAccentForName(String name) {
  const accents = [
    Color(0xFF7C6BC5),
    Color(0xFFD46844),
    Color(0xFF2E8B78),
    Color(0xFFB45A78),
    Color(0xFF4D7C9D),
  ];
  final hash = name.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
  return accents[hash % accents.length];
}

Color _collectionAccentForName(String name) {
  const accents = [
    Color(0xFF4D7C9D),
    Color(0xFFD46844),
    Color(0xFF2E8B78),
    Color(0xFFB45A78),
    Color(0xFF7C6BC5),
  ];
  final hash = name.codeUnits.fold<int>(17, (sum, unit) => (sum * 31) + unit);
  return accents[hash.abs() % accents.length];
}

String _authorInitials(String name) {
  final parts = name
      .replaceAll(RegExp(r'[^A-Za-z0-9А-Яа-яЁё]+'), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    return '?';
  }

  return parts.take(2).map((part) => part.substring(0, 1).toUpperCase()).join();
}

String _kindLabelForSeries(BuildContext context, ArchiveLibraryKind kind) {
  final l10n = AppLocalizations.of(context);
  return switch (kind) {
    ArchiveLibraryKind.manhwa => l10n.manhwaReader,
    ArchiveLibraryKind.manga => l10n.mangaReader,
    ArchiveLibraryKind.epub => l10n.epubReaderTitle,
    ArchiveLibraryKind.pdf => l10n.pdfReaderTitle,
  };
}

IconData _iconForCatalogKind(ArchiveLibraryKind kind) => switch (kind) {
  ArchiveLibraryKind.manhwa => Icons.collections_bookmark_rounded,
  ArchiveLibraryKind.manga => Icons.photo_library_rounded,
  ArchiveLibraryKind.epub => Icons.menu_book_rounded,
  ArchiveLibraryKind.pdf => Icons.picture_as_pdf_rounded,
};

Color _accentForCatalogKind(ReaderPalette palette, ArchiveLibraryKind kind) =>
    switch (kind) {
      ArchiveLibraryKind.manhwa => palette.accent,
      ArchiveLibraryKind.manga => palette.titleColor.withValues(alpha: 0.82),
      ArchiveLibraryKind.epub => const Color(0xFF4D7C9D),
      ArchiveLibraryKind.pdf => const Color(0xFFD95757),
    };

int _stableBookNumber(String value) {
  return value.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
}

_CatalogBookInfo _bookInfoForSeries(
  BuildContext context,
  ReaderPalette palette,
  _BundledSeriesPreview series,
) {
  final l10n = AppLocalizations.of(context);
  final isRu = l10n.locale.languageCode == 'ru';
  final author = _authorNameForSeries(context, series);
  final category = series.categoryNames.isEmpty
      ? _kindLabelForSeries(context, series.kind)
      : series.categoryNames.join(', ');
  final hash = _stableBookNumber(series.id);
  final releaseYear = series.releaseYear ?? 2018 + (hash % 8);
  final language = series.language.trim().isEmpty
      ? (isRu ? 'Русский' : 'Russian')
      : series.language.trim();
  final ageRating = series.recommendedAge != null
      ? '${series.recommendedAge}+'
      : series.id.toLowerCase().contains('doing_it')
      ? '18+'
      : series.displayChapterCount >= 40
      ? '16+'
      : '12+';
  final fallbackDescription = isRu
      ? 'РљРЅРёРіР° "${series.title}" РЅР° РїРѕР»РєРµ "$category": ${l10n.chaptersCount(series.displayChapterCount)}, Р°РІС‚РѕСЂ $author, РіРѕРґ РІС‹РїСѓСЃРєР° $releaseYear.'
      : '"${series.title}" sits in the $category shelf: ${l10n.chaptersCount(series.displayChapterCount)}, by $author, released in $releaseYear.';
  final description = series.description.trim().isEmpty
      ? series.displayChapterCount == 0
            ? (isRu
                  ? 'Книга "${series.title}" на полке "$category": автор $author, год выпуска $releaseYear.'
                  : '"${series.title}" sits in the $category shelf: by $author, released in $releaseYear.')
            : fallbackDescription
      : series.description.trim();

  return _CatalogBookInfo(
    author: author,
    releaseYear: releaseYear,
    description: description,
    language: language,
    ageRating: ageRating,
    category: category,
    categoryIcon: _iconForCatalogKind(series.kind),
    coverAccent: _accentForCatalogKind(palette, series.kind),
  );
}

void _openArchiveSeries(BuildContext context, _BundledSeriesPreview series) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ArchiveSeriesPage(
        seriesId: series.id,
        title: series.title,
        kind: _remoteKindForCatalogKind(series.kind),
        coverImageUrl: series.coverImageUrl,
        chapters: series.chapters,
      ),
    ),
  );
}

RemoteArchiveKind _remoteKindForCatalogKind(ArchiveLibraryKind kind) {
  return switch (kind) {
    ArchiveLibraryKind.manhwa => RemoteArchiveKind.manhwa,
    ArchiveLibraryKind.manga => RemoteArchiveKind.manga,
    ArchiveLibraryKind.epub => RemoteArchiveKind.epub,
    ArchiveLibraryKind.pdf => RemoteArchiveKind.pdf,
  };
}

void _openBookDetails(
  BuildContext context,
  ReaderPalette palette,
  _BundledSeriesPreview series,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _BookDetailsPage(palette: palette, series: series),
    ),
  );
}

void _openCategoryDetails(
  BuildContext context,
  ReaderPalette palette,
  _LibraryCategoryEntry category,
  ValueChanged<_BundledSeriesPreview> onOpenBook,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _CatalogCategoryDetailPage(
        palette: palette,
        category: category,
        onOpenBook: onOpenBook,
      ),
    ),
  );
}

void _openCollectionDetails(
  BuildContext context,
  ReaderPalette palette,
  _HomeCollectionData collection,
  ValueChanged<_BundledSeriesPreview> onOpenBook,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _CollectionDetailPage(
        palette: palette,
        collection: collection,
        onOpenBook: onOpenBook,
      ),
    ),
  );
}

void _openAuthorDetails(
  BuildContext context,
  ReaderPalette palette,
  _LibraryAuthorEntry author,
  ValueChanged<_BundledSeriesPreview> onOpenBook,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _AuthorDetailPage(
        palette: palette,
        author: author,
        onOpenBook: onOpenBook,
      ),
    ),
  );
}

class _LibrarySearchPage extends StatefulWidget {
  const _LibrarySearchPage({
    required this.palette,
    required this.series,
    required this.categories,
    required this.authors,
    required this.onOpenBook,
  });

  final ReaderPalette palette;
  final List<_BundledSeriesPreview> series;
  final List<_LibraryCategoryEntry> categories;
  final List<_LibraryAuthorEntry> authors;
  final ValueChanged<_BundledSeriesPreview> onOpenBook;

  @override
  State<_LibrarySearchPage> createState() => _LibrarySearchPageState();
}

class _LibrarySearchPageState extends State<_LibrarySearchPage> {
  final TextEditingController _controller = TextEditingController();
  _LibrarySearchScope _scope = _LibrarySearchScope.all;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Widget> _buildResults(BuildContext context) {
    final query = _normalizeCatalogQuery(_controller.text);
    final results = <Widget>[];

    if (_scope == _LibrarySearchScope.all ||
        _scope == _LibrarySearchScope.categories) {
      for (final category in widget.categories) {
        final matches = _matchesCatalogQuery(query, [
          category.title,
          category.description,
          ...category.series.map((series) => series.title),
        ]);
        if (!matches) {
          continue;
        }

        results.add(
          _CatalogResultTile(
            title: category.title,
            typeLabel: _CatalogCopy.categoryResult(context),
            subtitle:
                '${_CatalogCopy.booksCount(context, category.series.length)} · ${category.description}',
            icon: category.icon,
            accent: category.accent,
            onTap: () => _openCategoryDetails(
              context,
              widget.palette,
              category,
              widget.onOpenBook,
            ),
          ),
        );
      }
    }

    if (_scope == _LibrarySearchScope.all ||
        _scope == _LibrarySearchScope.authors) {
      for (final author in widget.authors) {
        final matches = _matchesCatalogQuery(query, [
          author.name,
          ...author.series.map((series) => series.title),
        ]);
        if (!matches) {
          continue;
        }

        results.add(
          _CatalogResultTile(
            title: author.name,
            typeLabel: _CatalogCopy.authorResult(context),
            subtitle:
                '${_CatalogCopy.booksCount(context, author.series.length)} · ${author.description}',
            icon: Icons.badge_rounded,
            accent: author.imageAccent,
            onTap: () => _openAuthorDetails(
              context,
              widget.palette,
              author,
              widget.onOpenBook,
            ),
          ),
        );
      }
    }

    if (_scope == _LibrarySearchScope.all ||
        _scope == _LibrarySearchScope.books) {
      for (final series in widget.series) {
        final info = _bookInfoForSeries(context, widget.palette, series);
        final author = info.author;
        final kindLabel = _kindLabelForSeries(context, series.kind);
        final chapterLabel = _chapterCountLabelForSeries(context, series);
        final matches = _matchesCatalogQuery(query, [
          series.title,
          info.author,
          '${info.releaseYear}',
          info.description,
          info.language,
          info.ageRating,
          info.category,
          kindLabel,
          if (chapterLabel != null) chapterLabel,
        ]);
        if (!matches) {
          continue;
        }

        results.add(
          _CatalogResultTile(
            title: series.title,
            typeLabel: _CatalogCopy.bookResult(context),
            subtitle: chapterLabel == null
                ? '$author · $kindLabel'
                : '$author · $kindLabel · $chapterLabel',
            icon: _iconForCatalogKind(series.kind),
            accent: _accentForCatalogKind(widget.palette, series.kind),
            onTap: () => widget.onOpenBook(series),
          ),
        );
      }
    }

    if (results.isEmpty) {
      return [
        _CatalogEmptyState(
          icon: Icons.search_off_rounded,
          title: _CatalogCopy.emptySearch(context),
          palette: widget.palette,
        ),
      ];
    }

    return results;
  }

  @override
  Widget build(BuildContext context) {
    final results = _buildResults(context);
    return Scaffold(
      appBar: AppBar(title: Text(_CatalogCopy.searchTitle(context))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _SearchPanel(
            palette: widget.palette,
            controller: _controller,
            scope: _scope,
            onScopeChanged: (value) {
              setState(() {
                _scope = value;
              });
            },
            onQueryChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CatalogMetricPill(
                icon: Icons.category_rounded,
                label: _CatalogCopy.categoriesCount(
                  context,
                  widget.categories.length,
                ),
                palette: widget.palette,
              ),
              _CatalogMetricPill(
                icon: Icons.badge_rounded,
                label: _CatalogCopy.authorsCount(
                  context,
                  widget.authors.length,
                ),
                palette: widget.palette,
              ),
              _CatalogMetricPill(
                icon: Icons.menu_book_rounded,
                label: _CatalogCopy.booksCount(context, widget.series.length),
                palette: widget.palette,
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...results,
        ],
      ),
    );
  }
}

class _SearchPanel extends StatelessWidget {
  const _SearchPanel({
    required this.palette,
    required this.controller,
    required this.scope,
    required this.onScopeChanged,
    required this.onQueryChanged,
  });

  final ReaderPalette palette;
  final TextEditingController controller;
  final _LibrarySearchScope scope;
  final ValueChanged<_LibrarySearchScope> onScopeChanged;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              palette.panelBackground,
              palette.accent.withValues(alpha: 0.14),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(
                        Icons.manage_search_rounded,
                        color: palette.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _CatalogCopy.searchTitle(context),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: palette.titleColor,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _CatalogCopy.searchLead(context),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: palette.bodyColor,
                                height: 1.35,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                onChanged: onQueryChanged,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: _CatalogCopy.searchHint(context),
                  filled: true,
                  fillColor: palette.pageBackground.withValues(alpha: 0.78),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(color: palette.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(color: palette.divider),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _SearchScopeCompass(
                palette: palette,
                scope: scope,
                onChanged: onScopeChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchScopeCompass extends StatelessWidget {
  const _SearchScopeCompass({
    required this.palette,
    required this.scope,
    required this.onChanged,
  });

  final ReaderPalette palette;
  final _LibrarySearchScope scope;
  final ValueChanged<_LibrarySearchScope> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        scope: _LibrarySearchScope.all,
        icon: Icons.all_inclusive_rounded,
        label: _CatalogCopy.allScope(context),
      ),
      (
        scope: _LibrarySearchScope.categories,
        icon: Icons.category_rounded,
        label: _CatalogCopy.categoryScope(context),
      ),
      (
        scope: _LibrarySearchScope.authors,
        icon: Icons.badge_rounded,
        label: _CatalogCopy.authorScope(context),
      ),
      (
        scope: _LibrarySearchScope.books,
        icon: Icons.menu_book_rounded,
        label: _CatalogCopy.bookScope(context),
      ),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final item in items)
          _SearchScopeChip(
            icon: item.icon,
            label: item.label,
            selected: scope == item.scope,
            palette: palette,
            onTap: () => onChanged(item.scope),
          ),
      ],
    );
  }
}

class _SearchScopeChip extends StatelessWidget {
  const _SearchScopeChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final ReaderPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = selected ? palette.accent : palette.bodyColor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? palette.accent.withValues(alpha: 0.16)
                : palette.pageBackground.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? palette.accent : palette.divider,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(color: accent, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogBrowseControls extends StatelessWidget {
  const _CatalogBrowseControls({
    required this.palette,
    required this.controller,
    required this.onQueryChanged,
  });

  final ReaderPalette palette;
  final TextEditingController controller;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: TextField(
          controller: controller,
          onChanged: onQueryChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: _CatalogBrowseCopy.browseHint(context),
            filled: true,
            fillColor: palette.pageBackground.withValues(alpha: 0.72),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: palette.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: palette.divider),
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogViewModeButton extends StatelessWidget {
  const _CatalogViewModeButton({
    required this.palette,
    required this.value,
    required this.onChanged,
  });

  final ReaderPalette palette;
  final _CatalogViewMode value;
  final ValueChanged<_CatalogViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_CatalogViewMode>(
      tooltip: _CatalogBrowseCopy.viewBlock(context),
      icon: Icon(_catalogViewModeIcon(value)),
      onSelected: onChanged,
      itemBuilder: (context) {
        return [
          for (final mode in _CatalogViewMode.values)
            PopupMenuItem(
              value: mode,
              child: Row(
                children: [
                  Icon(
                    _catalogViewModeIcon(mode),
                    size: 18,
                    color: mode == value ? palette.accent : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_catalogViewModeLabel(context, mode))),
                  if (mode == value)
                    Icon(Icons.check_rounded, size: 18, color: palette.accent),
                ],
              ),
            ),
        ];
      },
    );
  }
}

IconData _catalogViewModeIcon(_CatalogViewMode mode) => switch (mode) {
  _CatalogViewMode.spotlight => Icons.grid_view_rounded,
  _CatalogViewMode.list => Icons.view_list_rounded,
  _CatalogViewMode.twoColumn => Icons.view_comfy_alt_rounded,
};

String _catalogViewModeLabel(BuildContext context, _CatalogViewMode mode) =>
    switch (mode) {
      _CatalogViewMode.spotlight => _CatalogBrowseCopy.viewBlock(context),
      _CatalogViewMode.list => _CatalogBrowseCopy.viewList(context),
      _CatalogViewMode.twoColumn => _CatalogBrowseCopy.viewTwoColumns(context),
    };

class _CatalogCategoriesPage extends StatelessWidget {
  const _CatalogCategoriesPage({
    required this.palette,
    required this.categories,
    required this.onOpenBook,
  });

  final ReaderPalette palette;
  final List<_LibraryCategoryEntry> categories;
  final ValueChanged<_BundledSeriesPreview> onOpenBook;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_CatalogCopy.categoriesTitle(context))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _CatalogHeader(
            palette: palette,
            icon: Icons.category_rounded,
            title: _CatalogCopy.categoriesTitle(context),
            subtitle: _CatalogCopy.categoriesCount(context, categories.length),
          ),
          const SizedBox(height: 14),
          if (categories.isEmpty)
            _CatalogEmptyState(
              icon: Icons.category_outlined,
              title: _CatalogCopy.noBooks(context),
              palette: palette,
            )
          else
            for (final category in categories)
              _CatalogCategoryTile(
                palette: palette,
                category: category,
                onTap: () => _openCategoryDetails(
                  context,
                  palette,
                  category,
                  onOpenBook,
                ),
              ),
        ],
      ),
    );
  }
}

class _CatalogCategoryDetailPage extends StatelessWidget {
  const _CatalogCategoryDetailPage({
    required this.palette,
    required this.category,
    required this.onOpenBook,
  });

  final ReaderPalette palette;
  final _LibraryCategoryEntry category;
  final ValueChanged<_BundledSeriesPreview> onOpenBook;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(category.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _CatalogHeader(
            palette: palette,
            icon: category.icon,
            title: category.title,
            subtitle:
                '${_CatalogCopy.booksCount(context, category.series.length)} · ${category.description}',
            accent: category.accent,
          ),
          const SizedBox(height: 14),
          if (category.series.isEmpty)
            _CatalogEmptyState(
              icon: category.icon,
              title: _CatalogCopy.noBooks(context),
              palette: palette,
            )
          else
            for (final series in category.series)
              _CatalogSeriesTile(
                palette: palette,
                series: series,
                onTap: () => onOpenBook(series),
              ),
        ],
      ),
    );
  }
}

class _CatalogAuthorsPage extends StatefulWidget {
  const _CatalogAuthorsPage({
    required this.palette,
    required this.authors,
    required this.onOpenBook,
  });

  final ReaderPalette palette;
  final List<_LibraryAuthorEntry> authors;
  final ValueChanged<_BundledSeriesPreview> onOpenBook;

  @override
  State<_CatalogAuthorsPage> createState() => _CatalogAuthorsPageState();
}

class _CatalogAuthorsPageState extends State<_CatalogAuthorsPage> {
  final TextEditingController _searchController = TextEditingController();
  _CatalogViewMode _viewMode = _CatalogViewMode.spotlight;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_LibraryAuthorEntry> _filteredAuthors(BuildContext context) {
    final query = _normalizeCatalogQuery(_searchController.text);
    return [
      for (final author in widget.authors)
        if (_matchesCatalogQuery(query, [
          author.name,
          author.description,
          ...author.series.map((series) => series.title),
          ...author.series.map(
            (series) => _kindLabelForSeries(context, series.kind),
          ),
        ]))
          author,
    ];
  }

  List<Widget> _buildAuthorCards(
    BuildContext context,
    BoxConstraints constraints,
    List<_LibraryAuthorEntry> authors,
  ) {
    if (authors.isEmpty) {
      return [
        _CatalogEmptyState(
          icon: Icons.badge_outlined,
          title: _CatalogCopy.emptySearch(context),
          palette: widget.palette,
        ),
      ];
    }

    final contentWidth = constraints.maxWidth - 32;
    const spacing = 12.0;
    if (_viewMode == _CatalogViewMode.list) {
      return [
        for (final author in authors)
          _AuthorLineTile(
            palette: widget.palette,
            author: author,
            onTap: () => _openAuthorDetails(
              context,
              widget.palette,
              author,
              widget.onOpenBook,
            ),
          ),
      ];
    }

    if (_viewMode == _CatalogViewMode.twoColumn) {
      final columns = contentWidth >= 260 ? 2 : 1;
      final cardWidth = (contentWidth - ((columns - 1) * spacing)) / columns;
      return [
        Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final author in authors)
              _AuthorCompactGridCard(
                width: cardWidth,
                palette: widget.palette,
                author: author,
                onTap: () => _openAuthorDetails(
                  context,
                  widget.palette,
                  author,
                  widget.onOpenBook,
                ),
              ),
          ],
        ),
      ];
    }

    final columns = contentWidth >= 940
        ? 3
        : contentWidth >= 620
        ? 2
        : 1;
    final cardWidth = (contentWidth - ((columns - 1) * spacing)) / columns;
    final featuredAuthor = authors.first;
    final restAuthors = authors.skip(1).toList();

    return [
      _AuthorSpotlightCard(
        palette: widget.palette,
        author: featuredAuthor,
        onTap: () => _openAuthorDetails(
          context,
          widget.palette,
          featuredAuthor,
          widget.onOpenBook,
        ),
      ),
      if (restAuthors.isNotEmpty) ...[
        const SizedBox(height: 12),
        Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final author in restAuthors)
              _AuthorGalleryCard(
                width: cardWidth,
                palette: widget.palette,
                author: author,
                onTap: () => _openAuthorDetails(
                  context,
                  widget.palette,
                  author,
                  widget.onOpenBook,
                ),
              ),
          ],
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final authors = _filteredAuthors(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_CatalogCopy.authorsTitle(context)),
        actions: [
          _CatalogViewModeButton(
            palette: widget.palette,
            value: _viewMode,
            onChanged: (value) {
              setState(() {
                _viewMode = value;
              });
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _CatalogHeader(
                palette: widget.palette,
                icon: Icons.badge_rounded,
                title: _CatalogCopy.authorsTitle(context),
                subtitle: _CatalogCopy.authorsCount(context, authors.length),
                accent: const Color(0xFF7C6BC5),
              ),
              const SizedBox(height: 14),
              _CatalogBrowseControls(
                palette: widget.palette,
                controller: _searchController,
                onQueryChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              ..._buildAuthorCards(context, constraints, authors),
            ],
          );
        },
      ),
    );
  }
}

class _AuthorDetailPage extends StatelessWidget {
  const _AuthorDetailPage({
    required this.palette,
    required this.author,
    required this.onOpenBook,
  });

  final ReaderPalette palette;
  final _LibraryAuthorEntry author;
  final ValueChanged<_BundledSeriesPreview> onOpenBook;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(author.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _AuthorSpotlightCard(
            palette: palette,
            author: author,
            expanded: true,
          ),
          const SizedBox(height: 14),
          for (final series in author.series)
            _CatalogSeriesTile(
              palette: palette,
              series: series,
              onTap: () => onOpenBook(series),
            ),
        ],
      ),
    );
  }
}

class _CatalogBooksPage extends StatefulWidget {
  const _CatalogBooksPage({
    required this.palette,
    required this.series,
    required this.onOpenBook,
  });

  final ReaderPalette palette;
  final List<_BundledSeriesPreview> series;
  final ValueChanged<_BundledSeriesPreview> onOpenBook;

  @override
  State<_CatalogBooksPage> createState() => _CatalogBooksPageState();
}

class _CatalogBooksPageState extends State<_CatalogBooksPage> {
  final TextEditingController _searchController = TextEditingController();
  _CatalogViewMode _viewMode = _CatalogViewMode.spotlight;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_BundledSeriesPreview> _filteredSeries(BuildContext context) {
    final query = _normalizeCatalogQuery(_searchController.text);
    final result = <_BundledSeriesPreview>[];
    for (final series in widget.series) {
      final info = _bookInfoForSeries(context, widget.palette, series);
      final chapterLabel = _chapterCountLabelForSeries(context, series);
      if (_matchesCatalogQuery(query, [
        series.title,
        _authorNameForSeries(context, series),
        _kindLabelForSeries(context, series.kind),
        if (chapterLabel != null) chapterLabel,
        info.description,
        info.language,
        info.ageRating,
        info.category,
      ])) {
        result.add(series);
      }
    }
    return result;
  }

  List<Widget> _buildBookCards(
    BuildContext context,
    BoxConstraints constraints,
    List<_BundledSeriesPreview> series,
  ) {
    if (series.isEmpty) {
      return [
        _CatalogEmptyState(
          icon: Icons.menu_book_outlined,
          title: _CatalogCopy.emptySearch(context),
          palette: widget.palette,
        ),
      ];
    }

    final contentWidth = constraints.maxWidth - 32;
    const spacing = 12.0;
    if (_viewMode == _CatalogViewMode.list) {
      return [
        for (final item in series)
          _CatalogSeriesTile(
            palette: widget.palette,
            series: item,
            onTap: () => widget.onOpenBook(item),
          ),
      ];
    }

    if (_viewMode == _CatalogViewMode.twoColumn) {
      final columns = contentWidth >= 260 ? 2 : 1;
      final cardWidth = (contentWidth - ((columns - 1) * spacing)) / columns;
      return [
        Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in series)
              _BookCompactGridCard(
                width: cardWidth,
                palette: widget.palette,
                series: item,
                onTap: () => widget.onOpenBook(item),
              ),
          ],
        ),
      ];
    }

    return [
      for (final item in series) ...[
        _BookShowcaseCard(
          palette: widget.palette,
          series: item,
          onTap: () => widget.onOpenBook(item),
        ),
        if (item != series.last) const SizedBox(height: 12),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final series = _filteredSeries(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_CatalogCopy.booksTitle(context)),
        actions: [
          _CatalogViewModeButton(
            palette: widget.palette,
            value: _viewMode,
            onChanged: (value) {
              setState(() {
                _viewMode = value;
              });
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _CatalogHeader(
                palette: widget.palette,
                icon: Icons.menu_book_rounded,
                title: _CatalogCopy.booksTitle(context),
                subtitle: _CatalogCopy.booksCount(context, series.length),
                accent: const Color(0xFFD46844),
              ),
              const SizedBox(height: 14),
              _CatalogBrowseControls(
                palette: widget.palette,
                controller: _searchController,
                onQueryChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              ..._buildBookCards(context, constraints, series),
            ],
          );
        },
      ),
    );
  }
}

class _CatalogCollectionsPage extends StatelessWidget {
  const _CatalogCollectionsPage({
    required this.palette,
    required this.collections,
    required this.onOpenBook,
  });

  final ReaderPalette palette;
  final List<_HomeCollectionData> collections;
  final ValueChanged<_BundledSeriesPreview> onOpenBook;

  @override
  Widget build(BuildContext context) {
    final visibleCollections = collections
        .where((collection) => collection.series.isNotEmpty)
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(_CollectionCopy.collectionsTitle(context))),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = constraints.maxWidth - 32;
          final columns = contentWidth >= 960
              ? 3
              : contentWidth >= 620
              ? 2
              : 1;
          const spacing = 12.0;
          final cardWidth =
              (contentWidth - ((columns - 1) * spacing)) / columns;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _CatalogHeader(
                palette: palette,
                icon: Icons.library_books_rounded,
                title: _CollectionCopy.collectionsTitle(context),
                subtitle: _CollectionCopy.collectionsLead(context),
                accent: const Color(0xFF4D7C9D),
              ),
              const SizedBox(height: 14),
              if (visibleCollections.isEmpty)
                _CatalogEmptyState(
                  icon: Icons.library_books_outlined,
                  title: _CollectionCopy.emptyCollections(context),
                  palette: palette,
                )
              else
                Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final collection in visibleCollections)
                      _CollectionLibraryCard(
                        width: cardWidth,
                        palette: palette,
                        collection: collection,
                        onTap: () => _openCollectionDetails(
                          context,
                          palette,
                          collection,
                          onOpenBook,
                        ),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CollectionDetailPage extends StatelessWidget {
  const _CollectionDetailPage({
    required this.palette,
    required this.collection,
    required this.onOpenBook,
  });

  final ReaderPalette palette;
  final _HomeCollectionData collection;
  final ValueChanged<_BundledSeriesPreview> onOpenBook;

  @override
  Widget build(BuildContext context) {
    final totalChapters = collection.series.fold<int>(
      0,
      (sum, item) => sum + item.displayChapterCount,
    );

    return Scaffold(
      appBar: AppBar(title: Text(collection.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _CollectionDetailHeader(
            palette: palette,
            collection: collection,
            totalChapters: totalChapters,
          ),
          const SizedBox(height: 14),
          _CollectionReadingPath(
            palette: palette,
            collection: collection,
            preview: collection.series,
            onSeriesTap: onOpenBook,
          ),
        ],
      ),
    );
  }
}

class _BookDetailsPage extends StatefulWidget {
  const _BookDetailsPage({
    required this.palette,
    required this.series,
    this.popularSeries = const [],
    this.onPopularSeriesTap,
    this.onOpenEpub,
    this.onOpenPdf,
    this.onSeriesChanged,
  });

  final ReaderPalette palette;
  final _BundledSeriesPreview series;
  final List<_BundledSeriesPreview> popularSeries;
  final ValueChanged<_BundledSeriesPreview>? onPopularSeriesTap;
  final Future<void> Function(_BundledSeriesPreview series)? onOpenEpub;
  final Future<void> Function(_BundledSeriesPreview series)? onOpenPdf;
  final ValueChanged<_BundledSeriesPreview>? onSeriesChanged;

  @override
  State<_BookDetailsPage> createState() => _BookDetailsPageState();
}

class _BookDetailsPageState extends State<_BookDetailsPage> {
  static const String _bookReactionPreferencePrefix = 'book_reaction_';

  final ReadingLibraryStore _store = ReadingLibraryStore();
  final OfflineDocumentStore _documentStore = OfflineDocumentStore();

  late _BundledSeriesPreview _series;
  BookReaction _reaction = BookReaction.none;
  bool _isReadLater = false;
  bool _isDocumentDownloaded = false;
  bool _isSaving = false;
  bool _isOpeningBook = false;
  bool _isDownloadingDocument = false;
  bool _isReacting = false;

  String get _bookId => 'archive:${_series.kind.name}:${_series.id}';
  String get _reactionPreferenceKey =>
      '$_bookReactionPreferencePrefix${_series.bookId}';

  @override
  void initState() {
    super.initState();
    _series = widget.series;
    unawaited(_loadReadLaterState());
    unawaited(_loadReactionState());
    unawaited(_loadDocumentDownloadState());
  }

  @override
  void didUpdateWidget(covariant _BookDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.series.id != widget.series.id ||
        oldWidget.series.likesTotal != widget.series.likesTotal ||
        oldWidget.series.dislikesTotal != widget.series.dislikesTotal) {
      _series = widget.series;
      unawaited(_loadReadLaterState());
      unawaited(_loadReactionState());
      unawaited(_loadDocumentDownloadState());
    }
  }

  Future<void> _loadReadLaterState() async {
    final isSaved = await _store.isInReadLater(_bookId);
    if (!mounted) {
      return;
    }

    setState(() {
      _isReadLater = isSaved;
    });
  }

  Future<void> _loadReactionState() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_reactionPreferenceKey);
    final reaction = BookReaction.values.firstWhere(
      (item) => item.name == stored,
      orElse: () => BookReaction.none,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _reaction = reaction;
    });
  }

  Future<void> _loadDocumentDownloadState() async {
    final isDocument = _series.isEpub || _series.isPdf;
    final downloaded = isDocument
        ? await _documentStore.isDownloaded(_bookId)
        : false;
    if (!mounted) {
      return;
    }

    setState(() {
      _isDocumentDownloaded = downloaded;
    });
  }

  ReadingListBook _readLaterBook(BuildContext context) {
    final info = _bookInfoForSeries(context, widget.palette, _series);
    return ReadingListBook(
      id: _bookId,
      title: _series.title,
      author: info.author,
      category: info.category,
      sourceType: _series.isEpub
          ? 'epub'
          : _series.isPdf
          ? 'pdf'
          : 'archive',
      sourcePath: _series.isEpub
          ? _series.epubFileUrl
          : _series.isPdf
          ? _series.pdfFileUrl
          : _series.id,
      chapterCount: _series.displayChapterCount,
      addedAt: DateTime.now(),
    );
  }

  Future<void> _toggleReadLater() async {
    setState(() {
      _isSaving = true;
    });

    if (_isReadLater) {
      await _store.removeReadLater(_bookId);
    } else {
      await _store.addOrUpdateReadLater(_readLaterBook(context));
    }

    if (!mounted) {
      return;
    }

    final nextValue = !_isReadLater;
    setState(() {
      _isReadLater = nextValue;
      _isSaving = false;
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            nextValue
                ? _ReadingLibraryCopy.addedToReadLater(context)
                : _ReadingLibraryCopy.removedFromReadLater(context),
          ),
        ),
      );
  }

  Future<void> _setReaction(BookReaction selected) async {
    if (_isReacting) {
      return;
    }

    final previousReaction = _reaction;
    final nextReaction = previousReaction == selected
        ? BookReaction.none
        : selected;

    setState(() {
      _isReacting = true;
    });

    try {
      final counts = await LibraryApiClient.instance.reactToBook(
        bookId: _series.bookId,
        reaction: nextReaction,
        previousReaction: previousReaction,
      );
      final prefs = await SharedPreferences.getInstance();
      if (nextReaction == BookReaction.none) {
        await prefs.remove(_reactionPreferenceKey);
      } else {
        await prefs.setString(_reactionPreferenceKey, nextReaction.name);
      }

      if (!mounted) {
        return;
      }

      final updatedSeries = _series.copyWith(
        likesTotal: counts.likesTotal,
        dislikesTotal: counts.dislikesTotal,
      );

      setState(() {
        _reaction = nextReaction;
        _series = updatedSeries;
        _isReacting = false;
      });
      widget.onSeriesChanged?.call(updatedSeries);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isReacting = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
    }
  }

  Future<void> _openReaderBook() async {
    final openBook = _series.isPdf ? widget.onOpenPdf : widget.onOpenEpub;
    if (openBook == null || _isOpeningBook) {
      return;
    }
    final series = _series;

    setState(() {
      _isOpeningBook = true;
    });

    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
      await Future<void>.delayed(const Duration(milliseconds: 140));
    }

    await openBook(series);

    if (!mounted) {
      return;
    }

    setState(() {
      _isOpeningBook = false;
    });
  }

  Future<void> _downloadDocument() async {
    final isEpub = _series.isEpub;
    final isPdf = _series.isPdf;
    final sourceUrl = isEpub ? _series.epubFileUrl : _series.pdfFileUrl;
    if ((!isEpub && !isPdf) ||
        sourceUrl.trim().isEmpty ||
        _isDownloadingDocument) {
      return;
    }

    setState(() {
      _isDownloadingDocument = true;
    });

    try {
      final info = _bookInfoForSeries(context, widget.palette, _series);
      await _documentStore.downloadDocument(
        id: _bookId,
        title: _series.title,
        kind: isPdf ? RemoteArchiveKind.pdf : RemoteArchiveKind.epub,
        sourceUrl: sourceUrl,
        fileName: '${_series.title}.${isPdf ? 'pdf' : 'epub'}',
        coverImageUrl: _series.coverImageUrl,
        author: info.author,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _isDocumentDownloaded = true;
        _isDownloadingDocument = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(_ArchiveDownloadsCopy.documentDownloaded(context)),
          ),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isDownloadingDocument = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final series = _series;
    final info = _bookInfoForSeries(context, palette, series);
    final accent = info.coverAccent;
    final hasChapters = series.chapters.isNotEmpty;
    final canOpenEpub =
        series.isEpub &&
        series.epubFileUrl.trim().isNotEmpty &&
        widget.onOpenEpub != null;
    final canOpenPdf =
        series.isPdf &&
        series.pdfFileUrl.trim().isNotEmpty &&
        widget.onOpenPdf != null;
    final canDownloadDocument = canOpenEpub || canOpenPdf;

    return Scaffold(
      appBar: AppBar(title: Text(series.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 720;
                final cover = _BookCoverImage(
                  palette: palette,
                  series: series,
                  info: info,
                  height: wide ? 280 : 270,
                  large: true,
                  showDetailsOverlay: false,
                  interactive: true,
                );
                final content = _BookPassportBlock(
                  palette: palette,
                  series: series,
                  info: info,
                  chapterLabel: _chapterCountLabelForSeries(context, series),
                  expanded: true,
                );

                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        palette.panelBackground,
                        accent.withValues(alpha: 0.16),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 238, child: cover),
                              const SizedBox(width: 20),
                              Expanded(child: content),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              cover,
                              const SizedBox(height: 16),
                              content,
                            ],
                          ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (canOpenEpub || canOpenPdf)
                FilledButton.icon(
                  onPressed: _isOpeningBook ? null : _openReaderBook,
                  icon: _isOpeningBook
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          canOpenPdf
                              ? Icons.picture_as_pdf_rounded
                              : Icons.menu_book_rounded,
                        ),
                  label: Text(_CatalogCopy.readBook(context)),
                )
              else if (hasChapters)
                FilledButton.icon(
                  onPressed: () => _openArchiveSeries(context, series),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(_CatalogCopy.openChapters(context)),
                ),
              FilledButton.tonalIcon(
                onPressed: _isSaving ? null : _toggleReadLater,
                icon: Icon(
                  _isReadLater
                      ? Icons.playlist_add_check_rounded
                      : Icons.playlist_add_rounded,
                ),
                label: Text(
                  _isReadLater
                      ? _ReadingLibraryCopy.removeReadLater(context)
                      : _ReadingLibraryCopy.addReadLater(context),
                ),
              ),
              if (canDownloadDocument)
                FilledButton.tonalIcon(
                  onPressed: _isDownloadingDocument || _isDocumentDownloaded
                      ? null
                      : _downloadDocument,
                  icon: _isDownloadingDocument
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _isDocumentDownloaded
                              ? Icons.download_done_rounded
                              : Icons.download_rounded,
                        ),
                  label: Text(
                    _isDocumentDownloaded
                        ? _ArchiveDownloadsCopy.downloaded(context)
                        : _ArchiveDownloadsCopy.download(context),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _BookReactionPanel(
            palette: palette,
            likes: series.likesTotal,
            dislikes: series.dislikesTotal,
            reaction: _reaction,
            isBusy: _isReacting,
            onLike: () => unawaited(_setReaction(BookReaction.like)),
            onDislike: () => unawaited(_setReaction(BookReaction.dislike)),
          ),
          const SizedBox(height: 18),
          if (widget.popularSeries.isNotEmpty)
            _BookPopularPanel(
              palette: palette,
              series: widget.popularSeries,
              onSeriesTap: widget.onPopularSeriesTap,
            ),
        ],
      ),
    );
  }
}

class _BookPopularPanel extends StatelessWidget {
  const _BookPopularPanel({
    required this.palette,
    required this.series,
    required this.onSeriesTap,
  });

  final ReaderPalette palette;
  final List<_BundledSeriesPreview> series;
  final ValueChanged<_BundledSeriesPreview>? onSeriesTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.panelBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.divider),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      Icons.trending_up_rounded,
                      color: palette.accent,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _PopularCopy.title(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: palette.titleColor,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _PopularCopy.subtitle(context),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.mutedColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 286,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: series.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final item = series[index];
                  final info = _bookInfoForSeries(context, palette, item);
                  final metaLabel =
                      _chapterCountLabelForSeries(context, item) ??
                      '${info.releaseYear} · ${info.ageRating}';

                  return _PopularSeriesCard(
                    width: 188,
                    palette: palette,
                    title: item.title,
                    subtitle: _authorNameForSeries(context, item),
                    coverImageUrl: item.coverImageUrl,
                    categoryLabel: info.category,
                    chaptersLabel: metaLabel,
                    accent: _accentForCatalogKind(palette, item.kind),
                    icon: _iconForCatalogKind(item.kind),
                    indexLabel: '${index + 1}',
                    onTap: onSeriesTap == null
                        ? () {}
                        : () => onSeriesTap!(item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PopularCopy {
  static bool _isRu(BuildContext context) =>
      AppLocalizations.of(context).locale.languageCode == 'ru';

  static String title(BuildContext context) => _isRu(context)
      ? '\u041f\u043e\u043f\u0443\u043b\u044f\u0440\u043d\u043e\u0435'
      : 'Popular';

  static String subtitle(BuildContext context) => _isRu(context)
      ? '\u041a\u043d\u0438\u0433\u0438, \u043a\u043e\u0442\u043e\u0440\u044b\u0435 \u0447\u0430\u0449\u0435 \u043e\u0442\u043a\u0440\u044b\u0432\u0430\u044e\u0442 \u0438 \u0447\u0438\u0442\u0430\u044e\u0442'
      : 'Books readers open and follow most';
}

class _BookReactionPanel extends StatelessWidget {
  const _BookReactionPanel({
    required this.palette,
    required this.likes,
    required this.dislikes,
    required this.reaction,
    required this.isBusy,
    required this.onLike,
    required this.onDislike,
  });

  final ReaderPalette palette;
  final int likes;
  final int dislikes;
  final BookReaction reaction;
  final bool isBusy;
  final VoidCallback onLike;
  final VoidCallback onDislike;

  @override
  Widget build(BuildContext context) {
    final positive = const Color(0xFF2E8B78);
    final negative = const Color(0xFFD46844);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.panelBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.divider),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 430;
            final header = Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      Icons.how_to_vote_rounded,
                      color: palette.accent,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _BookReactionCopy.title(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: palette.titleColor,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _BookReactionCopy.subtitle(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.mutedColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isBusy) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: palette.accent,
                    ),
                  ),
                ],
              ],
            );

            final buttons = Row(
              children: [
                Expanded(
                  child: _BookReactionButton(
                    palette: palette,
                    color: positive,
                    icon: reaction == BookReaction.like
                        ? Icons.thumb_up_alt_rounded
                        : Icons.thumb_up_alt_outlined,
                    label: _BookReactionCopy.like(context),
                    count: likes,
                    selected: reaction == BookReaction.like,
                    onPressed: isBusy ? null : onLike,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _BookReactionButton(
                    palette: palette,
                    color: negative,
                    icon: reaction == BookReaction.dislike
                        ? Icons.thumb_down_alt_rounded
                        : Icons.thumb_down_alt_outlined,
                    label: _BookReactionCopy.dislike(context),
                    count: dislikes,
                    selected: reaction == BookReaction.dislike,
                    onPressed: isBusy ? null : onDislike,
                  ),
                ),
              ],
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [header, const SizedBox(height: 12), buttons],
              );
            }

            return Row(
              children: [
                Expanded(child: header),
                const SizedBox(width: 14),
                SizedBox(width: 290, child: buttons),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BookReactionButton extends StatelessWidget {
  const _BookReactionButton({
    required this.palette,
    required this.color,
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onPressed,
  });

  final ReaderPalette palette;
  final Color color;
  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final foreground = selected ? color : palette.bodyColor;
    final background = selected
        ? color.withValues(alpha: 0.15)
        : palette.pageBackground.withValues(alpha: 0.75);

    return Semantics(
      button: true,
      selected: selected,
      label: '$label $count',
      child: Opacity(
        opacity: disabled ? 0.62 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected
                      ? color.withValues(alpha: 0.75)
                      : palette.divider,
                  width: selected ? 1.4 : 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: foreground, size: 20),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: selected
                          ? color.withValues(alpha: 0.18)
                          : palette.panelBackground,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: selected
                            ? color.withValues(alpha: 0.35)
                            : palette.divider,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BookReactionCopy {
  static bool _isRu(BuildContext context) =>
      AppLocalizations.of(context).locale.languageCode == 'ru';

  static String title(BuildContext context) => _isRu(context)
      ? '\u041e\u0446\u0435\u043d\u043a\u0430 \u043a\u043d\u0438\u0433\u0438'
      : 'Book rating';

  static String subtitle(BuildContext context) => _isRu(context)
      ? '\u041b\u0430\u0439\u043a \u0438\u043b\u0438 \u0434\u0438\u0437\u043b\u0430\u0439\u043a \u043c\u043e\u0436\u043d\u043e \u0438\u0437\u043c\u0435\u043d\u0438\u0442\u044c'
      : 'You can change your reaction later';

  static String like(BuildContext context) =>
      _isRu(context) ? '\u041b\u0430\u0439\u043a' : 'Like';

  static String dislike(BuildContext context) =>
      _isRu(context) ? '\u0414\u0438\u0437\u043b\u0430\u0439\u043a' : 'Dislike';
}

class _DownloadedArchivePage extends StatefulWidget {
  const _DownloadedArchivePage({
    required this.palette,
    required this.onOpenEpub,
    required this.onOpenPdf,
  });

  final ReaderPalette palette;
  final Future<void> Function(OfflineDocument document) onOpenEpub;
  final Future<void> Function(OfflineDocument document) onOpenPdf;

  @override
  State<_DownloadedArchivePage> createState() => _DownloadedArchivePageState();
}

class _DownloadedArchivePageState extends State<_DownloadedArchivePage> {
  final OfflineArchiveStore _offlineStore = OfflineArchiveStore();
  final OfflineDocumentStore _documentStore = OfflineDocumentStore();

  bool _isLoading = true;
  String? _errorMessage;
  List<OfflineArchiveSeries> _series = const [];
  List<OfflineDocument> _documents = const [];
  Map<String, String> _catalogCoverUrls = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_loadDownloads());
  }

  Future<void> _loadDownloads() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final manga = await _offlineStore.loadDownloadedSeries(
        RemoteArchiveKind.manga,
      );
      final manhwa = await _offlineStore.loadDownloadedSeries(
        RemoteArchiveKind.manhwa,
      );
      final catalogCoverUrls = await _loadCatalogCoverUrls();
      final documents = await _documentStore.loadDocuments();
      final items = [...manga, ...manhwa]
        ..sort((a, b) => naturalCompare(a.title, b.title));

      if (!mounted) {
        return;
      }

      setState(() {
        _series = items;
        _documents = documents;
        _catalogCoverUrls = catalogCoverUrls;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<Map<String, String>> _loadCatalogCoverUrls() async {
    try {
      final result = <String, String>{};
      for (final kind in const [
        RemoteArchiveKind.manga,
        RemoteArchiveKind.manhwa,
      ]) {
        final series = await LibraryApiClient.instance.loadArchiveSeries(kind);
        for (final item in series) {
          if (item.imageUrl.trim().isNotEmpty) {
            result[item.id] = item.imageUrl.trim();
          }
        }
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  Future<void> _openSeries(OfflineArchiveSeries series) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArchiveSeriesPage(
          seriesId: series.seriesId,
          title: series.title,
          kind: series.kind,
          coverImageUrl: series.coverImageUrl.trim().isNotEmpty
              ? series.coverImageUrl.trim()
              : (_catalogCoverUrls[series.seriesId] ?? ''),
          chapters: series.chapters,
        ),
      ),
    );

    if (mounted) {
      await _loadDownloads();
    }
  }

  Future<void> _openDocument(OfflineDocument document) async {
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 140));
    if (document.kind == RemoteArchiveKind.pdf) {
      await widget.onOpenPdf(document);
    } else {
      await widget.onOpenEpub(document);
    }
  }

  IconData _iconForKind(RemoteArchiveKind kind) => switch (kind) {
    RemoteArchiveKind.manga => Icons.photo_library_rounded,
    RemoteArchiveKind.manhwa => Icons.collections_bookmark_rounded,
    RemoteArchiveKind.epub => Icons.menu_book_rounded,
    RemoteArchiveKind.pdf => Icons.picture_as_pdf_rounded,
  };

  String _labelForKind(BuildContext context, RemoteArchiveKind kind) {
    final l10n = AppLocalizations.of(context);
    return switch (kind) {
      RemoteArchiveKind.manga => l10n.mangaReader,
      RemoteArchiveKind.manhwa => l10n.manhwaReader,
      RemoteArchiveKind.epub => l10n.epubReaderTitle,
      RemoteArchiveKind.pdf => l10n.pdfReaderTitle,
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return Scaffold(
      appBar: AppBar(title: Text(_ArchiveDownloadsCopy.title(context))),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _DownloadedArchiveMessage(
              palette: palette,
              icon: Icons.error_outline_rounded,
              title: _ArchiveDownloadsCopy.errorTitle(context),
              message: _errorMessage!,
              actionLabel: AppLocalizations.of(context).retry,
              onAction: () => unawaited(_loadDownloads()),
            )
          : _series.isEmpty && _documents.isEmpty
          ? _DownloadedArchiveMessage(
              palette: palette,
              icon: Icons.offline_pin_outlined,
              title: _ArchiveDownloadsCopy.emptyTitle(context),
              message: _ArchiveDownloadsCopy.emptyMessage(context),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _DownloadedArchiveHero(
                  palette: palette,
                  titleCount: _series.length + _documents.length,
                  chapterCount: _series.fold<int>(
                    0,
                    (total, item) => total + item.chapters.length,
                  ),
                ),
                const SizedBox(height: 14),
                for (final document in _documents)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      leading: _DownloadedArchiveCover(
                        imageUrl: document.coverImageUrl,
                        icon: _iconForKind(document.kind),
                        palette: palette,
                      ),
                      title: Text(
                        document.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        [
                          _labelForKind(context, document.kind),
                          if (document.author.trim().isNotEmpty)
                            document.author.trim(),
                        ].join(' - '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => unawaited(_openDocument(document)),
                    ),
                  ),
                for (final series in _series)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      leading: _DownloadedArchiveCover(
                        imageUrl: series.coverImageUrl.trim().isNotEmpty
                            ? series.coverImageUrl.trim()
                            : (_catalogCoverUrls[series.seriesId] ?? ''),
                        icon: _iconForKind(series.kind),
                        palette: palette,
                      ),
                      title: Text(
                        series.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${_labelForKind(context, series.kind)} - ${AppLocalizations.of(context).chaptersCount(series.chapters.length)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => unawaited(_openSeries(series)),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _DownloadedArchiveHero extends StatelessWidget {
  const _DownloadedArchiveHero({
    required this.palette,
    required this.titleCount,
    required this.chapterCount,
  });

  final ReaderPalette palette;
  final int titleCount;
  final int chapterCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              palette.panelBackground,
              const Color(0xFF2E8B78).withValues(alpha: 0.16),
              palette.accent.withValues(alpha: 0.08),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF2E8B78).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: palette.divider),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Icon(
                    Icons.offline_pin_rounded,
                    color: Color(0xFF2E8B78),
                    size: 30,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _ArchiveDownloadsCopy.title(context),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: palette.titleColor,
                            fontWeight: FontWeight.w900,
                            height: 1.05,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _ArchiveDownloadsCopy.lead(context),
                      style: TextStyle(color: palette.bodyColor, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _CatalogMetricPill(
                          icon: Icons.collections_bookmark_rounded,
                          label: '$titleCount',
                          palette: palette,
                          accent: const Color(0xFF2E8B78),
                        ),
                        _CatalogMetricPill(
                          icon: Icons.auto_stories_rounded,
                          label: '$chapterCount',
                          palette: palette,
                          accent: palette.accent,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadedArchiveCover extends StatelessWidget {
  const _DownloadedArchiveCover({
    required this.imageUrl,
    required this.icon,
    required this.palette,
  });

  final String imageUrl;
  final IconData icon;
  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = imageUrl.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 46,
        height: 64,
        child: trimmedUrl.isEmpty
            ? _buildFallback()
            : Image.network(
                trimmedUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildFallback(),
              ),
      ),
    );
  }

  Widget _buildFallback() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.14),
        border: Border.all(color: palette.divider),
      ),
      child: Center(child: Icon(icon, size: 20, color: palette.accent)),
    );
  }
}

class _DownloadedArchiveMessage extends StatelessWidget {
  const _DownloadedArchiveMessage({
    required this.palette,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final ReaderPalette palette;
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 38, color: palette.accent),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: palette.titleColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.bodyColor, height: 1.45),
                  ),
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: onAction,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArchiveDownloadsCopy {
  static bool _isRu(BuildContext context) =>
      AppLocalizations.of(context).locale.languageCode == 'ru';

  static String title(BuildContext context) => _isRu(context)
      ? '\u0421\u043a\u0430\u0447\u0435\u043d\u043d\u044b\u0435'
      : 'Downloads';

  static String lead(BuildContext context) => _isRu(context)
      ? '\u0417\u0434\u0435\u0441\u044c \u043b\u0435\u0436\u0430\u0442 \u0433\u043b\u0430\u0432\u044b, EPUB \u0438 PDF, \u043a\u043e\u0442\u043e\u0440\u044b\u0435 \u043c\u043e\u0436\u043d\u043e \u0447\u0438\u0442\u0430\u0442\u044c \u0431\u0435\u0437 \u0438\u043d\u0442\u0435\u0440\u043d\u0435\u0442\u0430.'
      : 'Downloaded chapters, EPUB, and PDF books available offline live here.';

  static String emptyTitle(BuildContext context) => _isRu(context)
      ? '\u041f\u043e\u043a\u0430 \u043d\u0435\u0442 \u0441\u043a\u0430\u0447\u0430\u043d\u043d\u044b\u0445 \u043a\u043d\u0438\u0433'
      : 'No downloaded books yet';

  static String emptyMessage(BuildContext context) => _isRu(context)
      ? '\u041e\u0442\u043a\u0440\u043e\u0439\u0442\u0435 \u043a\u043d\u0438\u0433\u0443, EPUB, PDF, manga \u0438\u043b\u0438 manhwa, \u0437\u0430\u0442\u0435\u043c \u0441\u043a\u0430\u0447\u0430\u0439\u0442\u0435 \u0435\u0435 \u0434\u043b\u044f \u0447\u0442\u0435\u043d\u0438\u044f \u0431\u0435\u0437 \u0441\u0435\u0440\u0432\u0435\u0440\u0430.'
      : 'Open an EPUB, PDF, manga, or manhwa title, then download it for offline reading.';

  static String errorTitle(BuildContext context) => _isRu(context)
      ? '\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u043e\u0442\u043a\u0440\u044b\u0442\u044c \u0441\u043a\u0430\u0447\u0435\u043d\u043d\u044b\u0435'
      : 'Could not open downloads';

  static String download(BuildContext context) => _isRu(context)
      ? '\u0421\u043a\u0430\u0447\u0430\u0442\u044c'
      : 'Download';

  static String downloaded(BuildContext context) => _isRu(context)
      ? '\u0421\u043a\u0430\u0447\u0430\u043d\u043e'
      : 'Downloaded';

  static String documentDownloaded(BuildContext context) => _isRu(context)
      ? '\u041a\u043d\u0438\u0433\u0430 \u0441\u043a\u0430\u0447\u0430\u043d\u0430'
      : 'Book downloaded';
}

class _SavedReadingPage extends StatefulWidget {
  const _SavedReadingPage({
    required this.palette,
    required this.readLaterBooks,
    required this.bookmarks,
    required this.onOpenBook,
    required this.onRemoveBook,
    required this.onOpenBookmark,
    required this.onRemoveBookmark,
  });

  final ReaderPalette palette;
  final List<ReadingListBook> readLaterBooks;
  final List<ReadingBookmark> bookmarks;
  final Future<void> Function(ReadingListBook book) onOpenBook;
  final Future<void> Function(String id) onRemoveBook;
  final Future<void> Function(ReadingBookmark bookmark) onOpenBookmark;
  final Future<void> Function(String id) onRemoveBookmark;

  @override
  State<_SavedReadingPage> createState() => _SavedReadingPageState();
}

class _SavedReadingPageState extends State<_SavedReadingPage> {
  late List<ReadingListBook> _readLaterBooks;
  late List<ReadingBookmark> _bookmarks;

  @override
  void initState() {
    super.initState();
    _readLaterBooks = widget.readLaterBooks;
    _bookmarks = widget.bookmarks;
  }

  @override
  void didUpdateWidget(covariant _SavedReadingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.readLaterBooks != widget.readLaterBooks) {
      _readLaterBooks = widget.readLaterBooks;
    }
    if (oldWidget.bookmarks != widget.bookmarks) {
      _bookmarks = widget.bookmarks;
    }
  }

  Future<void> _removeReadLater(ReadingListBook book) async {
    await widget.onRemoveBook(book.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _readLaterBooks = [
        for (final item in _readLaterBooks)
          if (item.id != book.id) item,
      ];
    });
    _showRemovedSnack();
  }

  Future<void> _removeBookmark(ReadingBookmark bookmark) async {
    await widget.onRemoveBookmark(bookmark.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _bookmarks = [
        for (final item in _bookmarks)
          if (item.id != bookmark.id) item,
      ];
    });
    _showRemovedSnack();
  }

  void _showRemovedSnack() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(_ReadingLibraryCopy.removed(context))),
      );
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return Scaffold(
      appBar: AppBar(title: Text(_ReadingLibraryCopy.savedTitle(context))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _SavedLibraryHero(
            palette: palette,
            readLaterCount: _readLaterBooks.length,
            bookmarkCount: _bookmarks.length,
          ),
          const SizedBox(height: 16),
          _SavedSectionHeader(
            palette: palette,
            icon: Icons.playlist_add_check_rounded,
            title: _ReadingLibraryCopy.readLater(context),
          ),
          const SizedBox(height: 10),
          if (_readLaterBooks.isEmpty)
            _SavedEmptyPanel(
              palette: palette,
              icon: Icons.menu_book_outlined,
              message: _ReadingLibraryCopy.emptyReadLater(context),
            )
          else
            for (final book in _readLaterBooks)
              _SavedReadLaterCard(
                palette: palette,
                book: book,
                onOpen: () => unawaited(widget.onOpenBook(book)),
                onRemove: () => unawaited(_removeReadLater(book)),
              ),
          const SizedBox(height: 18),
          _SavedSectionHeader(
            palette: palette,
            icon: Icons.bookmark_added_rounded,
            title: _ReadingLibraryCopy.bookmarks(context),
          ),
          const SizedBox(height: 10),
          if (_bookmarks.isEmpty)
            _SavedEmptyPanel(
              palette: palette,
              icon: Icons.bookmark_border_rounded,
              message: _ReadingLibraryCopy.emptyBookmarks(context),
            )
          else
            for (final bookmark in _bookmarks)
              _SavedBookmarkCard(
                palette: palette,
                bookmark: bookmark,
                onOpen: () => unawaited(widget.onOpenBookmark(bookmark)),
                onRemove: () => unawaited(_removeBookmark(bookmark)),
              ),
        ],
      ),
    );
  }
}

class _SavedLibraryHero extends StatelessWidget {
  const _SavedLibraryHero({
    required this.palette,
    required this.readLaterCount,
    required this.bookmarkCount,
  });

  final ReaderPalette palette;
  final int readLaterCount;
  final int bookmarkCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              palette.panelBackground,
              palette.accent.withValues(alpha: 0.16),
              const Color(0xFFD46844).withValues(alpha: 0.12),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: palette.divider),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Icon(
                    Icons.inventory_2_rounded,
                    color: palette.accent,
                    size: 30,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _ReadingLibraryCopy.savedTitle(context),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: palette.titleColor,
                            fontWeight: FontWeight.w900,
                            height: 1.05,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _ReadingLibraryCopy.savedLead(context),
                      style: TextStyle(color: palette.bodyColor, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _CatalogMetricPill(
                          icon: Icons.playlist_add_check_rounded,
                          label: '$readLaterCount',
                          palette: palette,
                          accent: const Color(0xFFD46844),
                        ),
                        _CatalogMetricPill(
                          icon: Icons.bookmark_added_rounded,
                          label: '$bookmarkCount',
                          palette: palette,
                          accent: palette.accent,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavedSectionHeader extends StatelessWidget {
  const _SavedSectionHeader({
    required this.palette,
    required this.icon,
    required this.title,
  });

  final ReaderPalette palette;
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: palette.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: palette.titleColor,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _SavedEmptyPanel extends StatelessWidget {
  const _SavedEmptyPanel({
    required this.palette,
    required this.icon,
    required this.message,
  });

  final ReaderPalette palette;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(icon, color: palette.mutedColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: palette.bodyColor, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedReadLaterCard extends StatelessWidget {
  const _SavedReadLaterCard({
    required this.palette,
    required this.book,
    required this.onOpen,
    required this.onRemove,
  });

  final ReaderPalette palette;
  final ReadingListBook book;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final author = book.author.trim().isEmpty
        ? _ReadingLibraryCopy.unknownAuthor(context)
        : book.author.trim();
    final category = book.category.trim().isEmpty
        ? book.sourceType
        : book.category;
    final subtitle =
        '$author / $category / ${_ReadingLibraryCopy.chapters(context, book.chapterCount)}';

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFD46844).withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const SizedBox(
                  width: 52,
                  height: 64,
                  child: Icon(
                    Icons.menu_book_rounded,
                    color: Color(0xFFD46844),
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: palette.titleColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.bodyColor, height: 1.25),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<int>(
                onSelected: (value) {
                  if (value == 0) {
                    onOpen();
                    return;
                  }
                  onRemove();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 0,
                    child: Text(_ReadingLibraryCopy.open(context)),
                  ),
                  PopupMenuItem(
                    value: 1,
                    child: Text(_ReadingLibraryCopy.delete(context)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavedBookmarkCard extends StatelessWidget {
  const _SavedBookmarkCard({
    required this.palette,
    required this.bookmark,
    required this.onOpen,
    required this.onRemove,
  });

  final ReaderPalette palette;
  final ReadingBookmark bookmark;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final chapterTitle = bookmark.chapterTitle.trim().isEmpty
        ? _ReadingLibraryCopy.chapterNumber(context, bookmark.chapterIndex)
        : bookmark.chapterTitle.trim();
    final subtitle =
        '${_ReadingLibraryCopy.chapterNumber(context, bookmark.chapterIndex)} / $chapterTitle';

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                ),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: Icon(
                    Icons.bookmark_added_rounded,
                    color: palette.accent,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bookmark.bookTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: palette.titleColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.bodyColor, height: 1.25),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<int>(
                onSelected: (value) {
                  if (value == 0) {
                    onOpen();
                    return;
                  }
                  onRemove();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 0,
                    child: Text(_ReadingLibraryCopy.open(context)),
                  ),
                  PopupMenuItem(
                    value: 1,
                    child: Text(_ReadingLibraryCopy.delete(context)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogHeader extends StatelessWidget {
  const _CatalogHeader({
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.accent,
  });

  final ReaderPalette palette;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? palette.accent;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [palette.panelBackground, color.withValues(alpha: 0.13)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(icon, color: color),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: palette.titleColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.bodyColor,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogCategoryTile extends StatelessWidget {
  const _CatalogCategoryTile({
    required this.palette,
    required this.category,
    required this.onTap,
  });

  final ReaderPalette palette;
  final _LibraryCategoryEntry category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        leading: DecoratedBox(
          decoration: BoxDecoration(
            color: category.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(category.icon, color: category.accent),
          ),
        ),
        title: Text(
          category.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${_CatalogCopy.booksCount(context, category.series.length)} · ${category.description}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _AuthorSpotlightCard extends StatelessWidget {
  const _AuthorSpotlightCard({
    required this.palette,
    required this.author,
    this.expanded = false,
    this.onTap,
  });

  final ReaderPalette palette;
  final _LibraryAuthorEntry author;
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 680;
            final portrait = _AuthorPortrait(
              palette: palette,
              author: author,
              height: expanded ? 250 : 218,
            );
            final content = _AuthorInfoBlock(
              palette: palette,
              author: author,
              expanded: expanded,
            );

            if (wide) {
              return Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: expanded ? 260 : 232, child: portrait),
                    const SizedBox(width: 18),
                    Expanded(child: content),
                  ],
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [portrait, const SizedBox(height: 16), content],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AuthorGalleryCard extends StatelessWidget {
  const _AuthorGalleryCard({
    required this.width,
    required this.palette,
    required this.author,
    required this.onTap,
  });

  final double width;
  final ReaderPalette palette;
  final _LibraryAuthorEntry author;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AuthorPortrait(
                  palette: palette,
                  author: author,
                  height: 156,
                  compact: true,
                ),
                const SizedBox(height: 12),
                Text(
                  author.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.titleColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  author.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.bodyColor,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                _CatalogMetricPill(
                  icon: Icons.menu_book_rounded,
                  label: _CatalogCopy.booksCount(context, author.series.length),
                  palette: palette,
                  accent: author.imageAccent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthorCompactGridCard extends StatelessWidget {
  const _AuthorCompactGridCard({
    required this.width,
    required this.palette,
    required this.author,
    required this.onTap,
  });

  final double width;
  final ReaderPalette palette;
  final _LibraryAuthorEntry author;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chapterCount = author.series.fold<int>(
      0,
      (sum, item) => sum + item.displayChapterCount,
    );

    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 172,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: author.imageAccent.withValues(
                          alpha: 0.15,
                        ),
                        foregroundColor: author.imageAccent,
                        child: Text(
                          _authorInitials(author.name),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      const Spacer(),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: author.imageAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: palette.divider),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.menu_book_rounded,
                                size: 14,
                                color: author.imageAccent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${author.series.length}',
                                style: TextStyle(
                                  color: palette.bodyColor,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    author.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: palette.titleColor,
                      fontWeight: FontWeight.w900,
                      height: 1.08,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Text(
                      author.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.bodyColor,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context).chaptersCount(chapterCount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: author.imageAccent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthorLineTile extends StatelessWidget {
  const _AuthorLineTile({
    required this.palette,
    required this.author,
    required this.onTap,
  });

  final ReaderPalette palette;
  final _LibraryAuthorEntry author;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chapterCount = author.series.fold<int>(
      0,
      (sum, item) => sum + item.displayChapterCount,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        leading: CircleAvatar(
          backgroundColor: author.imageAccent.withValues(alpha: 0.14),
          foregroundColor: author.imageAccent,
          child: Text(
            _authorInitials(author.name),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        title: Text(
          author.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.titleColor,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          '${_CatalogCopy.booksCount(context, author.series.length)} / ${AppLocalizations.of(context).chaptersCount(chapterCount)}\n${author.description}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: palette.bodyColor, height: 1.3),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _AuthorInfoBlock extends StatelessWidget {
  const _AuthorInfoBlock({
    required this.palette,
    required this.author,
    required this.expanded,
  });

  final ReaderPalette palette;
  final _LibraryAuthorEntry author;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final chapterCount = author.series.fold<int>(
      0,
      (sum, item) => sum + item.displayChapterCount,
    );
    final formats = {
      for (final item in author.series) _kindLabelForSeries(context, item.kind),
    }.join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          author.name,
          maxLines: expanded ? 3 : 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: palette.titleColor,
            fontWeight: FontWeight.w900,
            height: 1.08,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          author.description,
          maxLines: expanded ? 5 : 3,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: palette.bodyColor,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _CatalogMetricPill(
              icon: Icons.menu_book_rounded,
              label: _CatalogCopy.booksCount(context, author.series.length),
              palette: palette,
              accent: author.imageAccent,
            ),
            _CatalogMetricPill(
              icon: Icons.view_list_rounded,
              label: AppLocalizations.of(context).chaptersCount(chapterCount),
              palette: palette,
              accent: author.imageAccent,
            ),
            _CatalogMetricPill(
              icon: Icons.auto_awesome_mosaic_rounded,
              label: formats,
              palette: palette,
              accent: author.imageAccent,
            ),
          ],
        ),
        if (!expanded) ...[
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: Icon(Icons.north_east_rounded, color: author.imageAccent),
          ),
        ],
      ],
    );
  }
}

class _AuthorPortrait extends StatelessWidget {
  const _AuthorPortrait({
    required this.palette,
    required this.author,
    required this.height,
    this.compact = false,
  });

  final ReaderPalette palette;
  final _LibraryAuthorEntry author;
  final double height;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final initials = _authorInitials(author.name);
    final accent = author.imageAccent;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent.withValues(alpha: 0.92),
                    palette.titleColor.withValues(alpha: 0.82),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            Positioned(
              left: -36,
              top: height * 0.18,
              child: Transform.rotate(
                angle: -0.42,
                child: Container(
                  width: height * 1.55,
                  height: compact ? 18 : 26,
                  color: palette.pageBackground.withValues(alpha: 0.18),
                ),
              ),
            ),
            Positioned(
              right: -42,
              bottom: height * 0.25,
              child: Transform.rotate(
                angle: -0.42,
                child: Container(
                  width: height * 1.45,
                  height: compact ? 16 : 22,
                  color: Colors.white.withValues(alpha: 0.16),
                ),
              ),
            ),
            Positioned(
              right: 14,
              top: 14,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.17),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    author.imageIcon,
                    color: Colors.white,
                    size: compact ? 20 : 24,
                  ),
                ),
              ),
            ),
            Center(
              child: Text(
                initials,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Text(
                author.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookCompactGridCard extends StatelessWidget {
  const _BookCompactGridCard({
    required this.width,
    required this.palette,
    required this.series,
    required this.onTap,
  });

  final double width;
  final ReaderPalette palette;
  final _BundledSeriesPreview series;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final info = _bookInfoForSeries(context, palette, series);
    final accent = info.coverAccent;
    final chapterLabel = _chapterCountLabelForSeries(context, series);
    final coverImageUrl = series.coverImageUrl.trim();

    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 284,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: 144,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  accent.withValues(alpha: 0.94),
                                  palette.titleColor.withValues(alpha: 0.82),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                          ),
                          Center(
                            child: Container(
                              width: 86,
                              height: 128,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(13),
                                boxShadow: [
                                  BoxShadow(
                                    color: palette.shadow.withValues(
                                      alpha: 0.24,
                                    ),
                                    blurRadius: 14,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(13),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: palette.panelBackground
                                            .withValues(alpha: 0.68),
                                      ),
                                      child: Icon(
                                        info.categoryIcon,
                                        color: accent,
                                        size: 30,
                                      ),
                                    ),
                                    if (coverImageUrl.isNotEmpty)
                                      Image.network(
                                        coverImageUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                const SizedBox.shrink(),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.black.withValues(alpha: 0.04),
                                  Colors.black.withValues(alpha: 0.42),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                          Positioned(
                            left: 10,
                            top: 10,
                            child: Icon(
                              info.categoryIcon,
                              color: Colors.white,
                              size: 23,
                            ),
                          ),
                          Positioned(
                            right: 10,
                            top: 10,
                            child: Text(
                              '${info.releaseYear}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Positioned(
                            left: 10,
                            right: 10,
                            bottom: 9,
                            child: Text(
                              info.category,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    series.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: palette.titleColor,
                      fontWeight: FontWeight.w900,
                      height: 1.08,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    info.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.mutedColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      if (chapterLabel == null)
                        const Spacer()
                      else
                        Expanded(
                          child: Text(
                            chapterLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.11),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          child: Text(
                            info.ageRating,
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BookShowcaseCard extends StatelessWidget {
  const _BookShowcaseCard({
    required this.palette,
    required this.series,
    required this.onTap,
  });

  final ReaderPalette palette;
  final _BundledSeriesPreview series;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final info = _bookInfoForSeries(context, palette, series);
    final child = Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 680;
            final cover = _BookCoverImage(
              palette: palette,
              series: series,
              info: info,
              height: 310,
              large: true,
            );
            final content = _BookPassportBlock(
              palette: palette,
              series: series,
              info: info,
              chapterLabel: _chapterCountLabelForSeries(context, series),
              expanded: true,
            );

            if (wide) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 190, child: cover),
                    const SizedBox(width: 18),
                    Expanded(child: content),
                  ],
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [cover, const SizedBox(height: 12), content],
              ),
            );
          },
        ),
      ),
    );
    return child;
  }
}

class _BookPassportBlock extends StatelessWidget {
  const _BookPassportBlock({
    required this.palette,
    required this.series,
    required this.info,
    required this.chapterLabel,
    required this.expanded,
  });

  final ReaderPalette palette;
  final _BundledSeriesPreview series;
  final _CatalogBookInfo info;
  final String? chapterLabel;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final accent = info.coverAccent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          series.title,
          maxLines: expanded ? 3 : 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: palette.titleColor,
            fontWeight: FontWeight.w900,
            height: 1.08,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          info.author,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: palette.mutedColor,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          info.description,
          maxLines: expanded ? 4 : 3,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: palette.bodyColor,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _BookFactChip(
              icon: Icons.calendar_month_rounded,
              label: '${info.releaseYear}',
              palette: palette,
              accent: accent,
            ),
            _BookFactChip(
              icon: Icons.translate_rounded,
              label: info.language,
              palette: palette,
              accent: accent,
            ),
            _BookFactChip(
              icon: Icons.shield_rounded,
              label: info.ageRating,
              palette: palette,
              accent: accent,
            ),
            _BookFactChip(
              icon: info.categoryIcon,
              label: info.category,
              palette: palette,
              accent: accent,
            ),
            if (chapterLabel != null)
              _BookFactChip(
                icon: Icons.view_list_rounded,
                label: chapterLabel!,
                palette: palette,
                accent: accent,
              ),
          ],
        ),
      ],
    );
  }
}

class _BookCoverImage extends StatefulWidget {
  const _BookCoverImage({
    required this.palette,
    required this.series,
    required this.info,
    required this.height,
    this.large = false,
    this.showDetailsOverlay = true,
    this.interactive = false,
  });

  final ReaderPalette palette;
  final _BundledSeriesPreview series;
  final _CatalogBookInfo info;
  final double height;
  final bool large;
  final bool showDetailsOverlay;
  final bool interactive;

  @override
  State<_BookCoverImage> createState() => _BookCoverImageState();
}

class _BookCoverImageState extends State<_BookCoverImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _coverGlowController;
  Alignment _coverTouchAlignment = Alignment.center;
  bool _isCoverPressed = false;

  @override
  void initState() {
    super.initState();
    _coverGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat();
  }

  @override
  void dispose() {
    _coverGlowController.dispose();
    super.dispose();
  }

  void _setCoverTouch(Offset localPosition, Size size) {
    if (!widget.interactive || size.width <= 0 || size.height <= 0) {
      return;
    }
    final x = ((localPosition.dx / size.width) * 2 - 1).clamp(-1.0, 1.0);
    final y = ((localPosition.dy / size.height) * 2 - 1).clamp(-1.0, 1.0);
    setState(() {
      _isCoverPressed = true;
      _coverTouchAlignment = Alignment(x, y);
    });
  }

  void _resetCoverTouch() {
    if (!widget.interactive) {
      return;
    }
    setState(() {
      _isCoverPressed = false;
      _coverTouchAlignment = Alignment.center;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final series = widget.series;
    final info = widget.info;
    final height = widget.height;
    final large = widget.large;
    final accent = info.coverAccent;
    final coverImageUrl = series.coverImageUrl.trim();

    return LayoutBuilder(
      builder: (context, constraints) {
        final coverOnly = !widget.showDetailsOverlay;
        final coverOnlyHeight = height - (large ? 34 : 28);
        final surfaceWidth = coverOnly
            ? math.min(constraints.maxWidth, coverOnlyHeight * 0.78)
            : constraints.maxWidth;
        final touchSize = Size(surfaceWidth, height);

        final coverSurface = GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: widget.interactive
              ? (details) => _setCoverTouch(details.localPosition, touchSize)
              : null,
          onTapUp: widget.interactive ? (_) => _resetCoverTouch() : null,
          onTapCancel: widget.interactive ? _resetCoverTouch : null,
          onPanStart: widget.interactive
              ? (details) => _setCoverTouch(details.localPosition, touchSize)
              : null,
          onPanUpdate: widget.interactive
              ? (details) => _setCoverTouch(details.localPosition, touchSize)
              : null,
          onPanEnd: widget.interactive ? (_) => _resetCoverTouch() : null,
          onPanCancel: widget.interactive ? _resetCoverTouch : null,
          child: TweenAnimationBuilder<Alignment>(
            tween: AlignmentTween(
              end: widget.interactive ? _coverTouchAlignment : Alignment.center,
            ),
            duration: _isCoverPressed
                ? const Duration(milliseconds: 70)
                : const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            builder: (context, touch, child) {
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateX(_isCoverPressed ? -touch.y * 0.055 : 0)
                  ..rotateY(_isCoverPressed ? touch.x * 0.07 : 0),
                child: child,
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                height: height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            accent.withValues(alpha: 0.95),
                            palette.titleColor.withValues(alpha: 0.86),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                    if (coverImageUrl.isNotEmpty)
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final coverHeight = coverOnly
                                ? height
                                : height - (large ? 34 : 28);
                            final coverWidth = coverOnly
                                ? constraints.maxWidth
                                : math.min(
                                    constraints.maxWidth *
                                        (large ? 0.58 : 0.52),
                                    coverHeight * 0.68,
                                  );

                            return Center(
                              child: SizedBox(
                                width: coverWidth,
                                height: coverHeight,
                                child: AnimatedBuilder(
                                  animation: _coverGlowController,
                                  builder: (context, child) {
                                    final glow =
                                        0.5 -
                                        (math.cos(
                                              _coverGlowController.value *
                                                  math.pi *
                                                  2,
                                            ) *
                                            0.5);
                                    return Container(
                                      width: coverWidth,
                                      height: coverHeight,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(18),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: _isCoverPressed
                                                  ? 0.34
                                                  : 0.22,
                                            ),
                                            blurRadius: _isCoverPressed
                                                ? (large ? 34 : 26)
                                                : (large ? 24 : 18),
                                            offset: Offset(
                                              _coverTouchAlignment.x * -8,
                                              large ? 14 : 10,
                                            ),
                                          ),
                                          BoxShadow(
                                            color: accent.withValues(
                                              alpha: 0.18 + glow * 0.22,
                                            ),
                                            blurRadius: 16 + glow * 26,
                                            spreadRadius: 1.5 + glow * 4,
                                          ),
                                          BoxShadow(
                                            color: Colors.white.withValues(
                                              alpha: 0.05 + glow * 0.10,
                                            ),
                                            blurRadius: 8 + glow * 14,
                                            spreadRadius: glow * 1.6,
                                          ),
                                        ],
                                      ),
                                      child: child,
                                    );
                                  },
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(18),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.network(
                                          coverImageUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  const SizedBox.shrink(),
                                        ),
                                        AnimatedBuilder(
                                          animation: _coverGlowController,
                                          builder: (context, child) {
                                            final glow =
                                                0.5 -
                                                (math.cos(
                                                      _coverGlowController
                                                              .value *
                                                          math.pi *
                                                          2,
                                                    ) *
                                                    0.5);
                                            return IgnorePointer(
                                              child: DecoratedBox(
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      Colors.white.withValues(
                                                        alpha: 0.02,
                                                      ),
                                                      accent.withValues(
                                                        alpha:
                                                            0.03 + glow * 0.04,
                                                      ),
                                                      Colors.white.withValues(
                                                        alpha:
                                                            0.03 + glow * 0.04,
                                                      ),
                                                      Colors.transparent,
                                                    ],
                                                    stops: const [
                                                      0,
                                                      0.36,
                                                      0.50,
                                                      1,
                                                    ],
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  ),
                                                  border: Border.all(
                                                    color: Colors.white
                                                        .withValues(
                                                          alpha:
                                                              0.10 +
                                                              glow * 0.12,
                                                        ),
                                                    width: 1,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                        if (widget.interactive)
                                          AnimatedOpacity(
                                            opacity: _isCoverPressed ? 1 : 0,
                                            duration: const Duration(
                                              milliseconds: 180,
                                            ),
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                gradient: RadialGradient(
                                                  center: _coverTouchAlignment,
                                                  radius: 0.78,
                                                  colors: [
                                                    Colors.white.withValues(
                                                      alpha: 0.42,
                                                    ),
                                                    accent.withValues(
                                                      alpha: 0.16,
                                                    ),
                                                    Colors.transparent,
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (widget.interactive)
                                          AnimatedOpacity(
                                            opacity: _isCoverPressed ? 1 : 0,
                                            duration: const Duration(
                                              milliseconds: 180,
                                            ),
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.34),
                                                  width: 1.4,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(18),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    Positioned(
                      left: coverOnly ? 10 : 16,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: coverOnly ? 8 : 12,
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                    Positioned(
                      right: coverOnly ? -34 : -42,
                      top: coverOnly ? 42 : 28,
                      child: Transform.rotate(
                        angle: -0.55,
                        child: Container(
                          width: height * (coverOnly ? 0.78 : 1.2),
                          height: coverOnly ? 22 : (large ? 34 : 24),
                          color: Colors.white.withValues(alpha: 0.16),
                        ),
                      ),
                    ),
                    Positioned(
                      left: coverOnly ? -26 : -38,
                      bottom: coverOnly ? 48 : 34,
                      child: Transform.rotate(
                        angle: -0.55,
                        child: Container(
                          width: height * (coverOnly ? 0.66 : 1),
                          height: coverOnly ? 18 : (large ? 28 : 20),
                          color: palette.pageBackground.withValues(alpha: 0.15),
                        ),
                      ),
                    ),
                    if (widget.showDetailsOverlay) ...[
                      Positioned(
                        right: 18,
                        top: 18,
                        child: Text(
                          '${info.releaseYear}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.88),
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          30,
                          large ? 26 : 22,
                          20,
                          18,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.24),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(11),
                                child: Icon(
                                  info.categoryIcon,
                                  color: Colors.white,
                                  size: large ? 28 : 24,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              info.category,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              series.title,
                              maxLines: large ? 4 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontSize: large ? 26 : 21,
                                    fontWeight: FontWeight.w900,
                                    height: 1.03,
                                  ),
                            ),
                            if (large) ...[
                              const SizedBox(height: 10),
                              Text(
                                info.author,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Colors.white.withValues(
                                        alpha: 0.86,
                                      ),
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  _CoverBadge(label: info.language),
                                  const SizedBox(width: 8),
                                  _CoverBadge(label: info.ageRating),
                                ],
                              ),
                            ] else ...[
                              const SizedBox(height: 8),
                              _CoverBadge(label: info.ageRating),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
        if (coverOnly) {
          return Center(
            child: SizedBox(width: surfaceWidth, child: coverSurface),
          );
        }
        return coverSurface;
      },
    );
  }
}

class _CoverBadge extends StatelessWidget {
  const _CoverBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.17),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _BookFactChip extends StatelessWidget {
  const _BookFactChip({
    required this.icon,
    required this.label,
    required this.palette,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final ReaderPalette palette;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: accent, size: 17),
            const SizedBox(width: 7),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.bodyColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutUsPage extends StatelessWidget {
  const _AboutUsPage({required this.palette});

  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    final principles = [
      (
        icon: Icons.explore_rounded,
        title: _InfoCopy.missionTitle(context),
        body: _InfoCopy.missionBody(context),
        accent: palette.accent,
      ),
      (
        icon: Icons.grid_view_rounded,
        title: _InfoCopy.designTitle(context),
        body: _InfoCopy.designBody(context),
        accent: const Color(0xFFD46844),
      ),
      (
        icon: Icons.verified_user_rounded,
        title: _InfoCopy.privacyTitle(context),
        body: _InfoCopy.privacyBody(context),
        accent: const Color(0xFF2E8B78),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(_InfoCopy.aboutTitle(context))),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = constraints.maxWidth - 32;
          final columns = contentWidth >= 900
              ? 3
              : contentWidth >= 620
              ? 2
              : 1;
          const spacing = 12.0;
          final cardWidth =
              (contentWidth - ((columns - 1) * spacing)) / columns;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _InfoConstellationHeader(
                palette: palette,
                title: _InfoCopy.aboutTitle(context),
                subtitle: _InfoCopy.aboutLead(context),
                badge: _InfoCopy.aboutBadge(context),
                icon: Icons.auto_stories_rounded,
                accent: palette.accent,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final item in principles)
                    _InfoPrincipleCard(
                      width: cardWidth,
                      palette: palette,
                      icon: item.icon,
                      title: item.title,
                      body: item.body,
                      accent: item.accent,
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ContactsPage extends StatelessWidget {
  const _ContactsPage({required this.palette});

  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    final channels = [
      const _ContactChannel(
        icon: Icons.mail_rounded,
        title: 'Email',
        value: 'reader.library@example.com',
        note: 'Product, support, and feedback',
        accent: Color(0xFF4D7C9D),
      ),
      const _ContactChannel(
        icon: Icons.alternate_email_rounded,
        title: 'Telegram',
        value: '@reader_library',
        note: 'Fast messages and beta notes',
        accent: Color(0xFF2E8B78),
      ),
      const _ContactChannel(
        icon: Icons.phone_in_talk_rounded,
        title: 'Phone',
        value: '+998 90 000-00-00',
        note: 'Local contact line',
        accent: Color(0xFFD46844),
      ),
      const _ContactChannel(
        icon: Icons.location_on_rounded,
        title: 'Studio',
        value: 'Tashkent Digital Library',
        note: 'Reading tools and archive workflows',
        accent: Color(0xFFB45A78),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(_InfoCopy.contactsTitle(context))),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = constraints.maxWidth - 32;
          final columns = contentWidth >= 900 ? 2 : 1;
          const spacing = 12.0;
          final cardWidth =
              (contentWidth - ((columns - 1) * spacing)) / columns;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _InfoConstellationHeader(
                palette: palette,
                title: _InfoCopy.contactsTitle(context),
                subtitle: _InfoCopy.contactsLead(context),
                badge: 'Reader Library',
                icon: Icons.contact_support_rounded,
                accent: const Color(0xFFB45A78),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final channel in channels)
                    _ContactOrbitCard(
                      width: cardWidth,
                      palette: palette,
                      channel: channel,
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InfoConstellationHeader extends StatelessWidget {
  const _InfoConstellationHeader({
    required this.palette,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.icon,
    required this.accent,
  });

  final ReaderPalette palette;
  final String title;
  final String subtitle;
  final String badge;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              palette.panelBackground,
              accent.withValues(alpha: 0.18),
              palette.titleColor.withValues(alpha: 0.08),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -34,
              top: -30,
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 132,
                color: accent.withValues(alpha: 0.13),
              ),
            ),
            Positioned(
              left: -42,
              bottom: -48,
              child: Icon(
                Icons.blur_on_rounded,
                size: 150,
                color: palette.titleColor.withValues(alpha: 0.08),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: palette.divider),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Icon(icon, color: accent, size: 30),
                        ),
                      ),
                      const Spacer(),
                      _BookFactChip(
                        icon: Icons.stars_rounded,
                        label: badge,
                        palette: palette,
                        accent: accent,
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: palette.titleColor,
                      fontWeight: FontWeight.w900,
                      height: 1.06,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: palette.bodyColor,
                        height: 1.48,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoPrincipleCard extends StatelessWidget {
  const _InfoPrincipleCard({
    required this.width,
    required this.palette,
    required this.icon,
    required this.title,
    required this.body,
    required this.accent,
  });

  final double width;
  final ReaderPalette palette;
  final IconData icon;
  final String title;
  final String body;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: accent, width: 4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Icon(icon, color: accent),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: palette.titleColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.bodyColor,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContactChannel {
  const _ContactChannel({
    required this.icon,
    required this.title,
    required this.value,
    required this.note,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String value;
  final String note;
  final Color accent;
}

class _ContactOrbitCard extends StatelessWidget {
  const _ContactOrbitCard({
    required this.width,
    required this.palette,
    required this.channel,
  });

  final double width;
  final ReaderPalette palette;
  final _ContactChannel channel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: channel.value));
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(_InfoCopy.copied(context))));
          },
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  palette.panelBackground,
                  channel.accent.withValues(alpha: 0.12),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 76,
                    height: 76,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: channel.accent.withValues(alpha: 0.11),
                            border: Border.all(color: palette.divider),
                          ),
                          child: const SizedBox.expand(),
                        ),
                        Transform.rotate(
                          angle: -0.7,
                          child: Container(
                            width: 72,
                            height: 22,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: channel.accent.withValues(alpha: 0.14),
                            ),
                          ),
                        ),
                        Icon(channel.icon, color: channel.accent, size: 28),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          channel.title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: palette.titleColor,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          channel.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: channel.accent,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          channel.note,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: palette.bodyColor,
                                height: 1.35,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.content_copy_rounded, color: channel.accent),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogSeriesTile extends StatelessWidget {
  const _CatalogSeriesTile({
    required this.palette,
    required this.series,
    required this.onTap,
  });

  final ReaderPalette palette;
  final _BundledSeriesPreview series;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _accentForCatalogKind(palette, series.kind);
    final author = _authorNameForSeries(context, series);
    final kindLabel = _kindLabelForSeries(context, series.kind);
    final chapterLabel = _chapterCountLabelForSeries(context, series);
    final imageUrl = series.coverImageUrl.trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        leading: SizedBox(
          width: 48,
          height: 68,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.18)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: Icon(
                      _iconForCatalogKind(series.kind),
                      color: accent,
                    ),
                  ),
                  if (imageUrl.isNotEmpty)
                    Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
          ),
        ),
        title: Text(series.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          chapterLabel == null
              ? '$author · $kindLabel'
              : '$author · $kindLabel · $chapterLabel',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _CatalogResultTile extends StatelessWidget {
  const _CatalogResultTile({
    required this.title,
    required this.typeLabel,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String typeLabel;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        leading: DecoratedBox(
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: accent),
          ),
        ),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '$typeLabel · $subtitle',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.north_east_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _CatalogMetricPill extends StatelessWidget {
  const _CatalogMetricPill({
    required this.icon,
    required this.label,
    required this.palette,
    this.accent,
  });

  final IconData icon;
  final String label;
  final ReaderPalette palette;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? palette.accent;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: palette.bodyColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogEmptyState extends StatelessWidget {
  const _CatalogEmptyState({
    required this.icon,
    required this.title,
    required this.palette,
  });

  final IconData icon;
  final String title;
  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: palette.mutedColor),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: palette.mutedColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeHeroBody extends StatelessWidget {
  const _HomeHeroBody({
    required this.palette,
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final ReaderPalette palette;
  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isCompact = MediaQuery.sizeOf(context).width < 430;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Icon(
                  Icons.auto_stories_rounded,
                  size: 30,
                  color: palette.accent,
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
              color: palette.mutedColor,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          title,
          style: textTheme.headlineSmall?.copyWith(
            fontSize: isCompact ? 28 : 34,
            fontWeight: FontWeight.w900,
            height: 1.05,
            color: palette.titleColor,
          ),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            subtitle,
            style: textTheme.bodyLarge?.copyWith(
              color: palette.bodyColor,
              height: 1.55,
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeInfoTile extends StatelessWidget {
  const _HomeInfoTile({
    required this.palette,
    required this.icon,
    required this.title,
    required this.value,
  });

  final ReaderPalette palette;
  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.pageBackground.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(icon, color: palette.accent),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: palette.mutedColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: palette.titleColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerProfileDeck extends StatelessWidget {
  const _DrawerProfileDeck({
    required this.palette,
    required this.initials,
    required this.title,
    required this.subtitle,
    required this.menuLabel,
    required this.statusPills,
    required this.onTap,
  });

  final ReaderPalette palette;
  final String initials;
  final String title;
  final String subtitle;
  final String menuLabel;
  final List<Widget> statusPills;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                palette.panelBackground,
                palette.accent.withValues(alpha: 0.15),
                palette.titleColor.withValues(alpha: 0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: palette.divider),
            boxShadow: [
              BoxShadow(
                color: palette.shadow.withValues(alpha: 0.45),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -28,
                top: -28,
                child: Icon(
                  Icons.auto_stories_rounded,
                  size: 116,
                  color: palette.accent.withValues(alpha: 0.11),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: palette.accent.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                            border: Border.all(color: palette.divider),
                          ),
                          child: SizedBox(
                            width: 58,
                            height: 58,
                            child: Center(
                              child: Text(
                                initials,
                                style: TextStyle(
                                  color: palette.accent,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: palette.pageBackground.withValues(
                              alpha: 0.78,
                            ),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: palette.divider),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.dashboard_customize_rounded,
                                  size: 16,
                                  color: palette.accent,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  menuLabel,
                                  style: TextStyle(
                                    color: palette.bodyColor,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: palette.titleColor,
                            fontWeight: FontWeight.w900,
                            height: 1.04,
                          ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.bodyColor,
                        height: 1.35,
                      ),
                    ),
                    if (statusPills.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Wrap(spacing: 8, runSpacing: 8, children: statusPills),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerQuickActionButton extends StatelessWidget {
  const _DrawerQuickActionButton({
    required this.width,
    required this.icon,
    required this.title,
    required this.accent,
    required this.palette,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final String title;
  final Color accent;
  final ReaderPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.panelBackground.withValues(alpha: 0.84),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: palette.divider),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 11),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.13),
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(icon, color: accent, size: 22),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.bodyColor,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawerCommandGroup extends StatelessWidget {
  const _DrawerCommandGroup({
    required this.label,
    required this.palette,
    required this.children,
  });

  final String label;
  final ReaderPalette palette;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.panelBackground.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: palette.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: palette.titleColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0)
                Divider(height: 1, thickness: 1, color: palette.divider),
              children[index],
            ],
          ],
        ),
      ),
    );
  }
}

class _DrawerSectionLabel extends StatelessWidget {
  const _DrawerSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.palette,
  });

  final IconData icon;
  final String label;
  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.pageBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: palette.accent),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: palette.bodyColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeDrawerActionTile extends StatelessWidget {
  const _HomeDrawerActionTile({
    required this.icon,
    required this.title,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(icon, color: accent, size: 22),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_ios_rounded, color: accent, size: 15),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomePromoBannerData {
  const _HomePromoBannerData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final FutureOr<void> Function() onTap;
}

class _HomeConnectionScreen extends StatelessWidget {
  const _HomeConnectionScreen({
    required this.palette,
    required this.message,
    required this.onRetry,
    required this.onOpenDownloads,
  });

  final ReaderPalette palette;
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onOpenDownloads;

  bool _isRu(BuildContext context) =>
      AppLocalizations.of(context).locale.languageCode == 'ru';

  @override
  Widget build(BuildContext context) {
    final isRu = _isRu(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            palette.pageBackground,
            palette.accent.withValues(alpha: 0.12),
            palette.panelBackground,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 56,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 146,
                                height: 146,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: palette.accent.withValues(alpha: 0.08),
                                ),
                              ),
                              Container(
                                width: 104,
                                height: 104,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: palette.panelBackground,
                                  border: Border.all(color: palette.divider),
                                  boxShadow: [
                                    BoxShadow(
                                      color: palette.shadow.withValues(
                                        alpha: 0.16,
                                      ),
                                      blurRadius: 28,
                                      offset: const Offset(0, 14),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.wifi_off_rounded,
                                  color: palette.accent,
                                  size: 46,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 30),
                        Text(
                          isRu
                              ? '\u041d\u0435\u0442 \u043f\u043e\u0434\u043a\u043b\u044e\u0447\u0435\u043d\u0438\u044f'
                              : 'No connection',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: palette.titleColor,
                                fontWeight: FontWeight.w900,
                                height: 1.08,
                              ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          isRu
                              ? '\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u043f\u043e\u0434\u043a\u043b\u044e\u0447\u0438\u0442\u044c\u0441\u044f \u043a \u0441\u0435\u0440\u0432\u0435\u0440\u0443. \u041f\u043e\u043f\u0440\u043e\u0431\u0443\u0439\u0442\u0435 \u0441\u043d\u043e\u0432\u0430 \u0438\u043b\u0438 \u043e\u0442\u043a\u0440\u043e\u0439\u0442\u0435 \u0441\u043a\u0430\u0447\u0430\u043d\u043d\u044b\u0435 \u043a\u043d\u0438\u0433\u0438.'
                              : 'The server is unavailable. Try again or open your downloaded books.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: palette.bodyColor,
                                height: 1.45,
                              ),
                        ),
                        const SizedBox(height: 26),
                        FilledButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(AppLocalizations.of(context).tryAgain),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: onOpenDownloads,
                          icon: const Icon(Icons.download_done_rounded),
                          label: Text(
                            isRu
                                ? '\u0427\u0438\u0442\u0430\u0442\u044c \u0441\u043a\u0430\u0447\u0430\u043d\u043d\u043e\u0435'
                                : 'Read downloaded',
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            backgroundColor: palette.panelBackground.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HomeConnectionUnavailable extends StatelessWidget {
  const _HomeConnectionUnavailable({
    required this.palette,
    required this.message,
    required this.onRetry,
    required this.onOpenDownloads,
  });

  final ReaderPalette palette;
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onOpenDownloads;

  bool _isRu(BuildContext context) =>
      AppLocalizations.of(context).locale.languageCode == 'ru';

  @override
  Widget build(BuildContext context) {
    final isRu = _isRu(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              palette.panelBackground,
              palette.accent.withValues(alpha: 0.12),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Icon(
                      Icons.wifi_off_rounded,
                      color: palette.accent,
                      size: 34,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                isRu
                    ? 'Отсутствует подключение к интернету'
                    : 'No internet connection',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: palette.titleColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isRu
                    ? 'Не удалось подключиться к серверу. Проверьте интернет или читайте уже скачанные книги.'
                    : 'The server is unavailable. Check your connection or continue with downloaded books.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: palette.bodyColor,
                  height: 1.4,
                ),
              ),
              if (message.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.mutedColor),
                ),
              ],
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(AppLocalizations.of(context).tryAgain),
                  ),
                  OutlinedButton.icon(
                    onPressed: onOpenDownloads,
                    icon: const Icon(Icons.download_done_rounded),
                    label: Text(isRu ? 'Читать скачанное' : 'Read downloaded'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeCategoryData {
  const _HomeCategoryData({
    required this.id,
    required this.title,
    required this.icon,
    required this.accent,
    this.imageUrl = '',
    this.onTap,
  });

  final String id;
  final String title;
  final IconData icon;
  final Color accent;
  final String imageUrl;
  final FutureOr<void> Function()? onTap;
}

class _HomeCollectionData {
  const _HomeCollectionData({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.icon,
    required this.series,
  });

  final String title;
  final String subtitle;
  final Color accent;
  final IconData icon;
  final List<_BundledSeriesPreview> series;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.palette,
  });

  final String title;
  final String subtitle;
  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: palette.titleColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: palette.mutedColor,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeaturedSeriesCarousel extends StatelessWidget {
  const _FeaturedSeriesCarousel({
    required this.controller,
    required this.currentIndex,
    required this.palette,
    required this.series,
    required this.kindIconBuilder,
    required this.kindAccentBuilder,
    required this.onPageChanged,
    required this.onSeriesTap,
    required this.onReadTap,
  });

  final PageController controller;
  final int currentIndex;
  final ReaderPalette palette;
  final List<_BundledSeriesPreview> series;
  final IconData Function(ArchiveLibraryKind kind) kindIconBuilder;
  final Color Function(ArchiveLibraryKind kind) kindAccentBuilder;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<_BundledSeriesPreview> onSeriesTap;
  final ValueChanged<_BundledSeriesPreview> onReadTap;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 430;

    return Column(
      children: [
        SizedBox(
          height: isCompact ? 314 : 324,
          child: PageView.builder(
            controller: controller,
            itemCount: series.length,
            onPageChanged: onPageChanged,
            clipBehavior: Clip.none,
            itemBuilder: (context, index) {
              final item = series[index];
              final info = _bookInfoForSeries(context, palette, item);
              final metaLabel = '${info.releaseYear} · ${info.ageRating}';
              return AnimatedBuilder(
                animation: controller,
                builder: (context, child) {
                  final page = controller.hasClients
                      ? (controller.page ?? controller.initialPage.toDouble())
                      : currentIndex.toDouble();
                  final delta = (page - index).abs().clamp(0.0, 1.0);
                  final scale = 1 - (delta * 0.08);
                  final translateY = delta * 20;

                  return Transform.translate(
                    offset: Offset(0, translateY),
                    child: Transform.scale(scale: scale, child: child),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _FeaturedSeriesCard(
                    palette: palette,
                    title: item.title,
                    coverImageUrl: item.coverImageUrl,
                    authorLabel: _authorNameForSeries(context, item),
                    categoryLabel: info.category,
                    metaLabel: metaLabel,
                    actionLabel: _CatalogCopy.readBook(context),
                    accent: kindAccentBuilder(item.kind),
                    icon: kindIconBuilder(item.kind),
                    indexLabel: '${index + 1}',
                    onTap: () => onSeriesTap(item),
                    onReadTap: () => onReadTap(item),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _CarouselDots(
          count: series.length,
          currentIndex: currentIndex,
          activeColor: palette.accent,
          inactiveColor: palette.divider,
        ),
      ],
    );
  }
}

class _FeaturedSeriesCard extends StatelessWidget {
  const _FeaturedSeriesCard({
    required this.palette,
    required this.title,
    required this.coverImageUrl,
    required this.authorLabel,
    required this.categoryLabel,
    required this.metaLabel,
    required this.actionLabel,
    required this.accent,
    required this.icon,
    required this.indexLabel,
    required this.onTap,
    required this.onReadTap,
  });

  final ReaderPalette palette;
  final String title;
  final String coverImageUrl;
  final String authorLabel;
  final String categoryLabel;
  final String metaLabel;
  final String actionLabel;
  final Color accent;
  final IconData icon;
  final String indexLabel;
  final VoidCallback onTap;
  final VoidCallback onReadTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final imageUrl = coverImageUrl.trim();

        return Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
            side: BorderSide(color: accent.withValues(alpha: 0.18)),
          ),
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          accent.withValues(alpha: 0.22),
                          palette.pageBackground,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Center(child: Icon(icon, color: accent, size: 54)),
                  ),
                ),
                if (imageUrl.isNotEmpty)
                  Positioned.fill(
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              accent.withValues(alpha: 0.22),
                              palette.pageBackground,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Center(
                          child: Icon(icon, color: accent, size: 54),
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withValues(alpha: 0.04),
                          Colors.black.withValues(alpha: 0.18),
                          Colors.black.withValues(alpha: 0.78),
                        ],
                        stops: const [0.0, 0.45, 1.0],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  top: 14,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_rounded, color: accent, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            '#$indexLabel',
                            style: TextStyle(
                              color: Colors.black.withValues(alpha: 0.88),
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  top: 14,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: compact ? 136 : 190),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.86),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 7,
                        ),
                        child: Text(
                          categoryLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 18,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: compact ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              height: 1.04,
                            ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        authorLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              metaLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.88),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onReadTap,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: accent,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    actionLabel,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.arrow_forward_rounded,
                                    color: Colors.white,
                                    size: 17,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PromoBannerCarousel extends StatelessWidget {
  const _PromoBannerCarousel({
    required this.controller,
    required this.currentIndex,
    required this.palette,
    required this.banners,
    required this.onPageChanged,
  });

  final PageController controller;
  final int currentIndex;
  final ReaderPalette palette;
  final List<_HomePromoBannerData> banners;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 430;

    return Column(
      children: [
        SizedBox(
          height: isCompact ? 214 : 196,
          child: PageView.builder(
            controller: controller,
            itemCount: banners.length,
            onPageChanged: onPageChanged,
            itemBuilder: (context, index) {
              final banner = banners[index];
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _PromoBannerCard(palette: palette, data: banner),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _CarouselDots(
          count: banners.length,
          currentIndex: currentIndex,
          activeColor: palette.accent,
          inactiveColor: palette.divider,
        ),
      ],
    );
  }
}

class _PromoBannerCard extends StatelessWidget {
  const _PromoBannerCard({required this.palette, required this.data});

  final ReaderPalette palette;
  final _HomePromoBannerData data;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 430;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => unawaited(Future<void>.sync(data.onTap)),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                palette.panelBackground,
                data.accent.withValues(alpha: 0.22),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: data.accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Icon(data.icon, color: data.accent),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        data.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: palette.titleColor,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Flexible(
                        child: Text(
                          data.subtitle,
                          maxLines: isCompact ? 3 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: palette.bodyColor,
                                height: 1.35,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Icon(Icons.north_east_rounded, color: data.accent, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeNewBooksCopy {
  const _HomeNewBooksCopy._();

  static bool _isRu(BuildContext context) =>
      AppLocalizations.of(context).locale.languageCode == 'ru';

  static String title(BuildContext context) => _isRu(context)
      ? '\u041d\u043e\u0432\u044b\u0435 \u0434\u043e\u0431\u0430\u0432\u043b\u0435\u043d\u043d\u044b\u0435 \u043a\u043d\u0438\u0433\u0438'
      : 'Newly Added Books';

  static String subtitle(BuildContext context) => _isRu(context)
      ? '\u041f\u043e\u0441\u043b\u0435\u0434\u043d\u0438\u0435 \u043a\u043d\u0438\u0433\u0438, \u043a\u043e\u0442\u043e\u0440\u044b\u0435 \u043f\u043e\u044f\u0432\u0438\u043b\u0438\u0441\u044c \u0432 \u0431\u0438\u0431\u043b\u0438\u043e\u0442\u0435\u043a\u0435.'
      : 'The latest books that appeared in the library.';
}

class _HomeCategoryPreferenceCopy {
  const _HomeCategoryPreferenceCopy._();

  static bool _isRu(BuildContext context) =>
      AppLocalizations.of(context).locale.languageCode == 'ru';

  static String manage(BuildContext context) => _isRu(context)
      ? '\u041d\u0430\u0441\u0442\u0440\u043e\u0438\u0442\u044c \u043a\u0430\u0442\u0435\u0433\u043e\u0440\u0438\u0438'
      : 'Customize categories';

  static String drawerButton(BuildContext context) => _isRu(context)
      ? '\u041c\u043e\u0438 \u043a\u0430\u0442\u0435\u0433\u043e\u0440\u0438\u0438'
      : 'My categories';

  static String title(BuildContext context) => _isRu(context)
      ? '\u041a\u0430\u043a\u0438\u0435 \u043a\u0430\u0442\u0435\u0433\u043e\u0440\u0438\u0438 \u043f\u043e\u043a\u0430\u0437\u044b\u0432\u0430\u0442\u044c?'
      : 'Which categories should appear?';

  static String subtitle(BuildContext context) => _isRu(context)
      ? '\u0412\u044b\u0431\u0435\u0440\u0438\u0442\u0435 \u043f\u043e\u043b\u043a\u0438 \u0434\u043b\u044f \u0433\u043b\u0430\u0432\u043d\u043e\u0439. \u0415\u0441\u043b\u0438 \u043d\u0438\u0447\u0435\u0433\u043e \u043d\u0435 \u0432\u044b\u0431\u0440\u0430\u043d\u043e, \u0431\u0443\u0434\u0443\u0442 \u0432\u0438\u0434\u043d\u044b \u0432\u0441\u0435 \u043a\u0430\u0442\u0435\u0433\u043e\u0440\u0438\u0438.'
      : 'Choose shelves for the home page. If nothing is selected, every category stays visible.';

  static String allMode(BuildContext context) => _isRu(context)
      ? '\u0421\u0435\u0439\u0447\u0430\u0441 \u043d\u0430 \u0433\u043b\u0430\u0432\u043d\u043e\u0439 \u0431\u0443\u0434\u0443\u0442 \u0432\u0438\u0434\u043d\u044b \u0432\u0441\u0435 \u043a\u0430\u0442\u0435\u0433\u043e\u0440\u0438\u0438.'
      : 'All categories will be visible on the home page.';

  static String selectedCount(BuildContext context, int count) => _isRu(context)
      ? '\u0412\u044b\u0431\u0440\u0430\u043d\u043e: $count'
      : 'Selected: $count';

  static String showAll(BuildContext context) => _isRu(context)
      ? '\u041f\u043e\u043a\u0430\u0437\u0430\u0442\u044c \u0432\u0441\u0435'
      : 'Show all';

  static String save(BuildContext context) => _isRu(context)
      ? '\u0421\u043e\u0445\u0440\u0430\u043d\u0438\u0442\u044c'
      : 'Save';
}

class _HomeCategoryPreferenceDialog extends StatefulWidget {
  const _HomeCategoryPreferenceDialog({
    required this.palette,
    required this.categories,
    required this.selectedIds,
  });

  final ReaderPalette palette;
  final List<_HomeCategoryData> categories;
  final Set<String> selectedIds;

  @override
  State<_HomeCategoryPreferenceDialog> createState() =>
      _HomeCategoryPreferenceDialogState();
}

class _HomeCategoryPreferenceDialogState
    extends State<_HomeCategoryPreferenceDialog> {
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.selectedIds.toSet();
  }

  void _toggle(String id) {
    setState(() {
      if (!_selectedIds.add(id)) {
        _selectedIds.remove(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final selectedCount = _selectedIds.length;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * 0.84,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.panelBackground,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: palette.divider),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Icon(Icons.tune_rounded, color: palette.accent),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _HomeCategoryPreferenceCopy.title(context),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: palette.titleColor,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _HomeCategoryPreferenceCopy.subtitle(context),
                            style: TextStyle(
                              color: palette.mutedColor,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: palette.accent.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selectedCount == 0
                              ? Icons.apps_rounded
                              : Icons.checklist_rounded,
                          color: palette.accent,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            selectedCount == 0
                                ? _HomeCategoryPreferenceCopy.allMode(context)
                                : _HomeCategoryPreferenceCopy.selectedCount(
                                    context,
                                    selectedCount,
                                  ),
                            style: TextStyle(
                              color: palette.bodyColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final tileWidth = constraints.maxWidth >= 480
                            ? (constraints.maxWidth - 10) / 2
                            : constraints.maxWidth;
                        return Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final category in widget.categories)
                              SizedBox(
                                width: tileWidth,
                                child: _HomeCategoryPreferenceTile(
                                  palette: palette,
                                  data: category,
                                  selected: _selectedIds.contains(category.id),
                                  onTap: () => _toggle(category.id),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).pop(<String>{}),
                        icon: const Icon(Icons.select_all_rounded),
                        label: Text(
                          _HomeCategoryPreferenceCopy.showAll(context),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () =>
                            Navigator.of(context).pop(_selectedIds.toSet()),
                        icon: const Icon(Icons.check_rounded),
                        label: Text(_HomeCategoryPreferenceCopy.save(context)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeCategoryPreferenceTile extends StatelessWidget {
  const _HomeCategoryPreferenceTile({
    required this.palette,
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final ReaderPalette palette;
  final _HomeCategoryData data;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? data.accent.withValues(alpha: 0.7)
        : palette.divider;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? data.accent.withValues(alpha: 0.12)
                : palette.pageBackground.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: data.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: _HomeCategoryAvatar(data: data, size: 40),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    data.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.titleColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? data.accent : palette.mutedColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeCategoryAvatar extends StatelessWidget {
  const _HomeCategoryAvatar({required this.data, required this.size});

  final _HomeCategoryData data;
  final double size;

  @override
  Widget build(BuildContext context) {
    final imageUrl = data.imageUrl.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        width: size,
        height: size,
        child: imageUrl.isEmpty
            ? Icon(data.icon, size: size * 0.52, color: data.accent)
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Icon(data.icon, size: size * 0.52, color: data.accent),
              ),
      ),
    );
  }
}

class _HomeCategoryChip extends StatelessWidget {
  const _HomeCategoryChip({required this.data, required this.palette});

  final _HomeCategoryData data;
  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: data.onTap == null
            ? null
            : () => unawaited(Future<void>.sync(data.onTap!)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.panelBackground,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: palette.divider),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: data.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: _HomeCategoryAvatar(data: data, size: 34),
                ),
                const SizedBox(width: 10),
                Text(
                  data.title,
                  style: TextStyle(
                    color: palette.bodyColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PopularSeriesCard extends StatelessWidget {
  const _PopularSeriesCard({
    required this.width,
    required this.palette,
    required this.title,
    required this.subtitle,
    required this.coverImageUrl,
    required this.categoryLabel,
    required this.chaptersLabel,
    required this.accent,
    required this.icon,
    required this.indexLabel,
    required this.onTap,
  });

  final double width;
  final ReaderPalette palette;
  final String title;
  final String subtitle;
  final String coverImageUrl;
  final String categoryLabel;
  final String chaptersLabel;
  final Color accent;
  final IconData icon;
  final String indexLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const coverWidth = 84.0;
    const coverHeight = 124.0;

    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: palette.divider),
        ),
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 146,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accent.withValues(alpha: 0.16),
                      palette.pageBackground.withValues(alpha: 0.68),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: 12,
                      top: 10,
                      child: Text(
                        indexLabel.padLeft(2, '0'),
                        style: TextStyle(
                          color: accent.withValues(alpha: 0.22),
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Center(
                      child: Container(
                        width: coverWidth,
                        height: coverHeight,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: palette.shadow.withValues(alpha: 0.22),
                              blurRadius: 16,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.14),
                                ),
                                child: Center(
                                  child: Icon(icon, color: accent, size: 34),
                                ),
                              ),
                              if (coverImageUrl.trim().isNotEmpty)
                                Image.network(
                                  coverImageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Center(
                                    child: Icon(icon, color: accent, size: 34),
                                  ),
                                ),
                              Positioned(
                                left: 0,
                                top: 0,
                                bottom: 0,
                                child: Container(
                                  width: 7,
                                  color: Colors.black.withValues(alpha: 0.16),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      bottom: 10,
                      right: 10,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: palette.panelBackground.withValues(
                            alpha: 0.88,
                          ),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.14),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 6,
                          ),
                          child: Text(
                            categoryLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: palette.titleColor,
                              fontWeight: FontWeight.w900,
                              height: 1.08,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.mutedColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              chaptersLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.bodyColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollectionShelfCard extends StatelessWidget {
  const _CollectionShelfCard({
    required this.width,
    required this.palette,
    required this.data,
    required this.onCollectionTap,
  });

  final double width;
  final ReaderPalette palette;
  final _HomeCollectionData data;
  final VoidCallback onCollectionTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                palette.panelBackground,
                data.accent.withValues(alpha: 0.12),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CollectionCoverStack(
                  palette: palette,
                  collection: data,
                  height: 118,
                ),
                const SizedBox(height: 16),
                Text(
                  data.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: palette.titleColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  data.subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.mutedColor,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: onCollectionTap,
                    icon: const Icon(Icons.library_books_rounded, size: 18),
                    label: Text(_CollectionCopy.openCollection(context)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CollectionLibraryCard extends StatelessWidget {
  const _CollectionLibraryCard({
    required this.width,
    required this.palette,
    required this.collection,
    required this.onTap,
  });

  final double width;
  final ReaderPalette palette;
  final _HomeCollectionData collection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(color: palette.panelBackground),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 10, color: collection.accent),
                ),
                Positioned(
                  left: 10,
                  top: 18,
                  child: Container(
                    width: 54,
                    height: 26,
                    decoration: BoxDecoration(
                      color: collection.accent.withValues(alpha: 0.18),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(14),
                        bottomRight: Radius.circular(14),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CollectionCoverStack(
                        palette: palette,
                        collection: collection,
                        height: 118,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              collection.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: palette.titleColor,
                                    fontWeight: FontWeight.w900,
                                    height: 1.06,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _CollectionCountBadge(
                            palette: palette,
                            collection: collection,
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        collection.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.bodyColor,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CollectionCountBadge extends StatelessWidget {
  const _CollectionCountBadge({
    required this.palette,
    required this.collection,
  });

  final ReaderPalette palette;
  final _HomeCollectionData collection;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: collection.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.collections_bookmark_rounded,
              size: 16,
              color: collection.accent,
            ),
            const SizedBox(width: 5),
            Text(
              '${collection.series.length}',
              style: TextStyle(
                color: palette.titleColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionReadingPath extends StatelessWidget {
  const _CollectionReadingPath({
    required this.palette,
    required this.collection,
    required this.preview,
    required this.onSeriesTap,
  });

  final ReaderPalette palette;
  final _HomeCollectionData collection;
  final List<_BundledSeriesPreview> preview;
  final ValueChanged<_BundledSeriesPreview> onSeriesTap;

  @override
  Widget build(BuildContext context) {
    if (preview.isEmpty) {
      return const SizedBox.shrink();
    }

    final visible = preview;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: collection.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.route_rounded, color: collection.accent, size: 18),
                const SizedBox(width: 7),
                Text(
                  AppLocalizations.of(context).locale.languageCode == 'ru'
                      ? '\u041c\u0430\u0440\u0448\u0440\u0443\u0442'
                      : 'Route',
                  style: TextStyle(
                    color: palette.titleColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (var index = 0; index < visible.length; index++)
              _CollectionRouteStop(
                palette: palette,
                collection: collection,
                series: visible[index],
                index: index,
                isLast: index == visible.length - 1,
                onTap: () => onSeriesTap(visible[index]),
              ),
          ],
        ),
      ),
    );
  }
}

class _CollectionRouteStop extends StatelessWidget {
  const _CollectionRouteStop({
    required this.palette,
    required this.collection,
    required this.series,
    required this.index,
    required this.isLast,
    required this.onTap,
  });

  final ReaderPalette palette;
  final _HomeCollectionData collection;
  final _BundledSeriesPreview series;
  final int index;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 30,
            child: Column(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: collection.accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: collection.accent.withValues(alpha: 0.32),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 30,
                            height: 42,
                            child: series.coverImageUrl.trim().isEmpty
                                ? DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: collection.accent.withValues(
                                        alpha: 0.12,
                                      ),
                                    ),
                                    child: Icon(
                                      collection.icon,
                                      color: collection.accent,
                                      size: 16,
                                    ),
                                  )
                                : Image.network(
                                    series.coverImageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: collection.accent.withValues(
                                          alpha: 0.12,
                                        ),
                                      ),
                                      child: Icon(
                                        collection.icon,
                                        color: collection.accent,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            series.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.titleColor,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: collection.accent,
                          size: 14,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionCoverStack extends StatefulWidget {
  const _CollectionCoverStack({
    required this.palette,
    required this.collection,
    required this.height,
  });

  final ReaderPalette palette;
  final _HomeCollectionData collection;
  final double height;

  @override
  State<_CollectionCoverStack> createState() => _CollectionCoverStackState();
}

class _CollectionCoverStackState extends State<_CollectionCoverStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turnController;
  Timer? _turnTimer;
  int _startIndex = 0;

  @override
  void initState() {
    super.initState();
    _turnController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _scheduleTurn();
  }

  @override
  void didUpdateWidget(covariant _CollectionCoverStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collection.title != widget.collection.title ||
        oldWidget.collection.series.length != widget.collection.series.length) {
      _startIndex = 0;
      _turnController.reset();
      _scheduleTurn();
    }
  }

  @override
  void dispose() {
    _turnTimer?.cancel();
    _turnController.dispose();
    super.dispose();
  }

  void _scheduleTurn() {
    _turnTimer?.cancel();
    if (widget.collection.series.length < 2) {
      return;
    }
    _turnTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _turnController.isAnimating) {
        return;
      }
      _turnController.forward(from: 0).whenComplete(() {
        if (!mounted) {
          return;
        }
        setState(() {
          _startIndex = (_startIndex + 1) % widget.collection.series.length;
        });
        _turnController.reset();
      });
    });
  }

  _BundledSeriesPreview _bookAt(int offset) {
    final series = widget.collection.series;
    return series[(_startIndex + offset) % series.length];
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 260.0;
          const shelfBottom = 16.0;
          final maxVisibleCount = available < 180 ? 3 : 5;
          final visibleCount = widget.collection.series.length
              .clamp(1, maxVisibleCount)
              .toInt();
          final canTurn = widget.collection.series.length > visibleCount;
          final stripCount = canTurn ? visibleCount + 1 : visibleCount;
          final covers = [
            for (var index = 0; index < stripCount; index++)
              canTurn ? _bookAt(index) : widget.collection.series[index],
          ];
          final sidePadding = available < 180 ? 14.0 : 18.0;
          final gap = (available * 0.024).clamp(6.0, 10.0).toDouble();
          final usableWidth = available - (sidePadding * 2);
          final bookWidth =
              ((usableWidth - ((visibleCount - 1) * gap)) / visibleCount)
                  .clamp(34.0, 52.0)
                  .toDouble();
          final rowWidth =
              (bookWidth * visibleCount) + (gap * (visibleCount - 1));
          final maxBookHeight = widget.height - shelfBottom - 28;
          final bookHeight = (bookWidth * 1.62)
              .clamp(64.0, maxBookHeight.clamp(72.0, 96.0))
              .toDouble();
          final rowInset = ((available - rowWidth) / 2)
              .clamp(12.0, available)
              .toDouble();
          final rowLeft = (available - rowWidth) / 2;
          final stepWidth = bookWidth + gap;
          final stripWidth =
              (bookWidth * stripCount) + (gap * (stripCount - 1));

          return Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        widget.collection.accent.withValues(alpha: 0.16),
                        widget.palette.panelBackground,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: widget.palette.divider),
                  ),
                  child: CustomPaint(
                    painter: _CollectionShelfPainter(
                      accent: widget.collection.accent,
                      divider: widget.palette.divider,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: rowInset - 3,
                right: rowInset - 3,
                top: 18,
                bottom: shelfBottom + 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: RadialGradient(
                      center: Alignment.topCenter,
                      radius: 1.05,
                      colors: [
                        widget.collection.accent.withValues(alpha: 0.22),
                        widget.collection.accent.withValues(alpha: 0.05),
                        Colors.transparent,
                      ],
                      stops: const [0, 0.58, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: rowLeft,
                bottom: shelfBottom + 5,
                child: SizedBox(
                  width: rowWidth,
                  height: bookHeight + 13,
                  child: ClipRect(
                    child: AnimatedBuilder(
                      animation: _turnController,
                      builder: (context, child) {
                        final shift = canTurn
                            ? Curves.easeInOutCubic.transform(
                                    _turnController.value,
                                  ) *
                                  stepWidth
                            : 0.0;
                        return Transform.translate(
                          offset: Offset(-shift, 0),
                          child: child,
                        );
                      },
                      child: OverflowBox(
                        alignment: Alignment.centerLeft,
                        minWidth: stripWidth,
                        maxWidth: stripWidth,
                        minHeight: bookHeight + 13,
                        maxHeight: bookHeight + 13,
                        child: SizedBox(
                          width: stripWidth,
                          height: bookHeight + 13,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                top: bookHeight + 3,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (
                                      var index = 0;
                                      index < stripCount;
                                      index++
                                    ) ...[
                                      _CollectionCoverReflection(
                                        accent: widget.collection.accent,
                                        imageUrl: covers[index].coverImageUrl,
                                        width: bookWidth,
                                      ),
                                      if (index != stripCount - 1)
                                        SizedBox(width: gap),
                                    ],
                                  ],
                                ),
                              ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  for (
                                    var index = 0;
                                    index < stripCount;
                                    index++
                                  ) ...[
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        boxShadow: [
                                          BoxShadow(
                                            color: widget.palette.shadow
                                                .withValues(alpha: 0.18),
                                            blurRadius: 12,
                                            offset: const Offset(0, 7),
                                          ),
                                          BoxShadow(
                                            color: widget.collection.accent
                                                .withValues(alpha: 0.10),
                                            blurRadius: 18,
                                            offset: const Offset(0, -2),
                                          ),
                                        ],
                                      ),
                                      child: SizedBox(
                                        height: bookHeight,
                                        child: _CollectionCoverThumb(
                                          palette: widget.palette,
                                          accent: widget.collection.accent,
                                          icon: widget.collection.icon,
                                          imageUrl: covers[index].coverImageUrl,
                                          width: bookWidth,
                                          spineIndex: index,
                                          title: covers[index].title,
                                        ),
                                      ),
                                    ),
                                    if (index != stripCount - 1)
                                      SizedBox(width: gap),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: rowInset,
                right: rowInset,
                bottom: shelfBottom - 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: widget.palette.shadow.withValues(alpha: 0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          widget.palette.panelBackground,
                          widget.collection.accent.withValues(alpha: 0.28),
                          widget.palette.panelBackground,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: widget.palette.divider.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: rowInset + 10,
                right: rowInset + 10,
                bottom: shelfBottom + 8,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: widget.collection.accent.withValues(alpha: 0.14),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CollectionShelfPainter extends CustomPainter {
  const _CollectionShelfPainter({required this.accent, required this.divider});

  final Color accent;
  final Color divider;

  @override
  void paint(Canvas canvas, Size size) {
    final shelfPaint = Paint()
      ..color = divider.withValues(alpha: 0.72)
      ..strokeWidth = 1.2;
    final accentPaint = Paint()
      ..color = accent.withValues(alpha: 0.2)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final panelPaint = Paint()
      ..color = accent.withValues(alpha: 0.055)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final glowPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0.22),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final shelfY = size.height - 18;
    for (var index = 1; index < 4; index++) {
      final x = size.width * index / 4;
      canvas.drawLine(Offset(x, 16), Offset(x, shelfY - 8), panelPaint);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(12, 12, size.width - 24, size.height * 0.36),
        const Radius.circular(18),
      ),
      glowPaint,
    );
    canvas.drawLine(
      Offset(12, shelfY),
      Offset(size.width - 12, shelfY),
      shelfPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.62, 18),
      Offset(size.width - 18, 18),
      accentPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.72, 30),
      Offset(size.width - 22, 30),
      shelfPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CollectionShelfPainter oldDelegate) {
    return oldDelegate.accent != accent || oldDelegate.divider != divider;
  }
}

class _CollectionCoverReflection extends StatelessWidget {
  const _CollectionCoverReflection({
    required this.accent,
    required this.imageUrl,
    required this.width,
  });

  final Color accent;
  final String imageUrl;
  final double width;

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = imageUrl.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: SizedBox(
        width: width,
        height: 10,
        child: trimmedUrl.isEmpty
            ? DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accent.withValues(alpha: 0.22),
                      accent.withValues(alpha: 0.03),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Opacity(
                    opacity: 0.18,
                    child: Image.network(
                      trimmedUrl,
                      fit: BoxFit.cover,
                      alignment: Alignment.bottomCenter,
                      errorBuilder: (_, __, ___) => DecoratedBox(
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                        ),
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.16),
                          Colors.transparent,
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CollectionCoverThumb extends StatelessWidget {
  const _CollectionCoverThumb({
    required this.palette,
    required this.accent,
    required this.icon,
    required this.imageUrl,
    required this.width,
    required this.spineIndex,
    required this.title,
  });

  final ReaderPalette palette;
  final Color accent;
  final IconData icon;
  final String imageUrl;
  final double width;
  final int spineIndex;
  final String title;

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = imageUrl.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.16),
            border: Border.all(color: palette.divider),
          ),
          child: trimmedUrl.isEmpty
              ? _buildSpineFallback(context)
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      trimmedUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _buildSpineFallback(context),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 5,
                        color: Colors.black.withValues(alpha: 0.22),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.10),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.12),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildSpineFallback(BuildContext context) {
    final colors = [
      accent,
      const Color(0xFFD46844),
      const Color(0xFF2E8B78),
      const Color(0xFF4D7C9D),
      const Color(0xFFB45A78),
    ];
    final base = colors[spineIndex % colors.length];
    final initial = title.trim().isEmpty ? '?' : title.trim()[0].toUpperCase();

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [base.withValues(alpha: 0.9), base.withValues(alpha: 0.56)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 7,
              color: Colors.black.withValues(alpha: 0.16),
            ),
          ),
          Positioned(
            left: 10,
            right: 8,
            top: 10,
            child: Container(
              height: 2,
              color: Colors.white.withValues(alpha: 0.46),
            ),
          ),
          Positioned(
            left: 10,
            right: 8,
            bottom: 10,
            child: Container(
              height: 2,
              color: Colors.white.withValues(alpha: 0.34),
            ),
          ),
          Center(
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionDetailHeader extends StatelessWidget {
  const _CollectionDetailHeader({
    required this.palette,
    required this.collection,
    required this.totalChapters,
  });

  final ReaderPalette palette;
  final _HomeCollectionData collection;
  final int totalChapters;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              palette.panelBackground,
              collection.accent.withValues(alpha: 0.16),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CollectionCoverStack(
                palette: palette,
                collection: collection,
                height: 132,
              ),
              const SizedBox(height: 14),
              Text(
                collection.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: palette.titleColor,
                  fontWeight: FontWeight.w900,
                  height: 1.06,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                collection.subtitle,
                style: TextStyle(color: palette.bodyColor, height: 1.4),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _CatalogMetricPill(
                    icon: Icons.menu_book_rounded,
                    label: _CollectionCopy.collectionCount(
                      context,
                      collection.series.length,
                    ),
                    palette: palette,
                    accent: collection.accent,
                  ),
                  if (totalChapters > 0)
                    _CatalogMetricPill(
                      icon: Icons.view_list_rounded,
                      label: AppLocalizations.of(
                        context,
                      ).chaptersCount(totalChapters),
                      palette: palette,
                      accent: collection.accent,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CarouselDots extends StatelessWidget {
  const _CarouselDots({
    required this.count,
    required this.currentIndex,
    required this.activeColor,
    required this.inactiveColor,
  });

  final int count;
  final int currentIndex;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    if (count <= 1) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < count; index++) ...[
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: index == currentIndex ? 20 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: index == currentIndex ? activeColor : inactiveColor,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          if (index != count - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _DashboardActionCard extends StatelessWidget {
  const _DashboardActionCard({
    required this.width,
    required this.compact,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final double width;
  final bool compact;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(compact ? 16 : 18),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: compact ? 0 : 172),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Icon(icon, color: accent),
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_outward_rounded,
                        color: accent,
                        size: 18,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: compact ? 4 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(label),
      ),
    );
  }
}

class _PrimaryChapterMediaView extends StatelessWidget {
  const _PrimaryChapterMediaView({
    required this.book,
    required this.chapterPath,
    required this.media,
    required this.fallbackLabel,
  });

  final EpubBook book;
  final String chapterPath;
  final EpubChapterMedia media;
  final String fallbackLabel;

  @override
  Widget build(BuildContext context) {
    final label = media.label?.trim().isNotEmpty == true
        ? media.label!.trim()
        : fallbackLabel;

    if (media.isInlineSvg) {
      return _InlineSvgView(svgMarkup: media.inlineSvgMarkup, label: label);
    }

    return _EpubImageView(
      book: book,
      chapterPath: chapterPath,
      reference: media.reference,
      label: label,
    );
  }
}

class _EpubImageView extends StatelessWidget {
  const _EpubImageView({
    required this.book,
    required this.chapterPath,
    required this.reference,
    required this.label,
  });

  final EpubBook book;
  final String chapterPath;
  final String? reference;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (reference == null || reference!.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final asset = book.resolveAsset(reference!, currentPath: chapterPath);
    if (asset == null) {
      return _MissingIllustration(label: label ?? reference!);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            constraints.maxWidth.isFinite && constraints.maxWidth > 1
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 64;
        final maxHeight = MediaQuery.sizeOf(context).height * 0.72;

        final Widget imageWidget = asset.isSvg
            ? SvgPicture.memory(
                asset.bytes,
                width: availableWidth,
                fit: BoxFit.contain,
                semanticsLabel: label,
              )
            : Image.memory(
                asset.bytes,
                width: availableWidth,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                errorBuilder: (context, error, stackTrace) {
                  return _MissingIllustration(label: label ?? asset.path);
                },
              );

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _ZoomableMediaScreen.asset(
                      asset: asset,
                      label: label ?? l10n.illustrationLabel,
                    ),
                  ),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: availableWidth,
                        maxHeight: maxHeight,
                      ),
                      child: imageWidget,
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.58),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(
                            Icons.zoom_in_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InlineSvgView extends StatelessWidget {
  const _InlineSvgView({required this.svgMarkup, required this.label});

  final String? svgMarkup;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (svgMarkup == null || svgMarkup!.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            constraints.maxWidth.isFinite && constraints.maxWidth > 1
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 64;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _ZoomableMediaScreen.svg(
                      svgMarkup: svgMarkup!,
                      label: label,
                    ),
                  ),
                );
              },
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: availableWidth,
                      maxHeight: MediaQuery.sizeOf(context).height * 0.72,
                    ),
                    child: SvgPicture.string(
                      svgMarkup!,
                      width: availableWidth,
                      fit: BoxFit.contain,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.58),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.zoom_in_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ZoomableMediaScreen extends StatefulWidget {
  const _ZoomableMediaScreen.asset({required this.asset, required this.label})
    : svgMarkup = null;

  const _ZoomableMediaScreen.svg({required this.svgMarkup, required this.label})
    : asset = null;

  final ResolvedAsset? asset;
  final String? svgMarkup;
  final String label;

  @override
  State<_ZoomableMediaScreen> createState() => _ZoomableMediaScreenState();
}

class _ZoomableMediaScreenState extends State<_ZoomableMediaScreen> {
  static const double _doubleTapZoomScale = 2.5;

  final TransformationController _transformationController =
      TransformationController();
  TapDownDetails? _doubleTapDetails;

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _handleDoubleTap() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    if (currentScale > 1.05) {
      _transformationController.value = Matrix4.identity();
      return;
    }

    final tapPosition = _doubleTapDetails?.localPosition;
    if (tapPosition == null) {
      _transformationController.value = Matrix4.identity()
        ..scale(_doubleTapZoomScale);
      return;
    }

    final scenePosition = _transformationController.toScene(tapPosition);
    _transformationController.value = Matrix4.identity()
      ..translate(
        -scenePosition.dx * (_doubleTapZoomScale - 1),
        -scenePosition.dy * (_doubleTapZoomScale - 1),
      )
      ..scale(_doubleTapZoomScale);
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (widget.svgMarkup != null) {
      child = SvgPicture.string(widget.svgMarkup!, fit: BoxFit.contain);
    } else if (widget.asset!.isSvg) {
      child = SvgPicture.memory(
        widget.asset!.bytes,
        fit: BoxFit.contain,
        semanticsLabel: widget.label,
      );
    } else {
      child = Image.memory(
        widget.asset!.bytes,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF050608),
      appBar: AppBar(
        backgroundColor: const Color(0xAA050608),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onDoubleTapDown: _handleDoubleTapDown,
          onDoubleTap: _handleDoubleTap,
          child: InteractiveViewer(
            transformationController: _transformationController,
            minScale: 1,
            maxScale: 5,
            clipBehavior: Clip.none,
            child: Padding(padding: const EdgeInsets.all(24), child: child),
          ),
        ),
      ),
    );
  }
}

class _MissingIllustration extends StatelessWidget {
  const _MissingIllustration({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, color: colors.primary),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                l10n.missingIllustration(label),
                style: TextStyle(color: colors.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
