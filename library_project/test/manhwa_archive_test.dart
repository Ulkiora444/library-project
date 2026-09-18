import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_project/src/manhwa_archive.dart';
import 'package:path/path.dart' as path;

void main() {
  Uint8List zipBytes(Map<String, List<int>> files) {
    final archive = Archive();
    for (final entry in files.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }

    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  test('parses archive files into naturally ordered image pages', () async {
    final directory = await Directory.systemTemp.createTemp('archive-parser-');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final archivePath = path.join(directory.path, 'vol1_12[test].zip');
    await File(archivePath).writeAsBytes(
      zipBytes({
        'pages/page10.jpg': [10],
        'pages/page2.jpg': [2],
        'pages/page1.png': [1],
        'readme.txt': [0],
      }),
    );

    final chapter = await ManhwaArchiveParser().parseFile(archivePath);

    expect(chapter.title, 'Том 1 · Глава 12');
    expect(chapter.pages.map((page) => page.path), [
      'pages/page1.png',
      'pages/page2.jpg',
      'pages/page10.jpg',
    ]);
    expect(chapter.pages.map((page) => page.mimeType), [
      'image/png',
      'image/jpeg',
      'image/jpeg',
    ]);
    expect(
      chapter.pages.every((page) => page.bytes?.isNotEmpty ?? false),
      isTrue,
    );
  });

  test('throws a clear error when archive has no image pages', () {
    final bytes = zipBytes({
      'notes/readme.txt': [1, 2, 3],
    });

    expect(
      () => ManhwaArchiveParser().parseBytes(
        bytes,
        sourcePath: 'empty.zip',
        fileName: 'empty.zip',
      ),
      throwsFormatException,
    );
  });
}
