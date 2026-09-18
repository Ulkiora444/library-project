import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as path;

class ManhwaArchiveParser {
  Future<ManhwaChapter> parseAsset(
    String assetPath, {
    String? titleOverride,
  }) async {
    final data = await rootBundle.load(assetPath);
    return parseBytes(
      data.buffer.asUint8List(),
      sourcePath: assetPath,
      fileName: path.basename(assetPath),
      titleOverride: titleOverride,
    );
  }

  Future<ManhwaChapter> parseFile(
    String filePath, {
    String? titleOverride,
  }) async {
    final file = File(filePath);
    return parseBytes(
      await file.readAsBytes(),
      sourcePath: file.path,
      fileName: path.basename(file.path),
      titleOverride: titleOverride,
    );
  }

  ManhwaChapter parseBytes(
    Uint8List bytes, {
    required String sourcePath,
    required String fileName,
    String? titleOverride,
  }) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final imageEntries =
        archive.files
            .where(
              (entry) => entry.isFile && isSupportedManhwaImagePath(entry.name),
            )
            .toList()
          ..sort(
            (a, b) => naturalCompare(
              normalizeArchivePath(a.name),
              normalizeArchivePath(b.name),
            ),
          );

    if (imageEntries.isEmpty) {
      throw const FormatException(
        'В архиве не найдены изображения для чтения.',
      );
    }

    final pages = <ManhwaPage>[
      for (final entry in imageEntries)
        ManhwaPage.memory(
          path: normalizeArchivePath(entry.name),
          bytes: Uint8List.fromList(entry.readBytes() ?? const <int>[]),
          mimeType: guessManhwaImageMimeType(entry.name),
        ),
    ];

    return ManhwaChapter(
      title: titleOverride ?? formatManhwaArchiveTitle(fileName),
      sourcePath: sourcePath,
      fileName: fileName,
      pages: pages,
    );
  }
}

class ManhwaChapter {
  const ManhwaChapter({
    required this.title,
    required this.sourcePath,
    required this.fileName,
    required this.pages,
  });

  final String title;
  final String sourcePath;
  final String fileName;
  final List<ManhwaPage> pages;
}

class ManhwaPage {
  const ManhwaPage.memory({
    required this.path,
    required this.bytes,
    required this.mimeType,
  }) : imageUrl = null;

  const ManhwaPage.network({
    required this.path,
    required this.imageUrl,
    required this.mimeType,
  }) : bytes = null;

  final String path;
  final Uint8List? bytes;
  final String? imageUrl;
  final String mimeType;

  bool get isNetwork => imageUrl != null;
  bool get isSvg =>
      mimeType.contains('svg') || path.toLowerCase().endsWith('.svg');
}

class ManhwaLibraryItem {
  const ManhwaLibraryItem.asset({required this.sourcePath, required this.title})
    : isBundledAsset = true,
      isNetwork = false,
      networkPages = const [];

  const ManhwaLibraryItem.file({required this.sourcePath, required this.title})
    : isBundledAsset = false,
      isNetwork = false,
      networkPages = const [];

  const ManhwaLibraryItem.network({
    required this.sourcePath,
    required this.title,
    required this.networkPages,
  }) : isBundledAsset = false,
       isNetwork = true;

  final String sourcePath;
  final String title;
  final bool isBundledAsset;
  final bool isNetwork;
  final List<ManhwaPage> networkPages;
}

bool isSupportedManhwaArchivePath(String sourcePath) {
  final lower = sourcePath.toLowerCase();
  return lower.endsWith('.zip') || lower.endsWith('.cbz');
}

bool isSupportedManhwaImagePath(String sourcePath) {
  final lower = sourcePath.toLowerCase();
  return lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.bmp') ||
      lower.endsWith('.svg');
}

String normalizeArchivePath(String sourcePath) {
  return sourcePath.replaceAll('\\', '/');
}

String formatManhwaArchiveTitle(String fileName) {
  final baseName = path.basenameWithoutExtension(fileName);
  final cleaned = baseName.replaceAll(RegExp(r'\[[^\]]+\]'), '').trim();
  final match = RegExp(
    r'vol\s*(\d+)[ _-]+(\d+(?:[.,]\d+)?)',
    caseSensitive: false,
  ).firstMatch(cleaned);

  if (match != null) {
    return 'Том ${match.group(1)} · Глава ${match.group(2)?.replaceAll(',', '.')}';
  }

  return cleaned
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String formatSeriesTitle(String folderName) {
  final words = folderName
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();

  return words
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}

int naturalCompare(String left, String right) {
  final leftTokens = RegExp(
    r'\d+|\D+',
  ).allMatches(left).map((match) => match.group(0)!).toList();
  final rightTokens = RegExp(
    r'\d+|\D+',
  ).allMatches(right).map((match) => match.group(0)!).toList();
  final length = leftTokens.length < rightTokens.length
      ? leftTokens.length
      : rightTokens.length;

  for (var i = 0; i < length; i++) {
    final leftToken = leftTokens[i];
    final rightToken = rightTokens[i];
    final leftNumber = int.tryParse(leftToken);
    final rightNumber = int.tryParse(rightToken);

    if (leftNumber != null && rightNumber != null) {
      final numberComparison = leftNumber.compareTo(rightNumber);
      if (numberComparison != 0) {
        return numberComparison;
      }
      continue;
    }

    final textComparison = leftToken.toLowerCase().compareTo(
      rightToken.toLowerCase(),
    );
    if (textComparison != 0) {
      return textComparison;
    }
  }

  return leftTokens.length.compareTo(rightTokens.length);
}

String guessManhwaImageMimeType(String sourcePath) {
  final lower = sourcePath.toLowerCase();
  if (lower.endsWith('.svg')) {
    return 'image/svg+xml';
  }
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (lower.endsWith('.gif')) {
    return 'image/gif';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  if (lower.endsWith('.bmp')) {
    return 'image/bmp';
  }
  return 'application/octet-stream';
}
