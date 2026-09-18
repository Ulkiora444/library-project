import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_localizations.dart';
import 'manhwa_archive.dart';
import 'reading_library_store.dart';

enum _ArchiveReadingMode { vertical, horizontal }

Matrix4 _zoomMatrixForTap({
  required TransformationController controller,
  required Offset localPosition,
  required double scale,
}) {
  final scenePosition = controller.toScene(localPosition);
  return Matrix4.identity()
    ..translate(
      localPosition.dx - scenePosition.dx * scale,
      localPosition.dy - scenePosition.dy * scale,
    )
    ..scale(scale);
}

class ManhwaReaderPage extends StatefulWidget {
  const ManhwaReaderPage({
    super.key,
    required this.libraryItems,
    required this.initialIndex,
  });

  final List<ManhwaLibraryItem> libraryItems;
  final int initialIndex;

  @override
  State<ManhwaReaderPage> createState() => _ManhwaReaderPageState();
}

class _ManhwaReaderPageState extends State<ManhwaReaderPage> {
  static const double _maxContentWidth = 1100;
  static const double _doubleTapScale = 2.5;
  static const String _readingModePreferenceKey = 'archive_reader_mode';

  final ManhwaArchiveParser _parser = ManhwaArchiveParser();
  final ReadingLibraryStore _readingStore = ReadingLibraryStore();
  final PageController _pageController = PageController();
  final TransformationController _transformationController =
      TransformationController();

  late int _currentIndex;
  int _currentPageIndex = 0;
  _ArchiveReadingMode _readingMode = _ArchiveReadingMode.vertical;
  ManhwaChapter? _chapter;
  bool _isLoading = true;
  int _chapterLoadToken = 0;
  int _imageLoadCompleted = 0;
  int _imageLoadTotal = 0;
  int _imageReloadAttempts = 0;
  String _loadingChapterTitle = '';
  String? _errorMessage;
  TapDownDetails? _doubleTapDetails;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex
        .clamp(0, widget.libraryItems.length - 1)
        .toInt();
    unawaited(_loadReadingModePreference());
    unawaited(_loadChapter(_currentIndex));
  }

  Future<void> _loadReadingModePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_readingModePreferenceKey);
    if (!mounted || stored == null) {
      return;
    }

    for (final mode in _ArchiveReadingMode.values) {
      if (mode.name == stored) {
        setState(() {
          _readingMode = mode;
        });
        return;
      }
    }
  }

  Future<void> _saveReadingModePreference(_ArchiveReadingMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_readingModePreferenceKey, mode.name);
  }

  Future<void> _loadChapter(int index) async {
    if (index < 0 || index >= widget.libraryItems.length) {
      return;
    }

    final loadToken = ++_chapterLoadToken;
    final item = widget.libraryItems[index];
    setState(() {
      _isLoading = true;
      _currentIndex = index;
      _currentPageIndex = 0;
      _chapter = null;
      _imageLoadCompleted = 0;
      _imageLoadTotal = 0;
      _imageReloadAttempts = 0;
      _loadingChapterTitle = item.title;
      _errorMessage = null;
      _doubleTapDetails = null;
    });

    try {
      final chapter = item.isNetwork
          ? ManhwaChapter(
              title: item.title,
              sourcePath: item.sourcePath,
              fileName: item.sourcePath.split(':').last,
              pages: item.networkPages,
            )
          : item.isBundledAsset
          ? await _parser.parseAsset(item.sourcePath, titleOverride: item.title)
          : await _parser.parseFile(item.sourcePath, titleOverride: item.title);
      if (!mounted || loadToken != _chapterLoadToken) {
        return;
      }

      setState(() {
        _imageLoadTotal = _precacheableImageCount(chapter);
      });

      await _precacheChapterImages(chapter, loadToken);
      if (!mounted || loadToken != _chapterLoadToken) {
        return;
      }

      setState(() {
        _chapter = chapter;
        _isLoading = false;
      });
      _resetZoom();
      _resetHorizontalPage();
    } catch (error) {
      if (!mounted || loadToken != _chapterLoadToken) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  int _precacheableImageCount(ManhwaChapter chapter) {
    return chapter.pages.length;
  }

  Future<void> _precacheChapterImages(
    ManhwaChapter chapter,
    int loadToken,
  ) async {
    for (final page in chapter.pages) {
      if (!mounted || loadToken != _chapterLoadToken) {
        return;
      }
      if (page.isSvg) {
        _markImageLoaded(loadToken);
        continue;
      }

      final provider = _imageProviderForPage(page);
      if (provider == null) {
        _markImageLoaded(loadToken);
        continue;
      }

      await _precacheImageWithRetry(provider, loadToken);

      _markImageLoaded(loadToken);
    }
  }

  Future<void> _precacheImageWithRetry(
    ImageProvider provider,
    int loadToken,
  ) async {
    const maxAttempts = 3;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (!mounted || loadToken != _chapterLoadToken) {
        return;
      }

      try {
        await precacheImage(
          provider,
          context,
        ).timeout(const Duration(seconds: 18));
        return;
      } catch (_) {
        await provider.evict();
        if (!mounted || loadToken != _chapterLoadToken) {
          return;
        }

        if (attempt < maxAttempts) {
          setState(() {
            _imageReloadAttempts++;
          });
          await Future<void>.delayed(
            Duration(milliseconds: 250 + attempt * 250),
          );
        }
      }
    }

    await provider.evict();
  }

  void _markImageLoaded(int loadToken) {
    if (!mounted || loadToken != _chapterLoadToken) {
      return;
    }

    setState(() {
      _imageLoadCompleted++;
    });
  }

  ImageProvider? _imageProviderForPage(ManhwaPage page) {
    final imageUrl = page.imageUrl;
    if (imageUrl != null) {
      return NetworkImage(imageUrl);
    }

    final bytes = page.bytes;
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    return MemoryImage(bytes);
  }

  void _resetZoom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _transformationController.value = Matrix4.identity();
    });
  }

  void _resetHorizontalPage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) {
        return;
      }
      _pageController.jumpToPage(0);
    });
  }

  void _setReadingMode(_ArchiveReadingMode mode) {
    if (_readingMode == mode) {
      return;
    }

    setState(() {
      _readingMode = mode;
      _currentPageIndex = 0;
    });
    _resetZoom();
    _resetHorizontalPage();
    unawaited(_saveReadingModePreference(mode));
  }

  void _openChapter(int index) {
    Navigator.of(context).maybePop();
    if (!_isLoading && index == _currentIndex) {
      return;
    }
    unawaited(_loadChapter(index));
  }

  void _goToAdjacentChapter(int offset) {
    final nextIndex = _currentIndex + offset;
    if (nextIndex < 0 || nextIndex >= widget.libraryItems.length) {
      return;
    }
    unawaited(_loadChapter(nextIndex));
  }

  Future<void> _saveBookmark() async {
    if (_isLoading || widget.libraryItems.isEmpty) {
      return;
    }

    final item = widget.libraryItems[_currentIndex];
    final seriesId = _seriesIdFromSourcePath(item.sourcePath);
    final bookTitle = formatSeriesTitle(seriesId);
    await _readingStore.addOrUpdateBookmark(
      ReadingBookmark(
        id: 'archive:$seriesId:${item.sourcePath}',
        bookId: 'archive:$seriesId',
        bookTitle: bookTitle,
        chapterTitle: item.title,
        chapterIndex: _currentIndex,
        chapterPath: item.sourcePath,
        sourceType: 'archive',
        sourcePath: item.sourcePath,
        createdAt: DateTime.now(),
      ),
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Закладка сохранена')));
  }

  String _seriesIdFromSourcePath(String sourcePath) {
    final normalized = normalizeArchivePath(sourcePath);
    final segments = normalized
        .split('/')
        .where((item) => item.isNotEmpty)
        .toList();
    if (segments.length >= 4 && segments[0] == 'assets') {
      return segments[2];
    }
    if (segments.length >= 2) {
      return segments[segments.length - 2];
    }
    return normalized;
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _handleDoubleTap() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final tapPosition = _doubleTapDetails?.localPosition ?? Offset.zero;
    if (currentScale > 1.05) {
      _transformationController.value = _zoomMatrixForTap(
        controller: _transformationController,
        localPosition: tapPosition,
        scale: 1,
      );
      return;
    }

    _transformationController.value = _zoomMatrixForTap(
      controller: _transformationController,
      localPosition: tapPosition,
      scale: _doubleTapScale,
    );
  }

  bool _isRussian(AppLocalizations l10n) => l10n.locale.languageCode == 'ru';

  String _readingModeTooltip(AppLocalizations l10n) =>
      _isRussian(l10n) ? 'Режим чтения' : 'Reading mode';

  String _readingModeLabel(AppLocalizations l10n, _ArchiveReadingMode mode) {
    return switch (mode) {
      _ArchiveReadingMode.vertical =>
        _isRussian(l10n) ? 'Вертикально' : 'Vertical scroll',
      _ArchiveReadingMode.horizontal =>
        _isRussian(l10n) ? 'Листать влево/вправо' : 'Swipe left/right',
    };
  }

  IconData _readingModeIcon(_ArchiveReadingMode mode) => switch (mode) {
    _ArchiveReadingMode.vertical => Icons.view_agenda_rounded,
    _ArchiveReadingMode.horizontal => Icons.swap_horiz_rounded,
  };

  String _readerProgressLabel(
    AppLocalizations l10n,
    ManhwaChapter chapter,
    bool hasMultipleChapters,
  ) {
    final chapterLabel = hasMultipleChapters
        ? '${_currentIndex + 1} / ${widget.libraryItems.length}'
        : '';
    final pageLabel = _readingMode == _ArchiveReadingMode.horizontal
        ? (_isRussian(l10n)
              ? 'стр. ${_currentPageIndex + 1} / ${chapter.pages.length}'
              : 'page ${_currentPageIndex + 1} / ${chapter.pages.length}')
        : l10n.pagesCountShort(chapter.pages.length);

    return chapterLabel.isEmpty ? pageLabel : '$chapterLabel · $pageLabel';
  }

  @override
  void dispose() {
    _pageController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chapter = _chapter;
    final hasMultipleChapters = widget.libraryItems.length > 1;

    return Scaffold(
      backgroundColor: const Color(0xFF050608),
      drawer: hasMultipleChapters ? _buildChapterDrawer(context) : null,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0D10),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          chapter?.title ?? widget.libraryItems[_currentIndex].title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (hasMultipleChapters)
            Builder(
              builder: (context) {
                return IconButton(
                  tooltip: l10n.toc,
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(Icons.view_list_rounded),
                );
              },
            ),
          IconButton(
            tooltip: 'Поставить закладку',
            onPressed: _isLoading ? null : () => unawaited(_saveBookmark()),
            icon: const Icon(Icons.bookmark_add_rounded),
          ),
          PopupMenuButton<_ArchiveReadingMode>(
            tooltip: _readingModeTooltip(l10n),
            icon: Icon(_readingModeIcon(_readingMode)),
            onSelected: _setReadingMode,
            itemBuilder: (context) => [
              CheckedPopupMenuItem<_ArchiveReadingMode>(
                value: _ArchiveReadingMode.vertical,
                checked: _readingMode == _ArchiveReadingMode.vertical,
                child: Text(
                  _readingModeLabel(l10n, _ArchiveReadingMode.vertical),
                ),
              ),
              CheckedPopupMenuItem<_ArchiveReadingMode>(
                value: _ArchiveReadingMode.horizontal,
                checked: _readingMode == _ArchiveReadingMode.horizontal,
                child: Text(
                  _readingModeLabel(l10n, _ArchiveReadingMode.horizontal),
                ),
              ),
            ],
          ),
          if (hasMultipleChapters)
            IconButton(
              tooltip: l10n.previousChapter,
              onPressed: _currentIndex > 0
                  ? () => _goToAdjacentChapter(-1)
                  : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
          if (hasMultipleChapters)
            IconButton(
              tooltip: l10n.nextChapter,
              onPressed: _currentIndex < widget.libraryItems.length - 1
                  ? () => _goToAdjacentChapter(1)
                  : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
        ],
      ),
      bottomNavigationBar: chapter == null
          ? null
          : BottomAppBar(
              color: const Color(0xFF0B0D10),
              surfaceTintColor: Colors.transparent,
              child: Row(
                children: [
                  if (hasMultipleChapters)
                    IconButton(
                      tooltip: l10n.previousChapter,
                      onPressed: _currentIndex > 0
                          ? () => _goToAdjacentChapter(-1)
                          : null,
                      icon: const Icon(Icons.navigate_before_rounded),
                    ),
                  Expanded(
                    child: Text(
                      hasMultipleChapters
                          ? '${_currentIndex + 1} / ${widget.libraryItems.length} · ${l10n.pagesCountShort(chapter.pages.length)}'
                          : l10n.pagesCountShort(chapter.pages.length),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasMultipleChapters)
                    IconButton(
                      tooltip: l10n.nextChapter,
                      onPressed: _currentIndex < widget.libraryItems.length - 1
                          ? () => _goToAdjacentChapter(1)
                          : null,
                      icon: const Icon(Icons.navigate_next_rounded),
                    ),
                ],
              ),
            ),
      body: _buildBody(chapter, l10n),
    );
  }

  Widget _buildBody(ManhwaChapter? chapter, AppLocalizations l10n) {
    if (_isLoading) {
      return _ManhwaReaderLoading(
        title: _loadingChapterTitle.trim().isEmpty
            ? (_isRussian(l10n)
                  ? '\u0417\u0430\u0433\u0440\u0443\u0437\u043a\u0430 \u0433\u043b\u0430\u0432\u044b'
                  : 'Loading chapter')
            : _loadingChapterTitle.trim(),
        subtitle: _isRussian(l10n)
            ? '\u0418\u0437\u043e\u0431\u0440\u0430\u0436\u0435\u043d\u0438\u044f \u0433\u043e\u0442\u043e\u0432\u044f\u0442\u0441\u044f \u043f\u0435\u0440\u0435\u0434 \u043e\u0442\u043a\u0440\u044b\u0442\u0438\u0435\u043c'
            : 'Images are being prepared before opening',
        completed: _imageLoadCompleted,
        total: _imageLoadTotal,
        reloadAttempts: _imageReloadAttempts,
      );
    }
    if (_errorMessage != null) {
      return _ManhwaReaderError(
        message: _errorMessage!,
        retryLabel: l10n.tryAgain,
        onRetry: () => unawaited(_loadChapter(_currentIndex)),
      );
    }
    if (chapter == null) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (_readingMode == _ArchiveReadingMode.horizontal) {
          return _buildHorizontalBody(chapter);
        }

        final contentWidth = constraints.maxWidth < _maxContentWidth
            ? constraints.maxWidth
            : _maxContentWidth;

        return ColoredBox(
          color: const Color(0xFF050608),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTapDown: _handleDoubleTapDown,
            onDoubleTap: _handleDoubleTap,
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale: 1,
              maxScale: 5,
              constrained: false,
              clipBehavior: Clip.hardEdge,
              boundaryMargin: EdgeInsets.zero,
              child: SizedBox(
                width: contentWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (
                      var index = 0;
                      index < chapter.pages.length;
                      index++
                    ) ...[
                      _ManhwaPageView(page: chapter.pages[index]),
                      if (index < chapter.pages.length - 1)
                        const SizedBox(height: 0),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHorizontalBody(ManhwaChapter chapter) {
    return ColoredBox(
      color: const Color(0xFF050608),
      child: PageView.builder(
        controller: _pageController,
        itemCount: chapter.pages.length,
        onPageChanged: (index) {
          setState(() {
            _currentPageIndex = index;
          });
        },
        itemBuilder: (context, index) {
          return _HorizontalManhwaPageView(
            key: ValueKey(chapter.pages[index].path),
            page: chapter.pages[index],
            maxContentWidth: _maxContentWidth,
            doubleTapScale: _doubleTapScale,
          );
        },
      ),
    );
  }

  Drawer _buildChapterDrawer(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Drawer(
      child: ListView.builder(
        itemCount: widget.libraryItems.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return DrawerHeader(
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  l10n.manhwaChaptersTitle,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }

          final itemIndex = index - 1;
          final item = widget.libraryItems[itemIndex];
          return ListTile(
            selected: itemIndex == _currentIndex,
            title: Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _openChapter(itemIndex),
          );
        },
      ),
    );
  }
}

class _ManhwaPageView extends StatelessWidget {
  const _ManhwaPageView({required this.page});

  final ManhwaPage page;

  @override
  Widget build(BuildContext context) {
    if (page.isSvg) {
      final imageUrl = page.imageUrl;
      if (imageUrl != null) {
        return SvgPicture.network(
          imageUrl,
          width: double.infinity,
          fit: BoxFit.fitWidth,
        );
      }

      return SvgPicture.memory(
        page.bytes ?? Uint8List(0),
        width: double.infinity,
        fit: BoxFit.fitWidth,
      );
    }

    final imageUrl = page.imageUrl;
    if (imageUrl != null) {
      return Image.network(
        imageUrl,
        width: double.infinity,
        fit: BoxFit.fitWidth,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );
    }

    return Image.memory(
      page.bytes ?? Uint8List(0),
      width: double.infinity,
      fit: BoxFit.fitWidth,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
    );
  }
}

class _HorizontalManhwaPageView extends StatefulWidget {
  const _HorizontalManhwaPageView({
    super.key,
    required this.page,
    required this.maxContentWidth,
    required this.doubleTapScale,
  });

  final ManhwaPage page;
  final double maxContentWidth;
  final double doubleTapScale;

  @override
  State<_HorizontalManhwaPageView> createState() =>
      _HorizontalManhwaPageViewState();
}

class _HorizontalManhwaPageViewState extends State<_HorizontalManhwaPageView> {
  final TransformationController _controller = TransformationController();
  TapDownDetails? _doubleTapDetails;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _handleDoubleTap() {
    final currentScale = _controller.value.getMaxScaleOnAxis();
    final tapPosition = _doubleTapDetails?.localPosition ?? Offset.zero;
    if (currentScale > 1.05) {
      _controller.value = _zoomMatrixForTap(
        controller: _controller,
        localPosition: tapPosition,
        scale: 1,
      );
      return;
    }

    _controller.value = _zoomMatrixForTap(
      controller: _controller,
      localPosition: tapPosition,
      scale: widget.doubleTapScale,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = constraints.maxWidth < widget.maxContentWidth
            ? constraints.maxWidth
            : widget.maxContentWidth;

        return ColoredBox(
          color: const Color(0xFF050608),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTapDown: _handleDoubleTapDown,
            onDoubleTap: _handleDoubleTap,
            child: InteractiveViewer(
              transformationController: _controller,
              minScale: 1,
              maxScale: 5,
              constrained: false,
              clipBehavior: Clip.hardEdge,
              boundaryMargin: EdgeInsets.zero,
              child: SizedBox(
                width: contentWidth,
                child: _ManhwaPageView(page: widget.page),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ManhwaReaderLoading extends StatefulWidget {
  const _ManhwaReaderLoading({
    required this.title,
    required this.subtitle,
    required this.completed,
    required this.total,
    required this.reloadAttempts,
  });

  final String title;
  final String subtitle;
  final int completed;
  final int total;
  final int reloadAttempts;

  @override
  State<_ManhwaReaderLoading> createState() => _ManhwaReaderLoadingState();
}

class _ManhwaReaderLoadingState extends State<_ManhwaReaderLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.total > 0
        ? (widget.completed / widget.total).clamp(0.0, 1.0).toDouble()
        : null;
    final percent = progress == null ? 0 : (progress * 100).round();
    final progressLabel = widget.total > 0
        ? '${widget.completed} / ${widget.total}'
        : '';
    final retryLabel = widget.reloadAttempts > 0
        ? '\n${widget.reloadAttempts} retry'
        : '';

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF071016), Color(0xFF0A0B12), Color(0xFF111827)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final phase = _controller.value;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 168,
                      height: 168,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          for (var index = 0; index < 8; index++)
                            Transform.rotate(
                              angle: phase * math.pi * 2 + index * math.pi / 4,
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: Transform.translate(
                                  offset: Offset(
                                    0,
                                    math.sin(phase * math.pi * 2 + index) * 7,
                                  ),
                                  child: Container(
                                    width: 22,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: Color.lerp(
                                        const Color(0xFF80D8FF),
                                        const Color(0xFFFFD166),
                                        index / 7,
                                      )!.withValues(alpha: 0.22 + index * 0.06),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.18,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          SizedBox(
                            width: 112,
                            height: 112,
                            child: CircularProgressIndicator(
                              value: progress,
                              strokeWidth: 8,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.1,
                              ),
                              color: const Color(0xFF80D8FF),
                            ),
                          ),
                          Container(
                            width: 86,
                            height: 86,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.28),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Text(
                              progress == null ? '...' : '$percent%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            height: 1.08,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      progressLabel.isEmpty
                          ? widget.subtitle
                          : '${widget.subtitle}\n$progressLabel$retryLabel',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.74),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 22),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: Colors.white.withValues(alpha: 0.11),
                        color: const Color(0xFF80D8FF),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var index = 0; index < 5; index++)
                          Transform.translate(
                            offset: Offset(
                              0,
                              math.sin((phase + index * 0.12) * math.pi * 2) *
                                  5,
                            ),
                            child: Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.symmetric(horizontal: 5),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(
                                  alpha: 0.28 + index * 0.1,
                                ),
                                shape: BoxShape.circle,
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
    );
  }
}

class _ManhwaReaderError extends StatelessWidget {
  const _ManhwaReaderError({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

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
                  const Icon(Icons.error_outline_rounded, size: 36),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(retryLabel),
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
