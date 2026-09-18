import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as html;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as path;
import 'package:xml/xml.dart';

class EpubParser {
  Future<EpubBook> parseFile(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final fileName = path.basename(file.path);
    return parseBytes(bytes, sourcePath: file.path, fileName: fileName);
  }

  EpubBook parseBytes(Uint8List bytes, {String? sourcePath, String? fileName}) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final assets = <String, EpubAsset>{};

    for (final entry in archive.files.where((entry) => entry.isFile)) {
      final normalizedPath = normalizeArchivePath(entry.name);
      final fileBytes = entry.readBytes() ?? Uint8List(0);
      assets[normalizedPath] = EpubAsset(
        path: normalizedPath,
        bytes: Uint8List.fromList(fileBytes),
      );
    }

    final rootFilePath = _parseRootFilePath(assets);
    final packageAsset = assets[rootFilePath];
    if (packageAsset == null) {
      throw const FormatException('Не найден пакет EPUB.');
    }

    final packageText = decodeText(packageAsset.bytes);
    final packageData = _parsePackageData(
      packageText: packageText,
      packagePath: rootFilePath,
    );

    final tocEntries = _parseTocEntries(
      assets: assets,
      packageData: packageData,
    );

    final chapterLabels = <String, String>{};
    for (final entry in tocEntries) {
      chapterLabels.putIfAbsent(entry.path, () => entry.label);
    }

    final orderedItems = <_ManifestItem>[];
    final seenPaths = <String>{};

    for (final itemId in packageData.spineItemIds) {
      final item = packageData.manifest[itemId];
      if (item == null || item.isNavigationDocument || !item.isHtmlDocument) {
        continue;
      }
      if (seenPaths.add(item.path)) {
        orderedItems.add(item);
      }
    }

    for (final item in packageData.manifest.values) {
      if (item.isNavigationDocument || !item.isHtmlDocument) {
        continue;
      }
      if (seenPaths.add(item.path)) {
        orderedItems.add(item);
      }
    }

    final chapters = <EpubChapter>[];

    for (final item in orderedItems) {
      final asset = assets[item.path];
      if (asset == null) {
        continue;
      }

      final prepared = _prepareChapterHtml(
        rawHtml: decodeText(asset.bytes),
        chapterPath: item.path,
        assets: assets,
      );

      final title =
          _extractChapterTitle(prepared.document) ??
          chapterLabels[item.path] ??
          item.id;

      chapters.add(
        EpubChapter(
          id: item.id,
          path: item.path,
          title: title.isEmpty ? 'Глава ${chapters.length + 1}' : title,
          html: prepared.document.outerHtml,
          primaryMedia: prepared.primaryMedia,
        ),
      );
    }

    final bookTitle = packageData.title?.trim().isNotEmpty == true
        ? packageData.title!.trim()
        : (fileName ?? 'Без названия');

    final normalizedToc = tocEntries.isNotEmpty
        ? tocEntries
        : [
            for (var i = 0; i < chapters.length; i++)
              EpubTocEntry(
                label: chapters[i].title,
                path: chapters[i].path,
                depth: 0,
              ),
          ];

    return EpubBook(
      title: bookTitle,
      author: packageData.author?.trim().isEmpty == true
          ? null
          : packageData.author?.trim(),
      sourcePath: sourcePath,
      fileName: fileName ?? bookTitle,
      chapters: chapters,
      tocEntries: normalizedToc,
      assets: assets,
    );
  }

  String _parseRootFilePath(Map<String, EpubAsset> assets) {
    const containerPath = 'META-INF/container.xml';
    final containerAsset = assets[containerPath];
    if (containerAsset == null) {
      throw const FormatException(
        'Не найден META-INF/container.xml. Файл не похож на EPUB.',
      );
    }

    final containerText = decodeText(containerAsset.bytes);
    final xmlDocument = tryParseXml(containerText);
    if (xmlDocument != null) {
      final rootFile = xmlDocument.descendants
          .whereType<XmlElement>()
          .firstWhereOrNull((element) => element.name.local == 'rootfile');
      final fullPath = rootFile?.attributes
          .firstWhereOrNull((attribute) => attribute.name.local == 'full-path')
          ?.value;
      if (fullPath != null && fullPath.trim().isNotEmpty) {
        return normalizeArchivePath(fullPath);
      }
    }

    final match = RegExp(
      r'''<rootfile[^>]*full-path=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(containerText);
    if (match != null) {
      return normalizeArchivePath(match.group(1)!);
    }

    throw const FormatException('Не удалось определить основной файл EPUB.');
  }

  _PackageData _parsePackageData({
    required String packageText,
    required String packagePath,
  }) {
    final xmlDocument = tryParseXml(packageText);
    if (xmlDocument != null) {
      return _parsePackageDataFromXml(
        xmlDocument: xmlDocument,
        packagePath: packagePath,
      );
    }

    return _parsePackageDataFromHtml(
      document: html_parser.parse(packageText),
      packagePath: packagePath,
    );
  }

  _PackageData _parsePackageDataFromXml({
    required XmlDocument xmlDocument,
    required String packagePath,
  }) {
    final manifest = <String, _ManifestItem>{};
    final spineItemIds = <String>[];
    String? navItemId;
    String? ncxItemId;

    for (final element in xmlDocument.descendants.whereType<XmlElement>()) {
      if (element.name.local == 'item') {
        final id = element.attributeByLocalName('id');
        final href = element.attributeByLocalName('href');
        if (id == null || href == null) {
          continue;
        }

        final mediaType = element.attributeByLocalName('media-type');
        final properties = (element.attributeByLocalName('properties') ?? '')
            .split(RegExp(r'\s+'))
            .where((value) => value.isNotEmpty)
            .toSet();

        final item = _ManifestItem(
          id: id,
          href: href,
          path: resolveArchivePath(packagePath, href),
          mediaType: mediaType,
          properties: properties,
        );
        manifest[id] = item;

        if (properties.contains('nav')) {
          navItemId = id;
        }
        if (mediaType == 'application/x-dtbncx+xml') {
          ncxItemId = id;
        }
      }

      if (element.name.local == 'spine') {
        final spineTocId = element.attributeByLocalName('toc');
        if (spineTocId != null && spineTocId.isNotEmpty) {
          ncxItemId ??= spineTocId;
        }

        for (final child in element.childElements.where(
          (child) => child.name.local == 'itemref',
        )) {
          final idRef = child.attributeByLocalName('idref');
          if (idRef != null && idRef.isNotEmpty) {
            spineItemIds.add(idRef);
          }
        }
      }
    }

    return _PackageData(
      title: _xmlFirstText(xmlDocument, 'title'),
      author: _xmlFirstText(xmlDocument, 'creator'),
      manifest: manifest,
      spineItemIds: spineItemIds,
      navPath: navItemId != null ? manifest[navItemId]?.path : null,
      ncxPath: ncxItemId != null ? manifest[ncxItemId]?.path : null,
    );
  }

  _PackageData _parsePackageDataFromHtml({
    required html.Document document,
    required String packagePath,
  }) {
    final manifest = <String, _ManifestItem>{};
    final spineItemIds = <String>[];
    String? navPath;
    String? ncxPath;

    for (final element in document.querySelectorAll('*')) {
      final name = element.localName ?? '';
      if (name == 'item') {
        final id = element.attributes['id'];
        final href = element.attributes['href'];
        if (id == null || href == null) {
          continue;
        }

        final mediaType = element.attributes['media-type'];
        final properties = (element.attributes['properties'] ?? '')
            .split(RegExp(r'\s+'))
            .where((value) => value.isNotEmpty)
            .toSet();

        final item = _ManifestItem(
          id: id,
          href: href,
          path: resolveArchivePath(packagePath, href),
          mediaType: mediaType,
          properties: properties,
        );
        manifest[id] = item;

        if (properties.contains('nav')) {
          navPath = item.path;
        }
        if (mediaType == 'application/x-dtbncx+xml') {
          ncxPath = item.path;
        }
      }

      if (name == 'spine') {
        final tocId = element.attributes['toc'];
        if (tocId != null && manifest.containsKey(tocId)) {
          ncxPath = manifest[tocId]?.path ?? ncxPath;
        }

        for (final child in element.children.where(
          (child) => child.localName == 'itemref',
        )) {
          final idRef = child.attributes['idref'];
          if (idRef != null && idRef.isNotEmpty) {
            spineItemIds.add(idRef);
          }
        }
      }
    }

    final title = document
        .querySelectorAll('*')
        .firstWhereOrNull(
          (element) =>
              element.localName == 'title' || element.localName == 'dc:title',
        );
    final creator = document
        .querySelectorAll('*')
        .firstWhereOrNull(
          (element) =>
              element.localName == 'creator' ||
              element.localName == 'dc:creator',
        );

    return _PackageData(
      title: title?.text.trim(),
      author: creator?.text.trim(),
      manifest: manifest,
      spineItemIds: spineItemIds,
      navPath: navPath,
      ncxPath: ncxPath,
    );
  }

  List<EpubTocEntry> _parseTocEntries({
    required Map<String, EpubAsset> assets,
    required _PackageData packageData,
  }) {
    if (packageData.navPath != null) {
      final navAsset = assets[packageData.navPath!];
      if (navAsset != null) {
        final entries = _parseNavDocument(
          navText: decodeText(navAsset.bytes),
          navPath: navAsset.path,
        );
        if (entries.isNotEmpty) {
          return entries;
        }
      }
    }

    if (packageData.ncxPath != null) {
      final ncxAsset = assets[packageData.ncxPath!];
      if (ncxAsset != null) {
        return _parseNcxDocument(
          ncxText: decodeText(ncxAsset.bytes),
          ncxPath: ncxAsset.path,
        );
      }
    }

    return const [];
  }

  List<EpubTocEntry> _parseNavDocument({
    required String navText,
    required String navPath,
  }) {
    final document = html_parser.parse(navText);
    final navElement =
        document.querySelectorAll('nav').firstWhereOrNull((element) {
          final epubType = element.attributes['epub:type'] ?? '';
          final type = element.attributes['type'] ?? '';
          final role = element.attributes['role'] ?? '';
          return epubType.contains('toc') ||
              type.contains('toc') ||
              role.contains('doc-toc');
        }) ??
        document.querySelector('nav');

    if (navElement == null) {
      return const [];
    }

    final listElement = navElement.children.firstWhereOrNull(
      (child) => child.localName == 'ol' || child.localName == 'ul',
    );
    if (listElement == null) {
      return const [];
    }

    return _flattenNavList(
      listElement: listElement,
      basePath: navPath,
      depth: 0,
    );
  }

  List<EpubTocEntry> _flattenNavList({
    required html.Element listElement,
    required String basePath,
    required int depth,
  }) {
    final entries = <EpubTocEntry>[];
    for (final child in listElement.children.where(
      (child) => child.localName == 'li',
    )) {
      final link = child.children.firstWhereOrNull(
        (element) => element.localName == 'a',
      );

      if (link != null) {
        final label = link.text.trim();
        final href = link.attributes['href'];
        final resolved = resolveReference(basePath, href);
        if (resolved != null && label.isNotEmpty) {
          entries.add(
            EpubTocEntry(
              label: label,
              path: resolved.path,
              fragment: resolved.fragment,
              depth: depth,
            ),
          );
        }
      }

      for (final nested in child.children.where(
        (element) => element.localName == 'ol' || element.localName == 'ul',
      )) {
        entries.addAll(
          _flattenNavList(
            listElement: nested,
            basePath: basePath,
            depth: depth + 1,
          ),
        );
      }
    }
    return entries;
  }

  List<EpubTocEntry> _parseNcxDocument({
    required String ncxText,
    required String ncxPath,
  }) {
    final xmlDocument = tryParseXml(ncxText);
    if (xmlDocument != null) {
      final navMap = xmlDocument.descendants
          .whereType<XmlElement>()
          .firstWhereOrNull((element) => element.name.local == 'navMap');
      if (navMap == null) {
        return const [];
      }

      final entries = <EpubTocEntry>[];
      for (final navPoint in navMap.childElements.where(
        (element) => element.name.local == 'navPoint',
      )) {
        entries.addAll(
          _flattenXmlNavPoints(navPoint: navPoint, basePath: ncxPath, depth: 0),
        );
      }
      return entries;
    }

    final document = html_parser.parse(ncxText);
    final navMap = document.querySelector('navmap');
    if (navMap == null) {
      return const [];
    }

    final entries = <EpubTocEntry>[];
    for (final navPoint in navMap.children.where(
      (element) => element.localName == 'navpoint',
    )) {
      entries.addAll(
        _flattenHtmlNavPoints(navPoint: navPoint, basePath: ncxPath, depth: 0),
      );
    }
    return entries;
  }

  List<EpubTocEntry> _flattenXmlNavPoints({
    required XmlElement navPoint,
    required String basePath,
    required int depth,
  }) {
    final entries = <EpubTocEntry>[];
    final label = navPoint.descendants
        .whereType<XmlElement>()
        .firstWhereOrNull((element) => element.name.local == 'text')
        ?.innerText
        .trim();
    final src = navPoint.descendants
        .whereType<XmlElement>()
        .firstWhereOrNull((element) => element.name.local == 'content')
        ?.attributeByLocalName('src');
    final resolved = resolveReference(basePath, src);

    if (label != null && label.isNotEmpty && resolved != null) {
      entries.add(
        EpubTocEntry(
          label: label,
          path: resolved.path,
          fragment: resolved.fragment,
          depth: depth,
        ),
      );
    }

    for (final child in navPoint.childElements.where(
      (element) => element.name.local == 'navPoint',
    )) {
      entries.addAll(
        _flattenXmlNavPoints(
          navPoint: child,
          basePath: basePath,
          depth: depth + 1,
        ),
      );
    }

    return entries;
  }

  List<EpubTocEntry> _flattenHtmlNavPoints({
    required html.Element navPoint,
    required String basePath,
    required int depth,
  }) {
    final entries = <EpubTocEntry>[];
    final label = navPoint.querySelector('navlabel > text')?.text.trim();
    final src = navPoint.querySelector('content')?.attributes['src'];
    final resolved = resolveReference(basePath, src);

    if (label != null && label.isNotEmpty && resolved != null) {
      entries.add(
        EpubTocEntry(
          label: label,
          path: resolved.path,
          fragment: resolved.fragment,
          depth: depth,
        ),
      );
    }

    for (final child in navPoint.children.where(
      (element) => element.localName == 'navpoint',
    )) {
      entries.addAll(
        _flattenHtmlNavPoints(
          navPoint: child,
          basePath: basePath,
          depth: depth + 1,
        ),
      );
    }

    return entries;
  }

  _PreparedChapter _prepareChapterHtml({
    required String rawHtml,
    required String chapterPath,
    required Map<String, EpubAsset> assets,
  }) {
    final document = html_parser.parse(normalizeXhtmlForHtmlParser(rawHtml));
    final head = document.head ?? html.Element.tag('head');

    for (final element in document.querySelectorAll('[name]')) {
      if ((element.id).isEmpty) {
        element.id = element.attributes['name'] ?? '';
      }
    }

    for (final script in document.querySelectorAll('script')) {
      script.remove();
    }

    final linkedCss = <String>[];
    for (final link in document.querySelectorAll('link[href]')) {
      final rel = link.attributes['rel'] ?? '';
      if (!rel.contains('stylesheet')) {
        continue;
      }
      final resolvedCss = resolveReference(
        chapterPath,
        link.attributes['href'],
      );
      final cssAsset = resolvedCss != null ? assets[resolvedCss.path] : null;
      if (cssAsset != null) {
        linkedCss.add(decodeText(cssAsset.bytes));
      }
      link.remove();
    }

    final style = html.Element.tag('style')
      ..text =
          '''
img, svg, object {
  max-width: 100%;
  height: auto;
}
${linkedCss.join('\n')}
''';
    head.nodes.add(style);

    for (final svgImage in document.querySelectorAll('image')) {
      final originalSource = imageSourceFromAttributes(svgImage.attributes);
      if (originalSource == null || originalSource.trim().isEmpty) {
        continue;
      }

      final resolved = resolveReference(chapterPath, originalSource);
      final asset = resolved != null
          ? findEpubAsset(assets, resolved.path)
          : null;
      if (asset == null) {
        continue;
      }

      final dataUri = buildDataUri(
        bytes: asset.bytes,
        mimeType: asset.mediaType ?? guessMimeType(asset.path),
      );
      svgImage.attributes['href'] = dataUri;
      svgImage.attributes['xlink:href'] = dataUri;
      svgImage.attributes['src'] = dataUri;
    }

    for (final svg in document.querySelectorAll('svg')) {
      final embeddedImages = svg
          .querySelectorAll('*')
          .where((child) => child.localName == 'image')
          .toList();
      if (embeddedImages.length != 1) {
        continue;
      }

      final imageReference = imageSourceFromAttributes(
        embeddedImages.single.attributes,
      );
      if (imageReference == null || imageReference.trim().isEmpty) {
        continue;
      }

      final image = html.Element.tag('img')
        ..attributes['src'] = imageReference
        ..attributes['alt'] =
            embeddedImages.single.attributes['alt'] ??
            embeddedImages.single.attributes['title'] ??
            svg.attributes['title'] ??
            '';
      svg.replaceWith(image);
    }

    return _PreparedChapter(
      document,
      primaryMedia: _extractPrimaryMedia(document),
    );
  }

  String? _extractChapterTitle(html.Document document) {
    final title = document.querySelector('title')?.text.trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }

    for (final selector in const ['h1', 'h2', 'h3']) {
      final heading = document.querySelector(selector)?.text.trim();
      if (heading != null && heading.isNotEmpty) {
        return heading;
      }
    }

    return null;
  }

  EpubChapterMedia? _extractPrimaryMedia(html.Document document) {
    final body = document.body;
    if (body == null) {
      return null;
    }

    final meaningfulNodes = body.nodes.where(_isMeaningfulChapterNode).toList();
    if (meaningfulNodes.length != 1) {
      return null;
    }

    return _extractMediaFromNode(meaningfulNodes.single);
  }

  bool _isMeaningfulChapterNode(html.Node node) {
    if (node is html.Text) {
      return node.text.trim().isNotEmpty;
    }

    return node is html.Element;
  }

  EpubChapterMedia? _extractMediaFromNode(html.Node node) {
    if (node is! html.Element) {
      return null;
    }

    final directMedia = _extractMediaFromElement(node);
    if (directMedia != null) {
      return directMedia;
    }

    final meaningfulChildren = node.nodes
        .where(_isMeaningfulChapterNode)
        .toList();
    if (meaningfulChildren.length != 1) {
      return null;
    }

    return _extractMediaFromNode(meaningfulChildren.single);
  }

  EpubChapterMedia? _extractMediaFromElement(html.Element element) {
    final tagName = element.localName?.toLowerCase();
    if (tagName == null) {
      return null;
    }

    if (tagName == 'svg') {
      final imageElement = element
          .querySelectorAll('*')
          .firstWhereOrNull((child) => child.localName == 'image');
      final imageReference = imageElement == null
          ? null
          : imageSourceFromAttributes(imageElement.attributes);
      final embeddedImage = imageElement;
      if (embeddedImage != null &&
          imageReference != null &&
          imageReference.trim().isNotEmpty) {
        return EpubChapterMedia(
          reference: imageReference,
          label:
              embeddedImage.attributes['alt'] ??
              embeddedImage.attributes['title'] ??
              element.attributes['title'] ??
              element.id,
        );
      }

      final markup = element.outerHtml.trim();
      if (markup.isEmpty) {
        return null;
      }
      return EpubChapterMedia(
        inlineSvgMarkup: markup,
        label: element.attributes['title'] ?? element.id,
      );
    }

    if (tagName != 'img' && tagName != 'image' && tagName != 'object') {
      return null;
    }

    final reference = imageSourceFromAttributes(element.attributes);
    if (reference == null || reference.trim().isEmpty) {
      return null;
    }

    return EpubChapterMedia(
      reference: reference,
      label:
          element.attributes['alt'] ??
          element.attributes['title'] ??
          element.id,
    );
  }

  String? _xmlFirstText(XmlDocument document, String localName) {
    return document.descendants
        .whereType<XmlElement>()
        .firstWhereOrNull((element) => element.name.local == localName)
        ?.innerText;
  }
}

class EpubBook {
  EpubBook({
    required this.title,
    required this.author,
    required this.sourcePath,
    required this.fileName,
    required this.chapters,
    required this.tocEntries,
    required this.assets,
  }) : chapterIndexByPath = {
         for (var i = 0; i < chapters.length; i++) chapters[i].path: i,
       },
       suggestedStartChapterIndex = _computeSuggestedStartChapterIndex(
         chapters: chapters,
         tocEntries: tocEntries,
       );

  final String title;
  final String? author;
  final String? sourcePath;
  final String fileName;
  final List<EpubChapter> chapters;
  final List<EpubTocEntry> tocEntries;
  final Map<String, EpubAsset> assets;
  final Map<String, int> chapterIndexByPath;
  final int suggestedStartChapterIndex;

  ResolvedAsset? resolveAsset(String reference, {required String currentPath}) {
    if (reference.trim().isEmpty) {
      return null;
    }

    final dataAsset = tryParseDataUri(reference);
    if (dataAsset != null) {
      return dataAsset;
    }

    if (isExternalReference(reference)) {
      return null;
    }

    final resolved = resolveReference(currentPath, reference);
    if (resolved == null) {
      return null;
    }

    final asset = findEpubAsset(assets, resolved.path);
    if (asset == null) {
      return null;
    }

    return ResolvedAsset(
      path: asset.path,
      bytes: asset.bytes,
      mimeType: asset.mediaType ?? guessMimeType(asset.path),
    );
  }

  ResolvedLocation? resolveLocation(
    String href, {
    required String currentPath,
  }) {
    if (href.trim().isEmpty || isExternalReference(href)) {
      return null;
    }

    final resolved = resolveReference(currentPath, href);
    if (resolved == null) {
      return null;
    }

    final index = chapterIndexByPath[resolved.path];
    if (index == null) {
      return null;
    }

    return ResolvedLocation(
      chapterIndex: index,
      path: resolved.path,
      fragment: resolved.fragment,
    );
  }

  static int _computeSuggestedStartChapterIndex({
    required List<EpubChapter> chapters,
    required List<EpubTocEntry> tocEntries,
  }) {
    if (chapters.isEmpty) {
      return 0;
    }

    final chapterIndexByPath = <String, int>{
      for (var i = 0; i < chapters.length; i++) chapters[i].path: i,
    };

    for (final entry in tocEntries) {
      if (!_isSkippableOpeningEntry(entry.label, entry.path)) {
        final index = chapterIndexByPath[entry.path];
        if (index != null) {
          return index;
        }
      }
    }

    for (var i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      if (!_isSkippableOpeningEntry(chapter.title, chapter.path)) {
        return i;
      }
    }

    return 0;
  }

  static bool _isSkippableOpeningEntry(String label, String path) {
    final combined = '${label.toLowerCase()} ${path.toLowerCase()}';
    final skipPatterns = <RegExp>[
      RegExp(r'\bcontents\b'),
      RegExp(r'\btable of contents\b'),
      RegExp(r'\btoc\b'),
      RegExp(r'\bnav\b'),
      RegExp(r'\bcover\b'),
      RegExp(r'\btitle page\b'),
      RegExp(r'\btitlepage\b'),
      RegExp(r'\bdedication\b'),
      RegExp(r'\bcopyright\b'),
      RegExp(r'\backnowledg'),
      RegExp(r'\bbibliograph'),
      RegExp(r'\bnotes\b'),
      RegExp(r'[/_-]toc([._/-]|$)'),
      RegExp(r'[/_-]nav([._/-]|$)'),
      RegExp(r'[/_-]cover([._/-]|$)'),
      RegExp(r'[/_-]titlepage([._/-]|$)'),
      RegExp(r'[/_-]ded([._/-]|$)'),
      RegExp(r'[/_-]cop([._/-]|$)'),
      RegExp(r'[/_-]fm\d*([._/-]|$)'),
      RegExp(r'[/_-]cvi([._/-]|$)'),
      RegExp(r'[/_-]tp([._/-]|$)'),
    ];

    for (final pattern in skipPatterns) {
      if (pattern.hasMatch(combined)) {
        return true;
      }
    }

    return false;
  }
}

class EpubChapter {
  const EpubChapter({
    required this.id,
    required this.path,
    required this.title,
    required this.html,
    this.primaryMedia,
  });

  final String id;
  final String path;
  final String title;
  final String html;
  final EpubChapterMedia? primaryMedia;
}

class EpubChapterMedia {
  const EpubChapterMedia({this.reference, this.inlineSvgMarkup, this.label})
    : assert(
        (reference != null && inlineSvgMarkup == null) ||
            (reference == null && inlineSvgMarkup != null),
        'Specify either a media reference or inline SVG markup.',
      );

  final String? reference;
  final String? inlineSvgMarkup;
  final String? label;

  bool get isInlineSvg => inlineSvgMarkup != null;
}

class EpubTocEntry {
  const EpubTocEntry({
    required this.label,
    required this.path,
    this.fragment,
    required this.depth,
  });

  final String label;
  final String path;
  final String? fragment;
  final int depth;
}

class EpubAsset {
  const EpubAsset({required this.path, required this.bytes, this.mediaType});

  final String path;
  final Uint8List bytes;
  final String? mediaType;
}

class ResolvedAsset {
  const ResolvedAsset({required this.path, required this.bytes, this.mimeType});

  final String path;
  final Uint8List bytes;
  final String? mimeType;

  bool get isSvg =>
      (mimeType?.contains('svg') ?? false) ||
      path.toLowerCase().endsWith('.svg');
}

class ResolvedLocation {
  const ResolvedLocation({
    required this.chapterIndex,
    required this.path,
    this.fragment,
  });

  final int chapterIndex;
  final String path;
  final String? fragment;
}

class _PreparedChapter {
  const _PreparedChapter(this.document, {this.primaryMedia});

  final html.Document document;
  final EpubChapterMedia? primaryMedia;
}

class _PackageData {
  const _PackageData({
    required this.title,
    required this.author,
    required this.manifest,
    required this.spineItemIds,
    required this.navPath,
    required this.ncxPath,
  });

  final String? title;
  final String? author;
  final Map<String, _ManifestItem> manifest;
  final List<String> spineItemIds;
  final String? navPath;
  final String? ncxPath;
}

class _ManifestItem {
  const _ManifestItem({
    required this.id,
    required this.href,
    required this.path,
    required this.mediaType,
    required this.properties,
  });

  final String id;
  final String href;
  final String path;
  final String? mediaType;
  final Set<String> properties;

  bool get isNavigationDocument => properties.contains('nav');

  bool get isHtmlDocument {
    final lowerPath = path.toLowerCase();
    final lowerType = mediaType?.toLowerCase();
    return lowerType == 'application/xhtml+xml' ||
        lowerType == 'text/html' ||
        lowerPath.endsWith('.xhtml') ||
        lowerPath.endsWith('.html') ||
        lowerPath.endsWith('.htm');
  }
}

class ResolvedReference {
  const ResolvedReference({required this.path, this.fragment});

  final String path;
  final String? fragment;

  String withFragment() {
    if (fragment == null || fragment!.isEmpty) {
      return path;
    }
    return '$path#$fragment';
  }
}

XmlDocument? tryParseXml(String source) {
  try {
    return XmlDocument.parse(source);
  } on XmlException {
    return null;
  }
}

ResolvedReference? resolveReference(String currentPath, String? href) {
  if (href == null) {
    return null;
  }

  final trimmed = href.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  if (isExternalReference(trimmed) || trimmed.startsWith('data:')) {
    return ResolvedReference(path: trimmed);
  }

  final hashIndex = trimmed.indexOf('#');
  final rawPath = hashIndex >= 0 ? trimmed.substring(0, hashIndex) : trimmed;
  final fragment = hashIndex >= 0 ? trimmed.substring(hashIndex + 1) : null;

  final normalizedPath = rawPath.isEmpty
      ? normalizeArchivePath(currentPath)
      : resolveArchivePath(currentPath, rawPath);

  return ResolvedReference(
    path: normalizedPath,
    fragment: fragment == null || fragment.isEmpty
        ? null
        : Uri.decodeComponent(fragment),
  );
}

String resolveArchivePath(String currentPath, String referencePath) {
  final decoded = Uri.decodeFull(referencePath.split('?').first);
  final baseDirectory = path.url.dirname(normalizeArchivePath(currentPath));
  return normalizeArchivePath(
    path.url.normalize(path.url.join(baseDirectory, decoded)),
  );
}

String normalizeArchivePath(String rawPath) {
  final sanitized = rawPath.replaceAll('\\', '/').trim();
  final segments = <String>[];
  for (final segment in sanitized.split('/')) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      if (segments.isNotEmpty) {
        segments.removeLast();
      }
      continue;
    }
    segments.add(Uri.decodeComponent(segment));
  }
  return segments.join('/');
}

String normalizeXhtmlForHtmlParser(String source) {
  return source.replaceAllMapped(
    RegExp(r'<(title|script|style|textarea)(\s[^>]*)?/>', caseSensitive: false),
    (match) => '<${match.group(1)}${match.group(2) ?? ''}></${match.group(1)}>',
  );
}

String? imageSourceFromAttributes(Map attributes) {
  final direct =
      attributeValue(attributes, 'src') ??
      attributeValue(attributes, 'data') ??
      attributeValue(attributes, 'href') ??
      attributeValue(attributes, 'xlink:href');
  if (direct != null && direct.trim().isNotEmpty) {
    return direct.trim();
  }

  final sourceSet = attributeValue(attributes, 'srcset');
  if (sourceSet == null || sourceSet.trim().isEmpty) {
    return null;
  }

  for (final candidate in sourceSet.split(',')) {
    final value = candidate.trim();
    if (value.isEmpty) {
      continue;
    }
    final reference = value.split(RegExp(r'\s+')).first.trim();
    if (reference.isNotEmpty) {
      return reference;
    }
  }

  return null;
}

String? attributeValue(Map attributes, String name) {
  final direct = attributes[name];
  if (direct is String) {
    return direct;
  }

  final lowerName = name.toLowerCase();
  for (final entry in attributes.entries) {
    if (entry.key.toString().toLowerCase() == lowerName &&
        entry.value is String) {
      return entry.value as String;
    }
  }

  return null;
}

EpubAsset? findEpubAsset(Map<String, EpubAsset> assets, String rawPath) {
  final normalized = normalizeArchivePath(rawPath);
  final direct = assets[normalized];
  if (direct != null) {
    return direct;
  }

  final lower = normalized.toLowerCase();
  for (final entry in assets.entries) {
    if (entry.key.toLowerCase() == lower) {
      return entry.value;
    }
  }

  final baseName = path.url.basename(normalized).toLowerCase();
  if (baseName.isEmpty) {
    return null;
  }

  EpubAsset? match;
  for (final entry in assets.entries) {
    if (path.url.basename(entry.key).toLowerCase() != baseName) {
      continue;
    }
    if (match != null) {
      return null;
    }
    match = entry.value;
  }
  return match;
}

bool isExternalReference(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      uri.hasScheme &&
      uri.scheme.isNotEmpty &&
      uri.scheme != 'file';
}

String decodeText(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }

  try {
    return utf8.decode(bytes, allowMalformed: true);
  } on FormatException {
    return latin1.decode(bytes, allowInvalid: true);
  }
}

ResolvedAsset? tryParseDataUri(String raw) {
  if (!raw.startsWith('data:')) {
    return null;
  }

  try {
    final data = UriData.parse(raw);
    return ResolvedAsset(
      path: raw,
      bytes: Uint8List.fromList(data.contentAsBytes()),
      mimeType: data.mimeType,
    );
  } on FormatException {
    return null;
  }
}

String buildDataUri({required Uint8List bytes, required String mimeType}) {
  final encoded = base64Encode(bytes);
  return 'data:$mimeType;base64,$encoded';
}

String guessMimeType(String pathValue) {
  final lower = pathValue.toLowerCase();
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

extension XmlElementAttributes on XmlElement {
  String? attributeByLocalName(String localName) {
    return attributes
        .firstWhereOrNull((attribute) => attribute.name.local == localName)
        ?.value;
  }
}

extension FirstWhereOrNullExtension<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T element) test) {
    for (final element in this) {
      if (test(element)) {
        return element;
      }
    }
    return null;
  }
}
