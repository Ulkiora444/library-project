import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'manhwa_archive.dart';
import 'reader_user_session.dart';

enum RemoteArchiveKind { manga, manhwa, epub, pdf }

enum BookReaction { none, like, dislike }

class LibraryApiClient {
  LibraryApiClient({http.Client? httpClient, String? baseUrl})
    : _httpClient = httpClient ?? http.Client(),
      baseUrl = _normalizeBaseUrl(baseUrl ?? _defaultBaseUrl);

  static final LibraryApiClient instance = LibraryApiClient();

  static const String _configuredBaseUrl = String.fromEnvironment(
    'LIBRARY_API_BASE_URL',
  );

  static String get _defaultBaseUrl {
    if (_configuredBaseUrl.trim().isNotEmpty) {
      return _configuredBaseUrl.trim();
    }

    return 'http://10.66.136.40:3000';
  }

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  final http.Client _httpClient;
  final String baseUrl;

  Uri _apiUri(String endpoint) {
    final normalized = endpoint.startsWith('/') ? endpoint : '/$endpoint';
    return Uri.parse('$baseUrl/api$normalized');
  }

  String fileUrl(String fileName) {
    final value = fileName.trim();
    if (value.startsWith('http://') ||
        value.startsWith('https://') ||
        value.startsWith('data:')) {
      return value;
    }

    return '$baseUrl/${Uri.encodeComponent(value)}';
  }

  Future<Uint8List> downloadFileBytes(String fileNameOrUrl) async {
    final response = await _httpClient
        .get(Uri.parse(fileUrl(fileNameOrUrl)))
        .timeout(const Duration(minutes: 2));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LibraryApiException('Backend returned ${response.statusCode}');
    }

    return response.bodyBytes;
  }

  Future<ReaderUserSession> login({
    required String login,
    required String password,
  }) async {
    final data = await _postObject('/users/login', <String, Object?>{
      'login': login,
      'password': password,
    });

    return _sessionFromJson(data, isGuest: false);
  }

  Future<ReaderUserSession> register({
    required String username,
    required String phone,
    required String email,
    required String password,
  }) async {
    final data = await _postObject('/users', <String, Object?>{
      'username': username,
      'phone': phone,
      'email': email,
      'password': password,
      'image': '',
    });

    return _sessionFromJson(data, isGuest: false, fallbackPhone: phone);
  }

  Future<List<RemoteArchiveSeries>> loadArchiveSeries(
    RemoteArchiveKind kind,
  ) async {
    final catalog = await loadCatalogSeries();
    return catalog
        .where(
          (series) =>
              series.kind == kind &&
              (series.kind == RemoteArchiveKind.epub
                  ? series.epubFileUrl.isNotEmpty
                  : series.kind == RemoteArchiveKind.pdf
                  ? series.pdfFileUrl.isNotEmpty
                  : series.chapterCount > 0),
        )
        .toList();
  }

  Future<RemoteArchiveSeries> loadSeriesChapters(
    RemoteArchiveSeries series,
  ) async {
    if (series.kind == RemoteArchiveKind.epub ||
        series.kind == RemoteArchiveKind.pdf ||
        series.chapters.isNotEmpty) {
      return series;
    }

    final endpoint = switch (series.kind) {
      RemoteArchiveKind.manga => '/manga_books/book/${series.bookId}',
      RemoteArchiveKind.manhwa => '/manhwa_books/book/${series.bookId}',
      RemoteArchiveKind.epub => '',
      RemoteArchiveKind.pdf => '',
    };
    final rows = await _getList(endpoint, timeout: const Duration(seconds: 45));
    final chapters = _contentRowsToChapters(rows, series.kind, series.bookId);

    return series.copyWith(
      chapters: chapters,
      chapterCount: chapters.isEmpty ? series.chapterCount : chapters.length,
    );
  }

  Future<BookReactionCounts> reactToBook({
    required int bookId,
    required BookReaction reaction,
    required BookReaction previousReaction,
  }) async {
    final data = await _postObject('/books/$bookId/reaction', <String, Object?>{
      'reaction': reaction.name,
      'previousReaction': previousReaction.name,
    });

    return BookReactionCounts(
      likesTotal: _intValue(data['likes_total']) ?? 0,
      dislikesTotal: _intValue(data['do_not_likes_total']) ?? 0,
    );
  }

  Future<List<RemoteCategory>> loadCategories() async {
    final rows = await _getList('/categories');
    final categories = <RemoteCategory>[];

    for (final row in rows) {
      final id = _intValue(row['id']);
      final name = _stringValue(row['name']);
      if (id == null || name.isEmpty) {
        continue;
      }

      final image = _stringValue(row['image']);
      categories.add(
        RemoteCategory(
          id: id,
          name: name,
          description: _stringValue(row['description']),
          imageUrl: image.isEmpty ? '' : fileUrl(image),
        ),
      );
    }

    categories.sort((a, b) => naturalCompare(a.name, b.name));
    return categories;
  }

  Future<List<RemoteBookCollection>> loadBookCollections() async {
    final rows = await _getList('/collections_books');
    final grouped = <int, _RemoteBookCollectionBuilder>{};

    for (final row in rows) {
      final collection = _mapValue(row['collections']);
      final book = _mapValue(row['books']);
      final collectionId =
          _intValue(row['collectionsId']) ?? _intValue(collection?['id']);
      final bookId = _intValue(row['booksId']) ?? _intValue(book?['id']);
      if (collectionId == null || bookId == null) {
        continue;
      }

      final name = _stringValue(collection?['name']);
      if (name.isEmpty) {
        continue;
      }

      final builder = grouped.putIfAbsent(
        collectionId,
        () => _RemoteBookCollectionBuilder(
          id: collectionId,
          name: name,
          description: _stringValue(collection?['description']),
        ),
      );
      builder.bookIds.add(bookId);
    }

    final collections = [
      for (final item in grouped.values)
        RemoteBookCollection(
          id: item.id,
          name: item.name,
          description: item.description,
          bookIds: item.bookIds.toList()..sort(),
        ),
    ]..sort((a, b) => naturalCompare(a.name, b.name));

    return collections;
  }

  Future<List<RemoteArchiveSeries>> loadCatalogSeries() async {
    final books = await _getList('/books/catalog');
    final series = <RemoteArchiveSeries>[];
    for (final book in books) {
      final bookId = _intValue(book['id']);
      if (bookId == null) {
        continue;
      }

      final readerName = _stringValue(_mapValue(book['readers'])?['name']);
      final mangaChapterCount = _intValue(book['mangaChapterCount']) ?? 0;
      final manhwaChapterCount = _intValue(book['manhwaChapterCount']) ?? 0;
      final epubFile = _stringValue(book['epubFile']);
      final pdfFile = _stringValue(book['pdfFile']);
      final kind = _kindForBook(
        readerName: readerName,
        hasManga: mangaChapterCount > 0,
        hasManhwa: manhwaChapterCount > 0,
        hasEpub: epubFile.isNotEmpty,
        hasPdf: pdfFile.isNotEmpty,
      );
      final chapterCount = switch (kind) {
        RemoteArchiveKind.manga => mangaChapterCount,
        RemoteArchiveKind.manhwa => manhwaChapterCount,
        RemoteArchiveKind.epub => 0,
        RemoteArchiveKind.pdf => 0,
      };
      final bookTitle = _stringValue(book['name']);
      final image = _stringValue(book['image']);

      series.add(
        RemoteArchiveSeries(
          id: 'remote:${kind.name}:$bookId',
          bookId: bookId,
          kind: kind,
          title: bookTitle.isEmpty ? 'Book $bookId' : bookTitle,
          description: _stringValue(book['description']),
          language: _stringValue(book['language']),
          imageUrl: image.isEmpty ? '' : fileUrl(image),
          authors: _uniqueSorted(_namesFromList(book['authors'])),
          categories: _uniqueSorted(_namesFromList(book['categories'])),
          releaseYear: _intValue(book['year']),
          recommendedAge: _intValue(book['recommended_age']),
          likesTotal: _intValue(book['likes_total']) ?? 0,
          dislikesTotal: _intValue(book['do_not_likes_total']) ?? 0,
          chapterCount: chapterCount,
          chapters: const [],
          epubFileUrl: epubFile.isEmpty ? '' : fileUrl(epubFile),
          pdfFileUrl: pdfFile.isEmpty ? '' : fileUrl(pdfFile),
        ),
      );
    }

    series.sort((a, b) => naturalCompare(a.title, b.title));
    return series;
  }

  List<RemoteArchiveChapter> _contentRowsToChapters(
    List<Map<String, Object?>> rows,
    RemoteArchiveKind kind,
    int bookId,
  ) {
    final groupedByChapter = <String, List<Map<String, Object?>>>{};

    for (final row in rows) {
      final file = _stringValue(row['file']);
      if (file.isEmpty) {
        continue;
      }
      final chapter = _stringValue(row['name']).isEmpty
          ? '1'
          : _stringValue(row['name']);
      groupedByChapter
          .putIfAbsent(chapter, () => <Map<String, Object?>>[])
          .add(row);
    }

    final chapters = groupedByChapter.entries.map((chapterEntry) {
      final pages = chapterEntry.value
        ..sort((a, b) {
          final aId = _intValue(a['id']) ?? 0;
          final bId = _intValue(b['id']) ?? 0;
          return aId.compareTo(bId);
        });

      final chapterTitle = chapterEntry.key;
      return RemoteArchiveChapter(
        title: chapterTitle,
        sourcePath: 'remote:${kind.name}:$bookId:$chapterTitle',
        pages: [
          for (final row in pages)
            ManhwaPage.network(
              path: 'remote:${kind.name}:$bookId:$chapterTitle:${row['id']}',
              imageUrl: fileUrl(_stringValue(row['file'])),
              mimeType: guessManhwaImageMimeType(_stringValue(row['file'])),
            ),
        ],
      );
    }).toList()..sort((a, b) => naturalCompare(a.title, b.title));

    return chapters;
  }

  RemoteArchiveKind _kindForBook({
    required String readerName,
    required bool hasManga,
    required bool hasManhwa,
    required bool hasEpub,
    required bool hasPdf,
  }) {
    final normalized = readerName.toLowerCase();
    if (normalized.contains('pdf') || normalized.contains('пдф')) {
      return RemoteArchiveKind.pdf;
    }
    if (normalized.contains('epub') || normalized.contains('e-book')) {
      return RemoteArchiveKind.epub;
    }
    if (normalized.contains('manhwa') || normalized.contains('манхв')) {
      return RemoteArchiveKind.manhwa;
    }
    if (normalized.contains('manga') || normalized.contains('манг')) {
      return RemoteArchiveKind.manga;
    }
    if (hasManhwa) {
      return RemoteArchiveKind.manhwa;
    }
    if (hasManga) {
      return RemoteArchiveKind.manga;
    }
    if (hasEpub) {
      return RemoteArchiveKind.epub;
    }
    if (hasPdf) {
      return RemoteArchiveKind.pdf;
    }
    return RemoteArchiveKind.manga;
  }

  List<String> _uniqueSorted(List<String> values) {
    final result = values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    result.sort(naturalCompare);
    return result;
  }

  List<String> _namesFromList(Object? value) {
    if (value is! List) {
      return const [];
    }

    return [
      for (final item in value)
        if (item is Map)
          _stringValue(item.cast<String, Object?>()['name'])
        else
          _stringValue(item),
    ];
  }

  Future<List<Map<String, Object?>>> _getList(
    String endpoint, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final response = await _httpClient.get(_apiUri(endpoint)).timeout(timeout);

    final body = _decodeBody(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LibraryApiException('Backend returned ${response.statusCode}');
    }

    if (body['success'] != true) {
      throw const LibraryApiException('Backend response was not successful');
    }

    final data = body['datas'];
    if (data is! List) {
      return const [];
    }

    return [
      for (final item in data)
        if (item is Map) item.cast<String, Object?>(),
    ];
  }

  Future<Map<String, Object?>> _postObject(
    String endpoint,
    Map<String, Object?> payload,
  ) async {
    final response = await _httpClient
        .post(
          _apiUri(endpoint),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 5));

    final body = _decodeBody(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LibraryApiException('Backend returned ${response.statusCode}');
    }

    if (body['success'] != true) {
      throw const LibraryApiException('Backend response was not successful');
    }

    final data = body['datas'];
    if (data is Map) {
      return data.cast<String, Object?>();
    }
    if (data is List && data.isNotEmpty && data.first is Map) {
      return (data.first as Map).cast<String, Object?>();
    }

    throw const LibraryApiException('Backend returned empty data');
  }

  Map<String, Object?> _decodeBody(http.Response response) {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map) {
      return decoded.cast<String, Object?>();
    }
    throw const LibraryApiException('Backend returned invalid JSON');
  }

  ReaderUserSession _sessionFromJson(
    Map<String, Object?> json, {
    required bool isGuest,
    String fallbackPhone = '',
  }) {
    return ReaderUserSession(
      displayName: _stringValue(json['username']),
      email: _stringValue(json['email']),
      phoneNumber: _stringValue(json['phone']).isEmpty
          ? fallbackPhone
          : _stringValue(json['phone']),
      isGuest: isGuest,
      categoryPickerPending: false,
    );
  }

  static int? _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static String _stringValue(Object? value) {
    if (value == null) {
      return '';
    }
    return value.toString().trim();
  }

  static Map<String, Object?>? _mapValue(Object? value) {
    if (value is Map) {
      return value.cast<String, Object?>();
    }
    return null;
  }
}

class RemoteArchiveSeries {
  const RemoteArchiveSeries({
    required this.id,
    required this.bookId,
    required this.kind,
    required this.title,
    required this.description,
    required this.language,
    required this.imageUrl,
    required this.authors,
    required this.categories,
    required this.releaseYear,
    required this.recommendedAge,
    required this.likesTotal,
    required this.dislikesTotal,
    required this.chapterCount,
    required this.chapters,
    required this.epubFileUrl,
    required this.pdfFileUrl,
  });

  final String id;
  final int bookId;
  final RemoteArchiveKind kind;
  final String title;
  final String description;
  final String language;
  final String imageUrl;
  final List<String> authors;
  final List<String> categories;
  final int? releaseYear;
  final int? recommendedAge;
  final int likesTotal;
  final int dislikesTotal;
  final int chapterCount;
  final List<RemoteArchiveChapter> chapters;
  final String epubFileUrl;
  final String pdfFileUrl;

  RemoteArchiveSeries copyWith({
    List<RemoteArchiveChapter>? chapters,
    int? chapterCount,
    String? epubFileUrl,
    String? pdfFileUrl,
    int? likesTotal,
    int? dislikesTotal,
  }) {
    return RemoteArchiveSeries(
      id: id,
      bookId: bookId,
      kind: kind,
      title: title,
      description: description,
      language: language,
      imageUrl: imageUrl,
      authors: authors,
      categories: categories,
      releaseYear: releaseYear,
      recommendedAge: recommendedAge,
      likesTotal: likesTotal ?? this.likesTotal,
      dislikesTotal: dislikesTotal ?? this.dislikesTotal,
      chapterCount: chapterCount ?? this.chapterCount,
      chapters: chapters ?? this.chapters,
      epubFileUrl: epubFileUrl ?? this.epubFileUrl,
      pdfFileUrl: pdfFileUrl ?? this.pdfFileUrl,
    );
  }
}

class BookReactionCounts {
  const BookReactionCounts({
    required this.likesTotal,
    required this.dislikesTotal,
  });

  final int likesTotal;
  final int dislikesTotal;
}

class RemoteArchiveChapter {
  const RemoteArchiveChapter({
    required this.title,
    required this.sourcePath,
    required this.pages,
  });

  final String title;
  final String sourcePath;
  final List<ManhwaPage> pages;
}

class RemoteCategory {
  const RemoteCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.imageUrl,
  });

  final int id;
  final String name;
  final String description;
  final String imageUrl;
}

class RemoteBookCollection {
  const RemoteBookCollection({
    required this.id,
    required this.name,
    required this.description,
    required this.bookIds,
  });

  final int id;
  final String name;
  final String description;
  final List<int> bookIds;
}

class _RemoteBookCollectionBuilder {
  _RemoteBookCollectionBuilder({
    required this.id,
    required this.name,
    required this.description,
  });

  final int id;
  final String name;
  final String description;
  final Set<int> bookIds = <int>{};
}

class LibraryApiException implements Exception {
  const LibraryApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
