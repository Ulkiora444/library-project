import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ReadingLibraryStore {
  static const String _readLaterKey = 'reader_read_later_books';
  static const String _bookmarksKey = 'reader_bookmarks';

  Future<List<ReadingListBook>> loadReadLater() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeList(
      prefs.getString(_readLaterKey),
      ReadingListBook.fromJson,
    );
  }

  Future<void> addOrUpdateReadLater(ReadingListBook book) async {
    final books = await loadReadLater();
    final next = [
      book,
      for (final item in books)
        if (item.id != book.id) item,
    ];
    await _saveReadLater(next);
  }

  Future<void> removeReadLater(String id) async {
    final books = await loadReadLater();
    await _saveReadLater([
      for (final item in books)
        if (item.id != id) item,
    ]);
  }

  Future<bool> isInReadLater(String id) async {
    final books = await loadReadLater();
    return books.any((item) => item.id == id);
  }

  Future<List<ReadingBookmark>> loadBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeList(
      prefs.getString(_bookmarksKey),
      ReadingBookmark.fromJson,
    );
  }

  Future<void> addOrUpdateBookmark(ReadingBookmark bookmark) async {
    final bookmarks = await loadBookmarks();
    final next = [
      bookmark,
      for (final item in bookmarks)
        if (item.id != bookmark.id) item,
    ];
    await _saveBookmarks(next);
  }

  Future<void> removeBookmark(String id) async {
    final bookmarks = await loadBookmarks();
    await _saveBookmarks([
      for (final item in bookmarks)
        if (item.id != id) item,
    ]);
  }

  Future<void> _saveReadLater(List<ReadingListBook> books) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _readLaterKey,
      jsonEncode([for (final book in books) book.toJson()]),
    );
  }

  Future<void> _saveBookmarks(List<ReadingBookmark> bookmarks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _bookmarksKey,
      jsonEncode([for (final bookmark in bookmarks) bookmark.toJson()]),
    );
  }

  List<T> _decodeList<T>(
    String? raw,
    T? Function(Map<String, Object?> json) decoder,
  ) {
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }

    try {
      final value = jsonDecode(raw);
      if (value is! List) {
        return const [];
      }

      return [
        for (final item in value)
          if (item is Map)
            if (decoder(Map<String, Object?>.from(item)) case final decoded?)
              decoded,
      ];
    } catch (_) {
      return const [];
    }
  }
}

class ReadingListBook {
  const ReadingListBook({
    required this.id,
    required this.title,
    required this.author,
    required this.category,
    required this.sourceType,
    required this.sourcePath,
    required this.chapterCount,
    required this.addedAt,
  });

  final String id;
  final String title;
  final String author;
  final String category;
  final String sourceType;
  final String sourcePath;
  final int chapterCount;
  final DateTime addedAt;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'category': category,
      'sourceType': sourceType,
      'sourcePath': sourcePath,
      'chapterCount': chapterCount,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  static ReadingListBook? fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final title = json['title'];
    if (id is! String || id.isEmpty || title is! String || title.isEmpty) {
      return null;
    }

    return ReadingListBook(
      id: id,
      title: title,
      author: (json['author'] as String?) ?? '',
      category: (json['category'] as String?) ?? '',
      sourceType: (json['sourceType'] as String?) ?? '',
      sourcePath: (json['sourcePath'] as String?) ?? '',
      chapterCount: (json['chapterCount'] as num?)?.toInt() ?? 0,
      addedAt:
          DateTime.tryParse((json['addedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class ReadingBookmark {
  const ReadingBookmark({
    required this.id,
    required this.bookId,
    required this.bookTitle,
    required this.chapterTitle,
    required this.chapterIndex,
    required this.chapterPath,
    required this.sourceType,
    required this.sourcePath,
    required this.createdAt,
  });

  final String id;
  final String bookId;
  final String bookTitle;
  final String chapterTitle;
  final int chapterIndex;
  final String chapterPath;
  final String sourceType;
  final String sourcePath;
  final DateTime createdAt;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'bookId': bookId,
      'bookTitle': bookTitle,
      'chapterTitle': chapterTitle,
      'chapterIndex': chapterIndex,
      'chapterPath': chapterPath,
      'sourceType': sourceType,
      'sourcePath': sourcePath,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  static ReadingBookmark? fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final bookId = json['bookId'];
    final bookTitle = json['bookTitle'];
    if (id is! String ||
        id.isEmpty ||
        bookId is! String ||
        bookId.isEmpty ||
        bookTitle is! String ||
        bookTitle.isEmpty) {
      return null;
    }

    return ReadingBookmark(
      id: id,
      bookId: bookId,
      bookTitle: bookTitle,
      chapterTitle: (json['chapterTitle'] as String?) ?? '',
      chapterIndex: (json['chapterIndex'] as num?)?.toInt() ?? 0,
      chapterPath: (json['chapterPath'] as String?) ?? '',
      sourceType: (json['sourceType'] as String?) ?? '',
      sourcePath: (json['sourcePath'] as String?) ?? '',
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
