import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class PdfReaderPage extends StatefulWidget {
  const PdfReaderPage({super.key, required this.title, required this.pdfUrl});

  final String title;
  final String pdfUrl;

  @override
  State<PdfReaderPage> createState() => _PdfReaderPageState();
}

enum _PdfMenuAction { zoomOut, zoomIn, resetZoom, bookmarks }

enum _PdfScrollMode { vertical, horizontal }

class _PdfReaderPageState extends State<PdfReaderPage> {
  final GlobalKey<SfPdfViewerState> _viewerKey = GlobalKey<SfPdfViewerState>();
  final PdfViewerController _controller = PdfViewerController();
  final TextEditingController _searchController = TextEditingController();

  PdfTextSearchResult? _searchResult;
  int _currentPage = 1;
  int _pageCount = 0;
  double _zoomLevel = 1;
  bool _isSearchVisible = false;
  bool _isDocumentLoading = true;
  _PdfScrollMode _scrollMode = _PdfScrollMode.vertical;
  String? _errorMessage;

  @override
  void dispose() {
    _searchResult?.removeListener(_handleSearchResultChanged);
    _searchResult?.clear();
    _searchController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PdfReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pdfUrl != widget.pdfUrl) {
      setState(() {
        _currentPage = 1;
        _pageCount = 0;
        _isDocumentLoading = true;
        _errorMessage = null;
      });
    }
  }

  void _toggleSearch() {
    setState(() {
      _isSearchVisible = !_isSearchVisible;
    });
    if (!_isSearchVisible) {
      _clearSearch();
    }
  }

  void _runSearch() {
    final query = _searchController.text.trim();
    _searchResult?.removeListener(_handleSearchResultChanged);
    _searchResult?.clear();

    if (query.isEmpty) {
      setState(() {
        _searchResult = null;
      });
      return;
    }

    final result = _controller.searchText(query);
    result.addListener(_handleSearchResultChanged);
    setState(() {
      _searchResult = result;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _searchResult?.removeListener(_handleSearchResultChanged);
    _searchResult?.clear();
    setState(() {
      _searchResult = null;
    });
  }

  void _handleSearchResultChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _jumpToSearchResult({required bool next}) {
    final result = _searchResult;
    if (result == null || !result.hasResult) {
      return;
    }
    if (next) {
      result.nextInstance();
    } else {
      result.previousInstance();
    }
  }

  bool get _canGoToPreviousPage => _pageCount > 0 && _currentPage > 1;
  bool get _canGoToNextPage => _pageCount > 0 && _currentPage < _pageCount;

  void _jumpToPageSafely(int targetPage) {
    if (!mounted || _pageCount == 0) {
      return;
    }

    final safePage = targetPage.clamp(1, _pageCount).toInt();
    try {
      _controller.jumpToPage(safePage);
      setState(() {
        _currentPage = safePage;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_PdfReaderLabels(context).pageJumpFailed)),
      );
    }
  }

  void _goToPreviousPage() {
    if (_canGoToPreviousPage) {
      _jumpToPageSafely(_currentPage - 1);
    }
  }

  void _goToNextPage() {
    if (_canGoToNextPage) {
      _jumpToPageSafely(_currentPage + 1);
    }
  }

  void _previewPdfPage(double value) {
    if (_pageCount == 0) {
      return;
    }
    final page = value.round().clamp(1, _pageCount).toInt();
    if (page == _currentPage) {
      return;
    }
    _jumpToPageSafely(page);
  }

  void _commitPdfPage(double value) {
    _jumpToPageSafely(value.round());
  }

  void _handlePageSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -250) {
      _goToNextPage();
    } else if (velocity > 250) {
      _goToPreviousPage();
    }
  }

  void _toggleScrollMode() {
    final currentPage = _currentPage;
    setState(() {
      _scrollMode = _scrollMode == _PdfScrollMode.vertical
          ? _PdfScrollMode.horizontal
          : _PdfScrollMode.vertical;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageCount > 0) {
        _jumpToPageSafely(currentPage);
      }
    });
  }

  void _setZoom(double value) {
    final next = value.clamp(1.0, 3.0).toDouble();
    _controller.zoomLevel = next;
    setState(() {
      _zoomLevel = next;
    });
  }

  void _handleMenuAction(_PdfMenuAction action) {
    switch (action) {
      case _PdfMenuAction.zoomOut:
        _setZoom(_zoomLevel - 0.25);
      case _PdfMenuAction.zoomIn:
        _setZoom(_zoomLevel + 0.25);
      case _PdfMenuAction.resetZoom:
        _setZoom(1);
      case _PdfMenuAction.bookmarks:
        _viewerKey.currentState?.openBookmarkView();
    }
  }

  bool get _isLocalPdf {
    final value = widget.pdfUrl.trim().toLowerCase();
    return value.isNotEmpty &&
        !value.startsWith('http://') &&
        !value.startsWith('https://');
  }

  @override
  Widget build(BuildContext context) {
    final labels = _PdfReaderLabels(context);
    final isHorizontalMode = _scrollMode == _PdfScrollMode.horizontal;
    final pagesLabel = _pageCount > 0
        ? '$_currentPage / $_pageCount'
        : labels.pdf;
    final subtitleLabel = _pageCount > 0
        ? '$pagesLabel  |  ${(_zoomLevel * 100).round()}%'
        : pagesLabel;

    return Scaffold(
      appBar: _isDocumentLoading && _errorMessage == null
          ? null
          : AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitleLabel,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: labels.search,
                  onPressed: _toggleSearch,
                  icon: Icon(
                    _isSearchVisible
                        ? Icons.search_off_rounded
                        : Icons.search_rounded,
                  ),
                ),
                IconButton(
                  tooltip: isHorizontalMode
                      ? labels.switchToVerticalScroll
                      : labels.switchToHorizontalScroll,
                  onPressed: _toggleScrollMode,
                  icon: Icon(
                    isHorizontalMode
                        ? Icons.swap_vert_rounded
                        : Icons.swap_horiz_rounded,
                  ),
                ),
                PopupMenuButton<_PdfMenuAction>(
                  tooltip: labels.more,
                  onSelected: _handleMenuAction,
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _PdfMenuAction.zoomOut,
                      enabled: _zoomLevel > 1,
                      child: _PdfMenuItem(
                        icon: Icons.zoom_out_rounded,
                        label: labels.zoomOut,
                      ),
                    ),
                    PopupMenuItem(
                      value: _PdfMenuAction.zoomIn,
                      enabled: _zoomLevel < 3,
                      child: _PdfMenuItem(
                        icon: Icons.zoom_in_rounded,
                        label: labels.zoomIn,
                      ),
                    ),
                    PopupMenuItem(
                      value: _PdfMenuAction.resetZoom,
                      enabled: _zoomLevel != 1,
                      child: _PdfMenuItem(
                        icon: Icons.center_focus_strong_rounded,
                        label: labels.resetZoom,
                      ),
                    ),
                    PopupMenuItem(
                      value: _PdfMenuAction.bookmarks,
                      child: _PdfMenuItem(
                        icon: Icons.bookmarks_rounded,
                        label: labels.bookmarks,
                      ),
                    ),
                  ],
                ),
              ],
            ),
      body: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: isHorizontalMode ? _handlePageSwipe : null,
            child: _buildPdfViewer(isHorizontalMode),
          ),
          if (_isDocumentLoading && _errorMessage == null)
            Positioned.fill(
              child: _PdfReaderLoadingScene(
                title: labels.loadingTitle,
                subtitle: labels.loadingSubtitle,
                bookTitle: widget.title,
              ),
            ),
          if (_isSearchVisible)
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              child: _PdfSearchBar(
                controller: _searchController,
                result: _searchResult,
                labels: labels,
                onSubmit: _runSearch,
                onClear: _clearSearch,
                onPrevious: () => _jumpToSearchResult(next: false),
                onNext: () => _jumpToSearchResult(next: true),
              ),
            ),
          if (_pageCount > 0)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SafeArea(
                top: false,
                child: _PdfPageTurnBar(
                  currentPage: _currentPage,
                  pageCount: _pageCount,
                  labels: labels,
                  onPrevious: _canGoToPreviousPage ? _goToPreviousPage : null,
                  onNext: _canGoToNextPage ? _goToNextPage : null,
                  onSliderChanged: _previewPdfPage,
                  onSliderChangeEnd: _commitPdfPage,
                ),
              ),
            ),
          if (_errorMessage != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 30,
                        color: Colors.black.withValues(alpha: 0.14),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.picture_as_pdf_rounded, size: 46),
                        const SizedBox(height: 12),
                        Text(_errorMessage!, textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPdfViewer(bool isHorizontalMode) {
    final viewerKey = _viewerKey;
    final controller = _controller;
    final canShowScrollHead = !isHorizontalMode;
    final pageLayoutMode = isHorizontalMode
        ? PdfPageLayoutMode.single
        : PdfPageLayoutMode.continuous;
    final scrollDirection = isHorizontalMode
        ? PdfScrollDirection.horizontal
        : PdfScrollDirection.vertical;

    void onDocumentLoaded(PdfDocumentLoadedDetails details) {
      setState(() {
        _pageCount = details.document.pages.count;
        _currentPage = _controller.pageNumber;
        _isDocumentLoading = false;
        _errorMessage = null;
      });
    }

    void onPageChanged(PdfPageChangedDetails details) {
      setState(() {
        _currentPage = details.newPageNumber;
      });
    }

    void onZoomLevelChanged(PdfZoomDetails details) {
      setState(() {
        _zoomLevel = details.newZoomLevel;
      });
    }

    void onDocumentLoadFailed(PdfDocumentLoadFailedDetails details) {
      setState(() {
        _isDocumentLoading = false;
        _errorMessage = details.description;
      });
    }

    if (_isLocalPdf) {
      return SfPdfViewer.file(
        File(widget.pdfUrl),
        key: viewerKey,
        controller: controller,
        canShowScrollHead: canShowScrollHead,
        canShowScrollStatus: canShowScrollHead,
        canShowPaginationDialog: canShowScrollHead,
        pageLayoutMode: pageLayoutMode,
        scrollDirection: scrollDirection,
        currentSearchTextHighlightColor: const Color(0xFFFFC857),
        otherSearchTextHighlightColor: const Color(0x66FFD166),
        onDocumentLoaded: onDocumentLoaded,
        onPageChanged: onPageChanged,
        onZoomLevelChanged: onZoomLevelChanged,
        onDocumentLoadFailed: onDocumentLoadFailed,
      );
    }

    return SfPdfViewer.network(
      widget.pdfUrl,
      key: viewerKey,
      controller: controller,
      canShowScrollHead: canShowScrollHead,
      canShowScrollStatus: canShowScrollHead,
      canShowPaginationDialog: canShowScrollHead,
      pageLayoutMode: pageLayoutMode,
      scrollDirection: scrollDirection,
      currentSearchTextHighlightColor: const Color(0xFFFFC857),
      otherSearchTextHighlightColor: const Color(0x66FFD166),
      onDocumentLoaded: onDocumentLoaded,
      onPageChanged: onPageChanged,
      onZoomLevelChanged: onZoomLevelChanged,
      onDocumentLoadFailed: onDocumentLoadFailed,
    );
  }
}

class _PdfSearchBar extends StatelessWidget {
  const _PdfSearchBar({
    required this.controller,
    required this.result,
    required this.labels,
    required this.onSubmit,
    required this.onClear,
    required this.onPrevious,
    required this.onNext,
  });

  final TextEditingController controller;
  final PdfTextSearchResult? result;
  final _PdfReaderLabels labels;
  final VoidCallback onSubmit;
  final VoidCallback onClear;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final total = result?.totalInstanceCount ?? 0;
    final current = result?.currentInstanceIndex ?? 0;
    final searching = result != null && !result!.isSearchCompleted;
    final hasResult = result?.hasResult ?? false;
    final resultLabel = searching
        ? labels.searching
        : hasResult
        ? '$current / $total'
        : result == null
        ? ''
        : labels.noMatches;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.search_rounded),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: labels.searchInBook,
                  isDense: true,
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => onSubmit(),
              ),
            ),
            if (resultLabel.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(resultLabel, style: Theme.of(context).textTheme.labelMedium),
            ],
            IconButton(
              tooltip: labels.previousResult,
              onPressed: hasResult ? onPrevious : null,
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
            ),
            IconButton(
              tooltip: labels.nextResult,
              onPressed: hasResult ? onNext : null,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
            IconButton(
              tooltip: labels.clear,
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _PdfReaderLoadingScene extends StatefulWidget {
  const _PdfReaderLoadingScene({
    required this.title,
    required this.subtitle,
    required this.bookTitle,
  });

  final String title;
  final String subtitle;
  final String bookTitle;

  @override
  State<_PdfReaderLoadingScene> createState() => _PdfReaderLoadingSceneState();
}

class _PdfReaderLoadingSceneState extends State<_PdfReaderLoadingScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.surface,
            colorScheme.primary.withValues(alpha: 0.08),
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.88),
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
              builder: (context, child) {
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
                          for (var index = 0; index < 6; index++)
                            Transform.rotate(
                              angle:
                                  (phase * math.pi * 2) + (index * math.pi / 3),
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: Container(
                                  width: 18,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary.withValues(
                                      alpha: 0.16 + index * 0.05,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ),
                          SizedBox(
                            width: 112,
                            height: 112,
                            child: CircularProgressIndicator(
                              strokeWidth: 8,
                              color: colorScheme.primary,
                              backgroundColor: colorScheme.primary.withValues(
                                alpha: 0.12,
                              ),
                            ),
                          ),
                          Container(
                            width: 82,
                            height: 82,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: colorScheme.surface.withValues(
                                alpha: 0.92,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.picture_as_pdf_rounded,
                              size: 38,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.subtitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      widget.bookTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
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

class _PdfPageTurnBar extends StatefulWidget {
  const _PdfPageTurnBar({
    required this.currentPage,
    required this.pageCount,
    required this.labels,
    required this.onPrevious,
    required this.onNext,
    required this.onSliderChanged,
    required this.onSliderChangeEnd,
  });

  final int currentPage;
  final int pageCount;
  final _PdfReaderLabels labels;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<double> onSliderChanged;
  final ValueChanged<double> onSliderChangeEnd;

  @override
  State<_PdfPageTurnBar> createState() => _PdfPageTurnBarState();
}

class _PdfPageTurnBarState extends State<_PdfPageTurnBar> {
  double? _dragPageValue;

  void _handleDragStart(DragStartDetails details) {
    _dragPageValue = widget.currentPage.toDouble();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (widget.pageCount <= 1) {
      return;
    }

    const pixelsPerPage = 8.0;
    final nextValue =
        (_dragPageValue ?? widget.currentPage.toDouble()) +
        (details.delta.dx / pixelsPerPage);
    _dragPageValue = nextValue.clamp(1, widget.pageCount).toDouble();
    final targetPage = _dragPageValue!
        .round()
        .clamp(1, widget.pageCount)
        .toDouble();
    widget.onSliderChanged(targetPage);
  }

  void _handleDragEnd(DragEndDetails details) {
    widget.onSliderChangeEnd((_dragPageValue ?? widget.currentPage.toDouble()));
    _dragPageValue = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canScrub = widget.pageCount > 1;

    return Center(
      child: Material(
        color: theme.colorScheme.surface.withValues(alpha: 0.94),
        elevation: 10,
        shadowColor: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: widget.labels.previousPage,
                onPressed: widget.onPrevious,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: canScrub ? _handleDragStart : null,
                onHorizontalDragUpdate: canScrub ? _handleDragUpdate : null,
                onHorizontalDragEnd: canScrub ? _handleDragEnd : null,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 112),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '${widget.currentPage} / ${widget.pageCount}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: widget.labels.nextPage,
                onPressed: widget.onNext,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PdfMenuItem extends StatelessWidget {
  const _PdfMenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(children: [Icon(icon), const SizedBox(width: 12), Text(label)]);
  }
}

class _PdfReaderLabels {
  _PdfReaderLabels(BuildContext context)
    : _isRu = Localizations.localeOf(context).languageCode == 'ru';

  final bool _isRu;

  String get pdf => 'PDF';
  String get loadingTitle => _isRu
      ? '\u041e\u0442\u043a\u0440\u044b\u0432\u0430\u044e PDF'
      : 'Opening PDF';
  String get loadingSubtitle => _isRu
      ? '\u0417\u0430\u0433\u0440\u0443\u0436\u0430\u044e \u043a\u043d\u0438\u0433\u0443 \u0438 \u0433\u043e\u0442\u043e\u0432\u043b\u044e \u0441\u0442\u0440\u0430\u043d\u0438\u0446\u044b'
      : 'Loading the book and preparing pages';
  String get search => _isRu ? '\u041f\u043e\u0438\u0441\u043a' : 'Search';
  String get searchInBook => _isRu
      ? '\u041f\u043e\u0438\u0441\u043a \u043f\u043e \u043a\u043d\u0438\u0433\u0435'
      : 'Search in book';
  String get searching => _isRu ? '\u0418\u0449\u0443...' : 'Searching...';
  String get noMatches => _isRu
      ? '\u041d\u0435\u0442 \u0441\u043e\u0432\u043f\u0430\u0434\u0435\u043d\u0438\u0439'
      : 'No matches';
  String get previousResult => _isRu
      ? '\u041f\u0440\u0435\u0434\u044b\u0434\u0443\u0449\u0435\u0435'
      : 'Previous result';
  String get nextResult => _isRu
      ? '\u0421\u043b\u0435\u0434\u0443\u044e\u0449\u0435\u0435'
      : 'Next result';
  String get previousPage => _isRu
      ? '\u041f\u0440\u0435\u0434\u044b\u0434\u0443\u0449\u0430\u044f \u0441\u0442\u0440\u0430\u043d\u0438\u0446\u0430'
      : 'Previous page';
  String get nextPage => _isRu
      ? '\u0421\u043b\u0435\u0434\u0443\u044e\u0449\u0430\u044f \u0441\u0442\u0440\u0430\u043d\u0438\u0446\u0430'
      : 'Next page';
  String get switchToVerticalScroll => _isRu
      ? '\u041b\u0438\u0441\u0442\u0430\u0442\u044c \u0432\u043d\u0438\u0437'
      : 'Scroll down';
  String get switchToHorizontalScroll => _isRu
      ? '\u041b\u0438\u0441\u0442\u0430\u0442\u044c \u0432 \u0441\u0442\u043e\u0440\u043e\u043d\u0443'
      : 'Scroll sideways';
  String get clear =>
      _isRu ? '\u041e\u0447\u0438\u0441\u0442\u0438\u0442\u044c' : 'Clear';
  String get pageJumpFailed => _isRu
      ? '\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u043f\u0435\u0440\u0435\u0439\u0442\u0438 \u043a \u044d\u0442\u043e\u0439 \u0441\u0442\u0440\u0430\u043d\u0438\u0446\u0435'
      : 'Could not jump to this page';
  String get more => _isRu ? '\u0415\u0449\u0435' : 'More';
  String get zoomOut => _isRu
      ? '\u0423\u043c\u0435\u043d\u044c\u0448\u0438\u0442\u044c'
      : 'Zoom out';
  String get zoomIn => _isRu
      ? '\u0423\u0432\u0435\u043b\u0438\u0447\u0438\u0442\u044c'
      : 'Zoom in';
  String get resetZoom => _isRu
      ? '\u0421\u0431\u0440\u043e\u0441\u0438\u0442\u044c \u043c\u0430\u0441\u0448\u0442\u0430\u0431'
      : 'Reset zoom';
  String get bookmarks =>
      _isRu ? '\u0417\u0430\u043a\u043b\u0430\u0434\u043a\u0438' : 'Bookmarks';
}
