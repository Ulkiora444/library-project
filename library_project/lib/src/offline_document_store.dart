import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'library_api.dart';

class OfflineDocument {
  const OfflineDocument({
    required this.id,
    required this.title,
    required this.kind,
    required this.localPath,
    required this.sourceUrl,
    required this.savedAt,
    this.coverImageUrl = '',
    this.author = '',
  });

  final String id;
  final String title;
  final RemoteArchiveKind kind;
  final String localPath;
  final String sourceUrl;
  final DateTime savedAt;
  final String coverImageUrl;
  final String author;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'kind': kind.name,
    'localPath': localPath,
    'sourceUrl': sourceUrl,
    'savedAt': savedAt.toIso8601String(),
    'coverImageUrl': coverImageUrl,
    'author': author,
  };

  static OfflineDocument fromJson(Map<String, Object?> json) {
    final kindName = '${json['kind'] ?? ''}';
    return OfflineDocument(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      kind: RemoteArchiveKind.values.firstWhere(
        (item) => item.name == kindName,
        orElse: () => RemoteArchiveKind.epub,
      ),
      localPath: '${json['localPath'] ?? ''}',
      sourceUrl: '${json['sourceUrl'] ?? ''}',
      savedAt: DateTime.tryParse('${json['savedAt'] ?? ''}') ?? DateTime.now(),
      coverImageUrl: '${json['coverImageUrl'] ?? ''}',
      author: '${json['author'] ?? ''}',
    );
  }
}

class OfflineDocumentStore {
  OfflineDocumentStore({LibraryApiClient? apiClient})
    : _apiClient = apiClient ?? LibraryApiClient.instance;

  static const String _indexKey = 'offline_documents_v1';
  static const String _documentsFolder = 'offline_documents';

  final LibraryApiClient _apiClient;

  Future<List<OfflineDocument>> loadDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_indexKey);
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const [];
    }

    final documents = <OfflineDocument>[];
    for (final item in decoded) {
      if (item is Map) {
        final document = OfflineDocument.fromJson(item.cast<String, Object?>());
        if (document.localPath.trim().isNotEmpty &&
            await File(document.localPath).exists()) {
          documents.add(document);
        }
      }
    }
    documents.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return documents;
  }

  Future<bool> isDownloaded(String id) async {
    final documents = await loadDocuments();
    return documents.any((item) => item.id == id);
  }

  Future<OfflineDocument?> documentById(String id) async {
    final documents = await loadDocuments();
    for (final item in documents) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  Future<OfflineDocument> downloadDocument({
    required String id,
    required String title,
    required RemoteArchiveKind kind,
    required String sourceUrl,
    required String fileName,
    String coverImageUrl = '',
    String author = '',
  }) async {
    final bytes = await _apiClient.downloadFileBytes(sourceUrl);
    final directory = await _documentsDirectory();
    final extension = kind == RemoteArchiveKind.pdf ? '.pdf' : '.epub';
    final safeName = _safeFileName(fileName, extension);
    final file = File(path.join(directory.path, safeName));
    await file.writeAsBytes(bytes, flush: true);

    final document = OfflineDocument(
      id: id,
      title: title,
      kind: kind,
      localPath: file.path,
      sourceUrl: sourceUrl,
      savedAt: DateTime.now(),
      coverImageUrl: coverImageUrl,
      author: author,
    );

    final documents = await loadDocuments();
    final next = [
      document,
      for (final item in documents)
        if (item.id != id) item,
    ];
    await _saveDocuments(next);
    return document;
  }

  Future<void> deleteDocument(String id) async {
    final documents = await loadDocuments();
    final next = <OfflineDocument>[];
    for (final item in documents) {
      if (item.id == id) {
        final file = File(item.localPath);
        if (await file.exists()) {
          await file.delete();
        }
      } else {
        next.add(item);
      }
    }
    await _saveDocuments(next);
  }

  Future<Directory> _documentsDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final directory = Directory(path.join(base.path, _documentsFolder));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<void> _saveDocuments(List<OfflineDocument> documents) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _indexKey,
      jsonEncode(documents.map((item) => item.toJson()).toList()),
    );
  }

  String _safeFileName(String value, String extension) {
    final trimmed = value.trim().isEmpty ? 'book$extension' : value.trim();
    final withExtension = trimmed.toLowerCase().endsWith(extension)
        ? trimmed
        : '$trimmed$extension';
    return withExtension.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
  }
}
