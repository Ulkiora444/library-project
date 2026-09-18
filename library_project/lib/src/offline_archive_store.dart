import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'library_api.dart';
import 'manhwa_archive.dart';

class ArchiveDownloadProgress {
  const ArchiveDownloadProgress({
    required this.chapterTitle,
    required this.chapterIndex,
    required this.chapterTotal,
    required this.pageCompleted,
    required this.pageTotal,
    this.completedChapters = 0,
    this.overallPageCompleted,
    this.overallPageTotal,
    this.activeDownloads = 1,
  });

  final String chapterTitle;
  final int chapterIndex;
  final int chapterTotal;
  final int pageCompleted;
  final int pageTotal;
  final int completedChapters;
  final int? overallPageCompleted;
  final int? overallPageTotal;
  final int activeDownloads;

  double get fraction {
    final overallTotal = overallPageTotal;
    final overallCompleted = overallPageCompleted;
    if (overallTotal != null && overallTotal > 0 && overallCompleted != null) {
      return (overallCompleted / overallTotal).clamp(0, 1).toDouble();
    }

    if (chapterTotal <= 0) {
      return 0;
    }

    final completedBeforeChapter =
        chapterIndex.clamp(1, chapterTotal).toInt() - 1;
    final pageFraction = pageTotal <= 0 ? 0 : pageCompleted / pageTotal;
    return ((completedBeforeChapter + pageFraction) / chapterTotal)
        .clamp(0, 1)
        .toDouble();
  }
}

class ArchiveDownloadCancelToken {
  final Set<http.Client> _clients = <http.Client>{};

  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) {
      return;
    }

    _isCancelled = true;
    for (final client in _clients.toList()) {
      client.close();
    }
    _clients.clear();
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw const ArchiveDownloadCancelledException();
    }
  }

  void _registerClient(http.Client client) {
    if (_isCancelled) {
      client.close();
      throw const ArchiveDownloadCancelledException();
    }
    _clients.add(client);
  }

  void _unregisterClient(http.Client client) {
    _clients.remove(client);
  }
}

class ArchiveDownloadCancelledException implements Exception {
  const ArchiveDownloadCancelledException();

  @override
  String toString() => 'Download cancelled';
}

class OfflineArchiveSeries {
  const OfflineArchiveSeries({
    required this.seriesId,
    required this.title,
    required this.kind,
    required this.chapters,
    this.coverImageUrl = '',
  });

  final String seriesId;
  final String title;
  final RemoteArchiveKind kind;
  final List<ManhwaLibraryItem> chapters;
  final String coverImageUrl;
}

class OfflineArchiveStore {
  OfflineArchiveStore({LibraryApiClient? apiClient})
    : _apiClient = apiClient ?? LibraryApiClient.instance;

  static const String _indexKey = 'offline_archive_chapters_v1';
  static const String _downloadsFolder = 'archive_downloads';
  static Future<void> _indexMutation = Future<void>.value();

  final LibraryApiClient _apiClient;

  Future<Set<String>> downloadedChapterKeys({String? seriesId}) async {
    final index = await _loadIndex();
    var changed = false;
    final result = <String>{};

    for (final entry in index.entries.toList()) {
      final record = entry.value;
      if (seriesId != null && record.seriesId != seriesId) {
        continue;
      }

      if (!await File(record.filePath).exists()) {
        index.remove(entry.key);
        changed = true;
        continue;
      }

      result
        ..add(record.sourcePath)
        ..add(record.filePath);
    }

    if (changed) {
      await _saveIndex(index);
    }

    return result;
  }

  Future<List<OfflineArchiveSeries>> loadDownloadedSeries(
    RemoteArchiveKind kind,
  ) async {
    final index = await _loadIndex();
    final grouped = <String, List<_OfflineArchiveRecord>>{};
    var changed = false;

    for (final entry in index.entries.toList()) {
      final record = entry.value;
      if (record.kind != kind) {
        continue;
      }
      if (!await File(record.filePath).exists()) {
        index.remove(entry.key);
        changed = true;
        continue;
      }

      grouped
          .putIfAbsent(record.seriesId, () => <_OfflineArchiveRecord>[])
          .add(record);
    }

    if (changed) {
      await _saveIndex(index);
    }

    final result = <OfflineArchiveSeries>[];
    for (final entry in grouped.entries) {
      final records = entry.value
        ..sort((a, b) {
          final indexCompare = a.chapterIndex.compareTo(b.chapterIndex);
          if (indexCompare != 0) {
            return indexCompare;
          }
          return naturalCompare(a.title, b.title);
        });

      if (records.isEmpty) {
        continue;
      }

      result.add(
        OfflineArchiveSeries(
          seriesId: entry.key,
          title: records.first.seriesTitle,
          kind: records.first.kind,
          coverImageUrl: records
              .map((record) => record.coverImageUrl)
              .firstWhere((value) => value.isNotEmpty, orElse: () => ''),
          chapters: [
            for (final record in records)
              ManhwaLibraryItem.file(
                sourcePath: record.filePath,
                title: record.title,
              ),
          ],
        ),
      );
    }

    result.sort((a, b) => naturalCompare(a.title, b.title));
    return result;
  }

  Future<ManhwaLibraryItem> itemForReading(ManhwaLibraryItem item) async {
    final record = await _recordForItem(item);
    if (record == null || !await File(record.filePath).exists()) {
      return item;
    }

    return ManhwaLibraryItem.file(
      sourcePath: record.filePath,
      title: record.title,
    );
  }

  Future<List<ManhwaLibraryItem>> itemsForReading(
    List<ManhwaLibraryItem> items,
  ) async {
    final result = <ManhwaLibraryItem>[];
    for (final item in items) {
      result.add(await itemForReading(item));
    }
    return result;
  }

  Future<ManhwaLibraryItem> downloadChapter({
    required String seriesId,
    required String seriesTitle,
    required RemoteArchiveKind kind,
    required ManhwaLibraryItem chapter,
    required int chapterIndex,
    required int chapterTotal,
    String coverImageUrl = '',
    ValueChanged<ArchiveDownloadProgress>? onProgress,
    ArchiveDownloadCancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final existing = await _recordForItem(chapter);
    if (existing != null && await File(existing.filePath).exists()) {
      return ManhwaLibraryItem.file(
        sourcePath: existing.filePath,
        title: existing.title,
      );
    }

    if (!chapter.isNetwork || chapter.networkPages.isEmpty) {
      throw StateError('Chapter does not contain remote pages');
    }

    final root = await _rootDirectory();
    final seriesDirectory = Directory(
      path.join(root.path, _safeFileSegment(seriesId)),
    );
    await seriesDirectory.create(recursive: true);

    final chapterFile = File(
      path.join(
        seriesDirectory.path,
        '${(chapterIndex + 1).toString().padLeft(4, '0')}_${_safeFileSegment(chapter.sourcePath)}.cbz',
      ),
    );
    final temporaryFile = File('${chapterFile.path}.tmp');
    if (await temporaryFile.exists()) {
      await temporaryFile.delete();
    }

    try {
      final archive = Archive();
      for (
        var pageIndex = 0;
        pageIndex < chapter.networkPages.length;
        pageIndex++
      ) {
        cancelToken?.throwIfCancelled();
        final page = chapter.networkPages[pageIndex];
        onProgress?.call(
          ArchiveDownloadProgress(
            chapterTitle: chapter.title,
            chapterIndex: chapterIndex + 1,
            chapterTotal: chapterTotal,
            pageCompleted: pageIndex,
            pageTotal: chapter.networkPages.length,
          ),
        );

        final bytes = await _bytesForPage(page, cancelToken);
        cancelToken?.throwIfCancelled();
        final extension = _extensionForPage(page);
        final entryName =
            'page_${(pageIndex + 1).toString().padLeft(4, '0')}$extension';
        archive.addFile(ArchiveFile.noCompress(entryName, bytes.length, bytes));

        onProgress?.call(
          ArchiveDownloadProgress(
            chapterTitle: chapter.title,
            chapterIndex: chapterIndex + 1,
            chapterTotal: chapterTotal,
            pageCompleted: pageIndex + 1,
            pageTotal: chapter.networkPages.length,
          ),
        );
      }

      cancelToken?.throwIfCancelled();
      final encoded = Uint8List.fromList(ZipEncoder().encode(archive));
      await temporaryFile.writeAsBytes(encoded, flush: true);
      cancelToken?.throwIfCancelled();
      if (await chapterFile.exists()) {
        await chapterFile.delete();
      }
      await temporaryFile.rename(chapterFile.path);

      await _withIndexLock(() async {
        final index = await _loadIndex();
        index[chapter.sourcePath] = _OfflineArchiveRecord(
          sourcePath: chapter.sourcePath,
          seriesId: seriesId,
          seriesTitle: seriesTitle,
          kind: kind,
          title: chapter.title,
          chapterIndex: chapterIndex,
          filePath: chapterFile.path,
          pageCount: chapter.networkPages.length,
          coverImageUrl: coverImageUrl,
          savedAt: DateTime.now(),
        );
        await _saveIndex(index);
      });
    } catch (_) {
      if (await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
      rethrow;
    }

    return ManhwaLibraryItem.file(
      sourcePath: chapterFile.path,
      title: chapter.title,
    );
  }

  Future<void> downloadSeries({
    required String seriesId,
    required String seriesTitle,
    required RemoteArchiveKind kind,
    required List<ManhwaLibraryItem> chapters,
    String coverImageUrl = '',
    ValueChanged<ArchiveDownloadProgress>? onProgress,
    ArchiveDownloadCancelToken? cancelToken,
    int parallelDownloads = 3,
  }) async {
    cancelToken?.throwIfCancelled();
    final downloaded = await downloadedChapterKeys(seriesId: seriesId);
    final tasks = <_ArchiveChapterDownloadTask>[];
    for (var index = 0; index < chapters.length; index++) {
      final chapter = chapters[index];
      if (!chapter.isNetwork) {
        continue;
      }
      if (downloaded.contains(chapter.sourcePath)) {
        continue;
      }
      tasks.add(_ArchiveChapterDownloadTask(index: index, chapter: chapter));
    }

    if (tasks.isEmpty) {
      return;
    }

    final workerCount = parallelDownloads.clamp(1, tasks.length).toInt();
    final overallPageTotal = tasks.fold<int>(
      0,
      (total, task) => total + task.chapter.networkPages.length,
    );
    var nextTaskIndex = 0;
    var completedChapters = 0;
    var completedPages = 0;
    var activeDownloads = 0;
    final partialPages = <String, int>{};

    void emitProgress(
      _ArchiveChapterDownloadTask task,
      ArchiveDownloadProgress progress,
    ) {
      partialPages[task.chapter.sourcePath] = progress.pageCompleted;
      final overallCompleted =
          completedPages +
          partialPages.values.fold<int>(0, (total, value) => total + value);
      onProgress?.call(
        ArchiveDownloadProgress(
          chapterTitle: task.chapter.title,
          chapterIndex: task.index + 1,
          chapterTotal: chapters.length,
          pageCompleted: progress.pageCompleted,
          pageTotal: task.chapter.networkPages.length,
          completedChapters: completedChapters,
          overallPageCompleted: overallCompleted,
          overallPageTotal: overallPageTotal,
          activeDownloads: activeDownloads,
        ),
      );
    }

    Future<void> worker() async {
      while (true) {
        cancelToken?.throwIfCancelled();
        final taskIndex = nextTaskIndex++;
        if (taskIndex >= tasks.length) {
          return;
        }

        final task = tasks[taskIndex];
        activeDownloads++;
        partialPages[task.chapter.sourcePath] = 0;
        emitProgress(
          task,
          ArchiveDownloadProgress(
            chapterTitle: task.chapter.title,
            chapterIndex: task.index + 1,
            chapterTotal: chapters.length,
            pageCompleted: 0,
            pageTotal: task.chapter.networkPages.length,
          ),
        );

        var downloaded = false;
        try {
          await downloadChapter(
            seriesId: seriesId,
            seriesTitle: seriesTitle,
            kind: kind,
            chapter: task.chapter,
            chapterIndex: task.index,
            chapterTotal: chapters.length,
            coverImageUrl: coverImageUrl,
            cancelToken: cancelToken,
            onProgress: (progress) => emitProgress(task, progress),
          );
          downloaded = true;
          completedChapters++;
          completedPages += task.chapter.networkPages.length;
        } catch (_) {
          cancelToken?.cancel();
          rethrow;
        } finally {
          activeDownloads--;
          partialPages.remove(task.chapter.sourcePath);
          if (downloaded && cancelToken?.isCancelled != true) {
            onProgress?.call(
              ArchiveDownloadProgress(
                chapterTitle: task.chapter.title,
                chapterIndex: task.index + 1,
                chapterTotal: chapters.length,
                pageCompleted: task.chapter.networkPages.length,
                pageTotal: task.chapter.networkPages.length,
                completedChapters: completedChapters,
                overallPageCompleted:
                    completedPages +
                    partialPages.values.fold<int>(
                      0,
                      (total, value) => total + value,
                    ),
                overallPageTotal: overallPageTotal,
                activeDownloads: activeDownloads,
              ),
            );
          }
        }
      }
    }

    await Future.wait([
      for (var index = 0; index < workerCount; index++) worker(),
    ]);
  }

  Future<T> _withIndexLock<T>(Future<T> Function() action) {
    final run = _indexMutation.then((_) => action());
    _indexMutation = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  Future<Uint8List> _downloadFileBytes(
    String fileNameOrUrl,
    ArchiveDownloadCancelToken? cancelToken,
  ) async {
    cancelToken?.throwIfCancelled();
    final client = http.Client();
    cancelToken?._registerClient(client);
    try {
      final response = await client
          .get(Uri.parse(_apiClient.fileUrl(fileNameOrUrl)))
          .timeout(const Duration(minutes: 2));
      cancelToken?.throwIfCancelled();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw LibraryApiException('Backend returned ${response.statusCode}');
      }
      return response.bodyBytes;
    } catch (_) {
      if (cancelToken?.isCancelled == true) {
        throw const ArchiveDownloadCancelledException();
      }
      rethrow;
    } finally {
      cancelToken?._unregisterClient(client);
      client.close();
    }
  }

  Future<Uint8List> _bytesForPage(
    ManhwaPage page,
    ArchiveDownloadCancelToken? cancelToken,
  ) async {
    cancelToken?.throwIfCancelled();
    final bytes = page.bytes;
    if (bytes != null) {
      return bytes;
    }

    final imageUrl = page.imageUrl;
    if (imageUrl == null || imageUrl.trim().isEmpty) {
      throw StateError('Page does not contain an image url');
    }

    return _downloadFileBytes(imageUrl, cancelToken);
  }

  Future<void> deleteChapter(String sourcePathOrFilePath) async {
    await _withIndexLock(() async {
      final index = await _loadIndex();
      final key = _keyForSourceOrFilePath(index, sourcePathOrFilePath);
      if (key == null) {
        return;
      }

      final record = index.remove(key);
      if (record != null) {
        final file = File(record.filePath);
        if (await file.exists()) {
          await file.delete();
        }
        await _deleteEmptyParentDirectory(file.parent);
      }

      await _saveIndex(index);
    });
  }

  Future<void> deleteSeries(String seriesId) async {
    await _withIndexLock(() async {
      final index = await _loadIndex();
      final records = index.entries
          .where((entry) => entry.value.seriesId == seriesId)
          .toList();

      for (final entry in records) {
        final file = File(entry.value.filePath);
        if (await file.exists()) {
          await file.delete();
        }
        await _deleteEmptyParentDirectory(file.parent);
        index.remove(entry.key);
      }

      await _saveIndex(index);
    });
  }

  Future<_OfflineArchiveRecord?> _recordForItem(ManhwaLibraryItem item) async {
    final index = await _loadIndex();
    final direct = index[item.sourcePath];
    if (direct != null) {
      return direct;
    }

    for (final record in index.values) {
      if (record.filePath == item.sourcePath) {
        return record;
      }
    }
    return null;
  }

  String? _keyForSourceOrFilePath(
    Map<String, _OfflineArchiveRecord> index,
    String sourcePathOrFilePath,
  ) {
    if (index.containsKey(sourcePathOrFilePath)) {
      return sourcePathOrFilePath;
    }

    for (final entry in index.entries) {
      if (entry.value.filePath == sourcePathOrFilePath ||
          entry.value.sourcePath == sourcePathOrFilePath) {
        return entry.key;
      }
    }
    return null;
  }

  String _extensionForPage(ManhwaPage page) {
    final source = (page.imageUrl?.trim().isNotEmpty ?? false)
        ? page.imageUrl!.trim()
        : page.path;
    final uri = Uri.tryParse(source);
    final sourcePath = uri?.path.isNotEmpty == true ? uri!.path : source;
    final extension = path.extension(sourcePath).toLowerCase();
    if (_supportedImageExtensions.contains(extension)) {
      return extension;
    }

    return switch (page.mimeType.toLowerCase()) {
      'image/jpeg' || 'image/jpg' => '.jpg',
      'image/png' => '.png',
      'image/webp' => '.webp',
      'image/gif' => '.gif',
      'image/bmp' => '.bmp',
      'image/svg+xml' => '.svg',
      _ => '.jpg',
    };
  }

  static const Set<String> _supportedImageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.svg',
  };

  Future<Directory> _rootDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final directory = Directory(path.join(base.path, _downloadsFolder));
    await directory.create(recursive: true);
    return directory;
  }

  String _safeFileSegment(String value) {
    final encoded = base64Url.encode(utf8.encode(value)).replaceAll('=', '');
    if (encoded.length <= 120) {
      return encoded;
    }
    return encoded.substring(0, 120);
  }

  Future<void> _deleteEmptyParentDirectory(Directory directory) async {
    if (!await directory.exists()) {
      return;
    }

    if (await directory.list().isEmpty) {
      await directory.delete();
    }
  }

  Future<Map<String, _OfflineArchiveRecord>> _loadIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_indexKey);
    if (raw == null || raw.trim().isEmpty) {
      return <String, _OfflineArchiveRecord>{};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <String, _OfflineArchiveRecord>{};
      }

      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is Map)
            entry.key as String: _OfflineArchiveRecord.fromJson(
              (entry.value as Map).cast<String, Object?>(),
            ),
      };
    } catch (_) {
      return <String, _OfflineArchiveRecord>{};
    }
  }

  Future<void> _saveIndex(Map<String, _OfflineArchiveRecord> index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _indexKey,
      jsonEncode({
        for (final entry in index.entries) entry.key: entry.value.toJson(),
      }),
    );
  }
}

class _ArchiveChapterDownloadTask {
  const _ArchiveChapterDownloadTask({
    required this.index,
    required this.chapter,
  });

  final int index;
  final ManhwaLibraryItem chapter;
}

class _OfflineArchiveRecord {
  const _OfflineArchiveRecord({
    required this.sourcePath,
    required this.seriesId,
    required this.seriesTitle,
    required this.kind,
    required this.title,
    required this.chapterIndex,
    required this.filePath,
    required this.pageCount,
    required this.coverImageUrl,
    required this.savedAt,
  });

  final String sourcePath;
  final String seriesId;
  final String seriesTitle;
  final RemoteArchiveKind kind;
  final String title;
  final int chapterIndex;
  final String filePath;
  final int pageCount;
  final String coverImageUrl;
  final DateTime savedAt;

  factory _OfflineArchiveRecord.fromJson(Map<String, Object?> json) {
    return _OfflineArchiveRecord(
      sourcePath: _stringValue(json['sourcePath']),
      seriesId: _stringValue(json['seriesId']),
      seriesTitle: _stringValue(json['seriesTitle']),
      kind: _kindFromName(_stringValue(json['kind'])),
      title: _stringValue(json['title']),
      chapterIndex: _intValue(json['chapterIndex']),
      filePath: _stringValue(json['filePath']),
      pageCount: _intValue(json['pageCount']),
      coverImageUrl: _stringValue(json['coverImageUrl']),
      savedAt:
          DateTime.tryParse(_stringValue(json['savedAt'])) ?? DateTime.now(),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sourcePath': sourcePath,
      'seriesId': seriesId,
      'seriesTitle': seriesTitle,
      'kind': kind.name,
      'title': title,
      'chapterIndex': chapterIndex,
      'filePath': filePath,
      'pageCount': pageCount,
      'coverImageUrl': coverImageUrl,
      'savedAt': savedAt.toIso8601String(),
    };
  }

  static RemoteArchiveKind _kindFromName(String value) {
    for (final kind in RemoteArchiveKind.values) {
      if (kind.name == value) {
        return kind;
      }
    }
    return RemoteArchiveKind.manga;
  }

  static int _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  static String _stringValue(Object? value) => value?.toString().trim() ?? '';
}
