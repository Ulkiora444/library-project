import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_project/src/epub_parser.dart';
import 'package:path/path.dart' as path;

void main() {
  test('parses malformed chapter markup and table of contents', () {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string('META-INF/container.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
'''),
      )
      ..addFile(
        ArchiveFile.string('OEBPS/content.opf', '''
<?xml version="1.0" encoding="utf-8"?>
<package version="3.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookId">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Test Book</dc:title>
    <dc:creator>Author</dc:creator>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="chapter-1" href="Text/chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="image-1" href="Images/picture.png" media-type="image/png"/>
  </manifest>
  <spine>
    <itemref idref="chapter-1"/>
  </spine>
</package>
'''),
      )
      ..addFile(
        ArchiveFile.string('OEBPS/nav.xhtml', '''
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
  <body>
    <nav epub:type="toc">
      <ol>
        <li><a href="Text/chapter1.xhtml#section-1">Section 1</a></li>
      </ol>
    </nav>
  </body>
</html>
'''),
      )
      ..addFile(
        ArchiveFile.string('OEBPS/Text/chapter1.xhtml', '''
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Chapter One</title></head>
  <body>
    <h1 id="section-1">Chapter One</h1>
    <p>Broken <strong>markup
    <img src="../Images/picture.png" alt="pic">
  </body>
</html>
'''),
      )
      ..addFile(
        ArchiveFile.bytes(
          'OEBPS/Images/picture.png',
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9p0V5wAAAABJRU5ErkJggg==',
          ),
        ),
      );

    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    final book = EpubParser().parseBytes(bytes, fileName: 'test.epub');

    expect(book.title, 'Test Book');
    expect(book.author, 'Author');
    expect(book.chapters, hasLength(1));
    expect(book.tocEntries, hasLength(1));
    expect(book.tocEntries.single.label, 'Section 1');
    expect(book.tocEntries.single.fragment, 'section-1');

    final chapter = book.chapters.single;
    expect(chapter.path, 'OEBPS/Text/chapter1.xhtml');
    expect(chapter.html, contains('Chapter One'));
    expect(chapter.html, contains('../Images/picture.png'));

    final image = book.resolveAsset(
      '../Images/picture.png',
      currentPath: chapter.path,
    );
    expect(image, isNotNull);
    expect(image!.bytes, isNotEmpty);

    final location = book.resolveLocation(
      'Text/chapter1.xhtml#section-1',
      currentPath: 'OEBPS/nav.xhtml',
    );
    expect(location, isNotNull);
    expect(location!.chapterIndex, 0);
    expect(location.fragment, 'section-1');
  });

  test('chooses a meaningful opening chapter from a local epub file', () async {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string('META-INF/container.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
'''),
      )
      ..addFile(
        ArchiveFile.string('OEBPS/content.opf', '''
<?xml version="1.0" encoding="utf-8"?>
<package version="3.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookId">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Local Book</dc:title>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="cover" href="Text/cover.xhtml" media-type="application/xhtml+xml"/>
    <item id="chapter-1" href="Text/chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="page-1" href="Images/page001.jpg" media-type="image/jpeg"/>
  </manifest>
  <spine>
    <itemref idref="cover"/>
    <itemref idref="chapter-1"/>
  </spine>
</package>
'''),
      )
      ..addFile(
        ArchiveFile.string('OEBPS/nav.xhtml', '''
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
  <body>
    <nav epub:type="toc">
      <ol>
        <li><a href="Text/cover.xhtml">Cover</a></li>
        <li><a href="Text/chapter1.xhtml">Chapter One</a></li>
      </ol>
    </nav>
  </body>
</html>
'''),
      )
      ..addFile(
        ArchiveFile.string('OEBPS/Text/cover.xhtml', '''
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml"><body><h1>Cover</h1></body></html>
'''),
      )
      ..addFile(
        ArchiveFile.string('OEBPS/Text/chapter1.xhtml', '''
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
  <body>
    <img src="../Images/page001.jpg" alt="page"/>
  </body>
</html>
'''),
      )
      ..addFile(ArchiveFile.bytes('OEBPS/Images/page001.jpg', [1, 2, 3]));

    final directory = await Directory.systemTemp.createTemp('epub-parser-');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final file = File(path.join(directory.path, 'local-book.epub'));
    await file.writeAsBytes(ZipEncoder().encode(archive));

    final book = await EpubParser().parseFile(file.path);
    final startChapter = book.chapters[book.suggestedStartChapterIndex];

    expect(book.suggestedStartChapterIndex, 1);
    expect(startChapter.path, 'OEBPS/Text/chapter1.xhtml');
    expect(startChapter.primaryMedia?.reference, '../Images/page001.jpg');
    expect(
      book.resolveAsset(
        '../Images/page001.jpg',
        currentPath: startChapter.path,
      ),
      isNotNull,
    );
  });
}
