import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'app_localizations.dart';
import 'library_api.dart';
import 'manhwa_archive.dart';
import 'manhwa_reader_page.dart';
import 'offline_archive_store.dart';

enum ArchiveLibraryKind { manhwa, manga, epub, pdf }

class ArchiveLibraryPage extends StatefulWidget {
  const ArchiveLibraryPage.manhwa({super.key})
    : kind = ArchiveLibraryKind.manhwa;

  const ArchiveLibraryPage.manga({super.key}) : kind = ArchiveLibraryKind.manga;

  final ArchiveLibraryKind kind;

  @override
  State<ArchiveLibraryPage> createState() => _ArchiveLibraryPageState();
}

class _ArchiveLibraryPageState extends State<ArchiveLibraryPage> {
  List<_ArchiveSeriesItem> _series = const [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSeries());
  }

  String _screenTitle(AppLocalizations l10n) => switch (widget.kind) {
    ArchiveLibraryKind.manhwa => l10n.manhwaReader,
    ArchiveLibraryKind.manga => l10n.mangaReader,
    ArchiveLibraryKind.epub => l10n.epubReaderTitle,
    ArchiveLibraryKind.pdf => l10n.pdfReaderTitle,
  };

  String _emptyTitle(AppLocalizations l10n) => switch (widget.kind) {
    ArchiveLibraryKind.manhwa => l10n.manhwaNotFound,
    ArchiveLibraryKind.manga => l10n.mangaNotFound,
    ArchiveLibraryKind.epub => l10n.epubEmptyTitle,
    ArchiveLibraryKind.pdf => l10n.pdfEmptyTitle,
  };

  String _description(AppLocalizations l10n) => switch (widget.kind) {
    ArchiveLibraryKind.manhwa => l10n.manhwaLibraryDescription,
    ArchiveLibraryKind.manga => l10n.mangaLibraryDescription,
    ArchiveLibraryKind.epub => l10n.epubEmptyDescription,
    ArchiveLibraryKind.pdf => l10n.pdfEmptyDescription,
  };

  Future<void> _loadSeries() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final remoteSeries = await _loadRemoteSeries();
      final offlineSeries = await _loadOfflineSeries();
      if (!mounted) {
        return;
      }

      setState(() {
        _series = _mergeRemoteAndOfflineSeries(remoteSeries, offlineSeries);
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

  Future<List<_ArchiveSeriesItem>> _loadRemoteSeries() async {
    final kind = switch (widget.kind) {
      ArchiveLibraryKind.manhwa => RemoteArchiveKind.manhwa,
      ArchiveLibraryKind.manga => RemoteArchiveKind.manga,
      ArchiveLibraryKind.epub => RemoteArchiveKind.epub,
      ArchiveLibraryKind.pdf => RemoteArchiveKind.pdf,
    };

    try {
      final series = await LibraryApiClient.instance.loadArchiveSeries(kind);
      return [
        for (final item in series)
          _ArchiveSeriesItem(
            id: item.id,
            bookId: item.bookId,
            kind: item.kind,
            title: item.title,
            language: item.language,
            imageUrl: item.imageUrl,
            chapterCount: item.chapterCount,
            chapters: [
              for (final chapter in item.chapters)
                ManhwaLibraryItem.network(
                  sourcePath: chapter.sourcePath,
                  title: chapter.title,
                  networkPages: chapter.pages,
                ),
            ],
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<List<_ArchiveSeriesItem>> _loadOfflineSeries() async {
    final remoteKind = switch (widget.kind) {
      ArchiveLibraryKind.manhwa => RemoteArchiveKind.manhwa,
      ArchiveLibraryKind.manga => RemoteArchiveKind.manga,
      ArchiveLibraryKind.epub => RemoteArchiveKind.epub,
      ArchiveLibraryKind.pdf => RemoteArchiveKind.pdf,
    };

    final downloaded = await OfflineArchiveStore().loadDownloadedSeries(
      remoteKind,
    );
    return [
      for (final series in downloaded)
        _ArchiveSeriesItem(
          id: series.seriesId,
          bookId: _bookIdFromSeriesId(series.seriesId),
          kind: series.kind,
          title: series.title,
          language: '',
          imageUrl: series.coverImageUrl,
          chapterCount: series.chapters.length,
          chapters: series.chapters,
        ),
    ];
  }

  List<_ArchiveSeriesItem> _mergeRemoteAndOfflineSeries(
    List<_ArchiveSeriesItem> remoteSeries,
    List<_ArchiveSeriesItem> offlineSeries,
  ) {
    final result = [...remoteSeries];
    final remoteIds = remoteSeries.map((item) => item.id).toSet();
    for (final offline in offlineSeries) {
      if (!remoteIds.contains(offline.id)) {
        result.add(offline);
      }
    }
    result.sort((a, b) => naturalCompare(a.title, b.title));
    return result;
  }

  int _bookIdFromSeriesId(String seriesId) {
    final match = RegExp(r':(\d+)$').firstMatch(seriesId);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  Future<void> _pickLocalArchive() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip', 'cbz'],
      withData: false,
    );

    if (!mounted || result == null || result.files.single.path == null) {
      return;
    }

    final filePath = result.files.single.path!;
    final item = ManhwaLibraryItem.file(
      sourcePath: filePath,
      title: formatManhwaArchiveTitle(filePath),
    );

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ManhwaReaderPage(libraryItems: [item], initialIndex: 0),
      ),
    );
  }

  Future<void> _openSeries(_ArchiveSeriesItem series) async {
    var openedSeries = series;
    if (series.chapters.isEmpty && series.chapterCount > 0) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      try {
        final loaded = await LibraryApiClient.instance.loadSeriesChapters(
          RemoteArchiveSeries(
            id: series.id,
            bookId: series.bookId,
            kind: series.kind,
            title: series.title,
            description: '',
            language: series.language,
            imageUrl: series.imageUrl,
            authors: const [],
            categories: const [],
            releaseYear: null,
            recommendedAge: null,
            likesTotal: 0,
            dislikesTotal: 0,
            chapterCount: series.chapterCount,
            chapters: const [],
            epubFileUrl: '',
            pdfFileUrl: '',
          ),
        );
        openedSeries = series.copyWith(
          chapters: [
            for (final chapter in loaded.chapters)
              ManhwaLibraryItem.network(
                sourcePath: chapter.sourcePath,
                title: chapter.title,
                networkPages: chapter.pages,
              ),
          ],
          chapterCount: loaded.chapterCount,
        );

        if (!mounted) {
          return;
        }
        setState(() {
          _series = [
            for (final item in _series)
              if (item.id == openedSeries.id) openedSeries else item,
          ];
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
        return;
      }
    }

    if (openedSeries.chapters.isEmpty) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArchiveSeriesPage(
          seriesId: openedSeries.id,
          title: openedSeries.title,
          kind: openedSeries.kind,
          coverImageUrl: openedSeries.imageUrl,
          chapters: openedSeries.chapters,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = _screenTitle(l10n);
    final description = _description(l10n);
    final localOpenLabel = l10n.openZipCbz;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: localOpenLabel,
            onPressed: _pickLocalArchive,
            icon: const Icon(Icons.archive_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _ArchiveLibraryError(
              message: _errorMessage!,
              localOpenLabel: localOpenLabel,
              onRetry: () => unawaited(_loadSeries()),
              onOpenLocalArchive: _pickLocalArchive,
            )
          : _series.isEmpty
          ? _EmptyArchiveLibrary(
              title: _emptyTitle(l10n),
              description: description,
              localOpenLabel: localOpenLabel,
              onOpenLocalArchive: _pickLocalArchive,
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: _series.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              description,
                              style: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.copyWith(height: 1.45),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                final series = _series[index - 1];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    leading: const Icon(Icons.menu_book_rounded),
                    title: Text(
                      series.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      series.subtitle(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _openSeries(series),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickLocalArchive,
        icon: const Icon(Icons.folder_open_rounded),
        label: Text(localOpenLabel),
      ),
    );
  }
}

class ArchiveSeriesPage extends StatefulWidget {
  const ArchiveSeriesPage({
    super.key,
    required this.seriesId,
    required this.title,
    required this.kind,
    required this.coverImageUrl,
    required this.chapters,
  });

  final String seriesId;
  final String title;
  final RemoteArchiveKind kind;
  final String coverImageUrl;
  final List<ManhwaLibraryItem> chapters;

  @override
  State<ArchiveSeriesPage> createState() => _ArchiveSeriesPageState();
}

class _ArchiveSeriesPageState extends State<ArchiveSeriesPage> {
  final OfflineArchiveStore _offlineStore = OfflineArchiveStore();
  static final Map<String, List<int>> _downloadQueuesBySeries =
      <String, List<int>>{};
  static final Map<String, ArchiveDownloadCancelToken> _chapterDownloadTokens =
      <String, ArchiveDownloadCancelToken>{};
  static final Map<String, ArchiveDownloadProgress> _chapterDownloadProgress =
      <String, ArchiveDownloadProgress>{};
  static final Set<String> _runningQueueSeriesIds = <String>{};
  static final Set<String> _recentlyCompletedDownloads = <String>{};
  static final ValueNotifier<int> _downloadStateRevision = ValueNotifier<int>(
    0,
  );
  static const int _queueParallelLimit = 3;

  late List<ManhwaLibraryItem> _chapters;
  Set<String> _downloadedChapterKeys = const <String>{};
  String? _openingChapterKey;

  List<int> get _downloadQueue =>
      _downloadQueuesBySeries.putIfAbsent(widget.seriesId, () => <int>[]);

  @override
  void initState() {
    super.initState();
    _chapters = widget.chapters;
    _downloadStateRevision.addListener(_handleDownloadStateChanged);
    unawaited(_loadOfflineStatus());
  }

  @override
  void dispose() {
    _downloadStateRevision.removeListener(_handleDownloadStateChanged);
    super.dispose();
  }

  void _handleDownloadStateChanged() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  static void _notifyDownloadStateChanged() {
    _downloadStateRevision.value++;
  }

  @override
  void didUpdateWidget(covariant ArchiveSeriesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chapters != widget.chapters) {
      _chapters = widget.chapters;
      unawaited(_loadOfflineStatus());
    }
  }

  Future<void> _loadOfflineStatus() async {
    final keys = await _offlineStore.downloadedChapterKeys(
      seriesId: widget.seriesId,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _downloadedChapterKeys = keys;
    });
  }

  bool _isDownloaded(ManhwaLibraryItem chapter) {
    return _recentlyCompletedDownloads.contains(chapter.sourcePath) ||
        _downloadedChapterKeys.contains(chapter.sourcePath) ||
        !chapter.isNetwork;
  }

  bool get _canDownloadAll {
    for (var index = 0; index < _chapters.length; index++) {
      final chapter = _chapters[index];
      if (chapter.isNetwork &&
          !_isDownloaded(chapter) &&
          !_isChapterDownloading(chapter) &&
          !_isQueued(index)) {
        return true;
      }
    }
    return false;
  }

  bool get _canDeleteAny {
    return _chapters.any(_isDownloaded);
  }

  bool get _hasActiveDownloads => _chapters.any(_isChapterDownloading);
  bool get _hasQueuedDownloads => _downloadQueue.isNotEmpty;

  bool _isChapterDownloading(ManhwaLibraryItem chapter) {
    return _chapterDownloadTokens.containsKey(chapter.sourcePath);
  }

  void _cancelChapterDownload(String sourcePath) {
    _chapterDownloadTokens[sourcePath]?.cancel();
  }

  void _cancelAllDownloads() {
    _downloadQueue.clear();
    for (final token in _chapterDownloadTokens.values.toList()) {
      token.cancel();
    }
    _notifyDownloadStateChanged();
  }

  bool _isQueued(int index) {
    return _downloadQueue.contains(index);
  }

  void _queueChapterDownload(int index) {
    if (index < 0 || index >= _chapters.length) {
      return;
    }

    final chapter = _chapters[index];
    if (!chapter.isNetwork ||
        _isDownloaded(chapter) ||
        _isChapterDownloading(chapter) ||
        _isQueued(index)) {
      return;
    }

    _downloadQueue.add(index);
    _chapterDownloadProgress[chapter.sourcePath] = ArchiveDownloadProgress(
      chapterTitle: chapter.title,
      chapterIndex: index + 1,
      chapterTotal: _chapters.length,
      pageCompleted: 0,
      pageTotal: chapter.networkPages.length,
    );
    _notifyDownloadStateChanged();
    unawaited(_runDownloadQueue());
  }

  Future<void> _runDownloadQueue() async {
    if (_runningQueueSeriesIds.contains(widget.seriesId)) {
      return;
    }

    _runningQueueSeriesIds.add(widget.seriesId);
    try {
      while (_downloadQueue.isNotEmpty &&
          _chapterDownloadTokens.length < _queueParallelLimit) {
        final index = _downloadQueue.removeAt(0);
        _notifyDownloadStateChanged();
        unawaited(
          _downloadChapter(index, showSuccessSnack: false, fromQueue: true),
        );
      }
    } finally {
      _runningQueueSeriesIds.remove(widget.seriesId);
    }
  }

  Future<void> _openChapter(int index) async {
    if (index < 0 || index >= _chapters.length) {
      return;
    }

    final chapter = _chapters[index];
    setState(() {
      _openingChapterKey = chapter.sourcePath;
    });

    try {
      final readerItems = await _offlineStore.itemsForReading(_chapters);
      if (!mounted) {
        return;
      }

      setState(() {
        _openingChapterKey = null;
      });

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ManhwaReaderPage(libraryItems: readerItems, initialIndex: index),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _openingChapterKey = null;
      });
      _showSnack(
        '${_ArchiveOfflineCopy.openFailed(context)}: ${error.toString().replaceFirst('Exception: ', '')}',
      );
    }
  }

  Future<void> _downloadChapter(
    int index, {
    bool showSuccessSnack = true,
    bool fromQueue = false,
  }) async {
    if (index < 0 || index >= _chapters.length) {
      return;
    }

    final chapter = _chapters[index];
    if (!chapter.isNetwork ||
        _isDownloaded(chapter) ||
        _isChapterDownloading(chapter)) {
      return;
    }

    final cancelToken = ArchiveDownloadCancelToken();
    _downloadQueue.remove(index);
    _chapterDownloadTokens[chapter.sourcePath] = cancelToken;
    _chapterDownloadProgress[chapter.sourcePath] = ArchiveDownloadProgress(
      chapterTitle: chapter.title,
      chapterIndex: index + 1,
      chapterTotal: _chapters.length,
      pageCompleted: 0,
      pageTotal: chapter.networkPages.length,
    );
    _notifyDownloadStateChanged();

    try {
      await _offlineStore.downloadChapter(
        seriesId: widget.seriesId,
        seriesTitle: widget.title,
        kind: widget.kind,
        chapter: chapter,
        chapterIndex: index,
        chapterTotal: _chapters.length,
        coverImageUrl: widget.coverImageUrl,
        cancelToken: cancelToken,
        onProgress: (progress) {
          _chapterDownloadProgress[chapter.sourcePath] = progress;
          _notifyDownloadStateChanged();
        },
      );
      _recentlyCompletedDownloads.add(chapter.sourcePath);
      await _loadOfflineStatus();
      if (mounted && showSuccessSnack) {
        _showSnack(_ArchiveOfflineCopy.chapterDownloaded(context));
      }
    } on ArchiveDownloadCancelledException {
      await _loadOfflineStatus();
      if (mounted) {
        _showSnack(_ArchiveOfflineCopy.downloadCancelled(context));
      }
    } catch (error) {
      if (mounted) {
        _showSnack(error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (_chapterDownloadTokens[chapter.sourcePath] == cancelToken) {
        _chapterDownloadTokens.remove(chapter.sourcePath);
      }
      _chapterDownloadProgress.remove(chapter.sourcePath);
      _notifyDownloadStateChanged();
      if (fromQueue) {
        unawaited(_runDownloadQueue());
      }
    }
  }

  Future<void> _downloadAll() async {
    if (!_canDownloadAll) {
      return;
    }

    for (var index = 0; index < _chapters.length; index++) {
      final chapter = _chapters[index];
      if (chapter.isNetwork &&
          !_isDownloaded(chapter) &&
          !_isChapterDownloading(chapter)) {
        _queueChapterDownload(index);
      }
    }
  }

  Future<void> _deleteChapter(int index) async {
    if (index < 0 || index >= _chapters.length) {
      return;
    }

    final chapter = _chapters[index];
    await _offlineStore.deleteChapter(chapter.sourcePath);
    _recentlyCompletedDownloads.remove(chapter.sourcePath);
    if (!mounted) {
      return;
    }

    setState(() {
      if (!chapter.isNetwork) {
        _chapters = [
          for (var i = 0; i < _chapters.length; i++)
            if (i != index) _chapters[i],
        ];
      }
    });

    await _loadOfflineStatus();
    if (!mounted) {
      return;
    }

    _showSnack(_ArchiveOfflineCopy.chapterDeleted(context));
    if (_chapters.isEmpty) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _deleteAll() async {
    if (!_canDeleteAny) {
      return;
    }

    await _offlineStore.deleteSeries(widget.seriesId);
    if (!mounted) {
      return;
    }

    setState(() {
      _downloadedChapterKeys = const <String>{};
      for (final chapter in _chapters) {
        _recentlyCompletedDownloads.remove(chapter.sourcePath);
      }
      if (_chapters.every((chapter) => !chapter.isNetwork)) {
        _chapters = const <ManhwaLibraryItem>[];
      }
    });
    _showSnack(_ArchiveOfflineCopy.seriesDeleted(context));

    if (_chapters.isEmpty) {
      Navigator.of(context).maybePop();
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _chapterSubtitle(BuildContext context, ManhwaLibraryItem chapter) {
    if (_isDownloaded(chapter)) {
      return _ArchiveOfflineCopy.offlineReady(context);
    }
    if (chapter.isNetwork) {
      return _ArchiveOfflineCopy.pagesCount(
        context,
        chapter.networkPages.length,
      );
    }
    return _ArchiveOfflineCopy.localFile(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_hasActiveDownloads || _hasQueuedDownloads)
            IconButton(
              tooltip: _ArchiveOfflineCopy.cancelAllDownloads(context),
              onPressed: _cancelAllDownloads,
              icon: const Icon(Icons.cancel_rounded),
            )
          else if (_canDownloadAll)
            IconButton(
              tooltip: _ArchiveOfflineCopy.downloadAll(context),
              onPressed: () => unawaited(_downloadAll()),
              icon: const Icon(Icons.download_for_offline_rounded),
            ),
          if (_canDeleteAny)
            IconButton(
              tooltip: _ArchiveOfflineCopy.deleteDownloaded(context),
              onPressed: _hasActiveDownloads || _hasQueuedDownloads
                  ? null
                  : () => unawaited(_deleteAll()),
              icon: const Icon(Icons.delete_sweep_rounded),
            ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: _chapters.length,
        itemBuilder: (context, index) {
          final chapterIndex = index;
          final chapter = _chapters[chapterIndex];
          final downloaded = _isDownloaded(chapter);
          final downloadProgress = _chapterDownloadProgress[chapter.sourcePath];
          final isDownloading = _isChapterDownloading(chapter);
          final isQueued = _isQueued(chapterIndex);
          final isOpening = _openingChapterKey == chapter.sourcePath;

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: CircleAvatar(child: Text('${chapterIndex + 1}')),
              title: Text(
                chapter.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                isQueued
                    ? _ArchiveOfflineCopy.queued(context)
                    : isDownloading
                    ? _ArchiveOfflineCopy.chapterDownloadProgress(
                        context,
                        downloadProgress,
                      )
                    : _chapterSubtitle(context, chapter),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: SizedBox(
                width: 104,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isOpening)
                      const SizedBox(
                        width: 40,
                        height: 40,
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          ),
                        ),
                      )
                    else if (isDownloading)
                      _ChapterDownloadCancelButton(
                        progress: downloadProgress,
                        tooltip: _ArchiveOfflineCopy.cancelDownload(context),
                        onPressed: () =>
                            _cancelChapterDownload(chapter.sourcePath),
                      )
                    else if (isQueued)
                      _ChapterDownloadCancelButton(
                        progress: downloadProgress,
                        tooltip: _ArchiveOfflineCopy.cancelDownload(context),
                        onPressed: () {
                          _downloadQueue.remove(chapterIndex);
                          _chapterDownloadProgress.remove(chapter.sourcePath);
                          _notifyDownloadStateChanged();
                        },
                      )
                    else if (downloaded)
                      IconButton(
                        tooltip: _ArchiveOfflineCopy.deleteChapter(context),
                        onPressed: () =>
                            unawaited(_deleteChapter(chapterIndex)),
                        icon: const Icon(Icons.delete_outline_rounded),
                      )
                    else if (chapter.isNetwork)
                      IconButton(
                        tooltip: _ArchiveOfflineCopy.downloadChapter(context),
                        onPressed: () => _queueChapterDownload(chapterIndex),
                        icon: const Icon(Icons.download_rounded),
                      )
                    else
                      const SizedBox(width: 48),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
              onTap: isDownloading || isQueued
                  ? null
                  : () => unawaited(_openChapter(chapterIndex)),
            ),
          );
        },
      ),
    );
  }
}

class _ChapterDownloadCancelButton extends StatelessWidget {
  const _ChapterDownloadCancelButton({
    required this.progress,
    required this.tooltip,
    required this.onPressed,
  });

  final ArchiveDownloadProgress? progress;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final currentProgress = progress;
    final chapterProgress =
        currentProgress == null || currentProgress.pageTotal <= 0
        ? null
        : (currentProgress.pageCompleted / currentProgress.pageTotal)
              .clamp(0, 1)
              .toDouble();
    final remaining = currentProgress == null
        ? null
        : (currentProgress.pageTotal - currentProgress.pageCompleted)
              .clamp(0, currentProgress.pageTotal)
              .toInt();
    final label = remaining == null
        ? '...'
        : remaining > 99
        ? '99+'
        : '$remaining';
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: SizedBox(
        width: 36,
        height: 36,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                value: chapterProgress,
                strokeWidth: 3,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: remaining != null && remaining > 99 ? 8 : 10,
                height: 1,
              ),
            ),
            Positioned(
              right: -1,
              bottom: -1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded, size: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchiveOfflineCopy {
  static bool _isRu(BuildContext context) =>
      AppLocalizations.of(context).locale.languageCode == 'ru';

  static String downloadAll(BuildContext context) => _isRu(context)
      ? '\u0421\u043a\u0430\u0447\u0430\u0442\u044c \u0432\u0435\u0441\u044c \u0442\u0430\u0439\u0442\u043b'
      : 'Download full title';

  static String cancelAllDownloads(BuildContext context) => _isRu(context)
      ? '\u041e\u0442\u043c\u0435\u043d\u0438\u0442\u044c \u0432\u0441\u0435 \u0437\u0430\u0433\u0440\u0443\u0437\u043a\u0438'
      : 'Cancel all downloads';

  static String queued(BuildContext context) => _isRu(context)
      ? '\u0412 \u043e\u0447\u0435\u0440\u0435\u0434\u0438'
      : 'Queued';

  static String downloadChapter(BuildContext context) => _isRu(context)
      ? '\u0421\u043a\u0430\u0447\u0430\u0442\u044c \u0433\u043b\u0430\u0432\u0443'
      : 'Download chapter';

  static String deleteChapter(BuildContext context) => _isRu(context)
      ? '\u0423\u0434\u0430\u043b\u0438\u0442\u044c \u0441\u043a\u0430\u0447\u0430\u043d\u043d\u0443\u044e \u0433\u043b\u0430\u0432\u0443'
      : 'Delete downloaded chapter';

  static String deleteDownloaded(BuildContext context) => _isRu(context)
      ? '\u0423\u0434\u0430\u043b\u0438\u0442\u044c \u0441\u043a\u0430\u0447\u0430\u043d\u043d\u043e\u0435'
      : 'Delete downloads';

  static String offlineReady(BuildContext context) => _isRu(context)
      ? '\u0421\u043a\u0430\u0447\u0430\u043d\u043e \u0434\u043b\u044f \u043e\u0444\u043b\u0430\u0439\u043d\u0430'
      : 'Ready offline';

  static String localFile(BuildContext context) => _isRu(context)
      ? '\u041b\u043e\u043a\u0430\u043b\u044c\u043d\u044b\u0439 \u0444\u0430\u0439\u043b'
      : 'Local file';

  static String cancelDownload(BuildContext context) => _isRu(context)
      ? '\u041e\u0442\u043c\u0435\u043d\u0438\u0442\u044c'
      : 'Cancel';

  static String downloadCancelled(BuildContext context) => _isRu(context)
      ? '\u0421\u043a\u0430\u0447\u0438\u0432\u0430\u043d\u0438\u0435 \u043e\u0442\u043c\u0435\u043d\u0435\u043d\u043e'
      : 'Download cancelled';

  static String chapterDownloaded(BuildContext context) => _isRu(context)
      ? '\u0413\u043b\u0430\u0432\u0430 \u0441\u043a\u0430\u0447\u0430\u043d\u0430'
      : 'Chapter downloaded';

  static String chapterDeleted(BuildContext context) => _isRu(context)
      ? '\u0413\u043b\u0430\u0432\u0430 \u0443\u0434\u0430\u043b\u0435\u043d\u0430'
      : 'Chapter deleted';

  static String seriesDeleted(BuildContext context) => _isRu(context)
      ? '\u0421\u043a\u0430\u0447\u0430\u043d\u043d\u043e\u0435 \u0443\u0434\u0430\u043b\u0435\u043d\u043e'
      : 'Downloads deleted';

  static String openFailed(BuildContext context) => _isRu(context)
      ? '\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u043e\u0442\u043a\u0440\u044b\u0442\u044c \u0433\u043b\u0430\u0432\u0443'
      : 'Could not open chapter';

  static String pagesCount(BuildContext context, int count) =>
      _isRu(context) ? '$count \u0441\u0442\u0440.' : '$count pages';

  static String chapterDownloadProgress(
    BuildContext context,
    ArchiveDownloadProgress? progress,
  ) {
    if (progress == null) {
      return _isRu(context)
          ? '\u0421\u043a\u0430\u0447\u0438\u0432\u0430\u043d\u0438\u0435...'
          : 'Downloading...';
    }

    return _isRu(context)
        ? '\u0421\u043a\u0430\u0447\u0438\u0432\u0430\u043d\u0438\u0435: ${progress.pageCompleted} / ${progress.pageTotal} \u0441\u0442\u0440.'
        : 'Downloading: ${progress.pageCompleted} / ${progress.pageTotal} pages';
  }
}

class _EmptyArchiveLibrary extends StatelessWidget {
  const _EmptyArchiveLibrary({
    required this.title,
    required this.description,
    required this.localOpenLabel,
    required this.onOpenLocalArchive,
  });

  final String title;
  final String description;
  final String localOpenLabel;
  final VoidCallback onOpenLocalArchive;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.photo_library_outlined, size: 36),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    description,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: onOpenLocalArchive,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: Text(localOpenLabel),
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

class _ArchiveLibraryError extends StatelessWidget {
  const _ArchiveLibraryError({
    required this.message,
    required this.localOpenLabel,
    required this.onRetry,
    required this.onOpenLocalArchive,
  });

  final String message;
  final String localOpenLabel;
  final VoidCallback onRetry;
  final VoidCallback onOpenLocalArchive;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
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
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(l10n.retry),
                      ),
                      OutlinedButton.icon(
                        onPressed: onOpenLocalArchive,
                        icon: const Icon(Icons.folder_open_rounded),
                        label: Text(localOpenLabel),
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

class _ArchiveSeriesItem {
  const _ArchiveSeriesItem({
    required this.id,
    required this.bookId,
    required this.kind,
    required this.title,
    required this.language,
    required this.imageUrl,
    required this.chapterCount,
    required this.chapters,
  });

  final String id;
  final int bookId;
  final RemoteArchiveKind kind;
  final String title;
  final String language;
  final String imageUrl;
  final int chapterCount;
  final List<ManhwaLibraryItem> chapters;

  int get displayChapterCount =>
      chapters.isNotEmpty ? chapters.length : chapterCount;

  String subtitle(BuildContext context) {
    final count = AppLocalizations.of(
      context,
    ).chaptersCount(displayChapterCount);
    final value = language.trim();
    return value.isEmpty ? count : '$count · $value';
  }

  _ArchiveSeriesItem copyWith({
    int? chapterCount,
    List<ManhwaLibraryItem>? chapters,
  }) {
    return _ArchiveSeriesItem(
      id: id,
      bookId: bookId,
      kind: kind,
      title: title,
      language: language,
      imageUrl: imageUrl,
      chapterCount: chapterCount ?? this.chapterCount,
      chapters: chapters ?? this.chapters,
    );
  }
}
