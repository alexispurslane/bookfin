// Tool code for the on-demand corpus run (BOOKFIN_EPUB_CORPUS=1). It is
// not part of Bookfin and nothing in lib/ uses it.
//
// The support report: whether a book uses anything outside the subset that
// the renderer lays out as Chromium does. The corpus run reports it.
//
// A feature counts only where a section uses it: an element of the
// section, or a style rule whose selector matches an element of the
// section. A rule that matches nothing changes nothing on the page.
import 'package:bookfin/reader/epub/css.dart';
import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/fonts.dart';
import 'package:bookfin/reader/epub/prepare.dart';

import 'book.dart';

/// What a book uses that the renderer does not lay out as Chromium does.
class SupportReport {
  /// Features that change the layout so much that the WebView reader would
  /// have opened the book, with the sections that use them.
  final Map<String, Set<int>> unsupported = {};

  /// Features that the renderer draws in a simpler way, which keeps the
  /// text and its order, with the sections that use them.
  final Map<String, Set<int>> approximated = {};

  int sections = 0;

  bool get supported => unsupported.isEmpty;

  /// The sections that use no unsupported feature.
  int get supportedSections =>
      sections -
      unsupported.values.fold(<int>{}, (all, some) => all..addAll(some)).length;
}

/// Checks every section of [book], styled for a page [width] by [height]
/// pixels.
SupportReport checkSupport(
  CorpusBook book, {
  double width = 412,
  double height = 671,
}) {
  final report = SupportReport()..sections = book.sections;
  final opf = String.fromCharCodes(
    book.publication.resources[book.publication.packagePath]!,
  );
  if (RegExp(r'page-progression-direction="rtl"').hasMatch(opf)) {
    report.unsupported['right-to-left page order'] = {
      for (var index = 0; index < book.sections; index++) index,
    };
  }
  final media = MediaContext(width: width, height: height);
  for (var index = 0; index < book.sections; index++) {
    final input = book.source(index);
    final dom = DomSection.parse(input.xhtml);
    final elements = elementsOf(dom.root).toList();
    void note(_Finding finding) =>
        (finding.unsupported ? report.unsupported : report.approximated)
            .putIfAbsent(finding.feature, () => {})
            .add(index);
    for (final sheet in sectionSheets(input, dom, media)) {
      // A face that BookFonts cannot register, such as WOFF 2, draws in
      // the reader font.
      for (final face in sheet.fontFaces) {
        final bytes = book.resource(face.path);
        if (bytes == null || sfntOf(bytes) == null) {
          note(const _Finding('embedded fonts drawn in the reader font'));
        }
      }
      for (final (rule, pseudo) in [
        for (final rule in sheet.rules) (rule, false),
        for (final rule in sheet.pseudoRules) (rule, true),
      ]) {
        final findings = _classify(
          rule.declarations,
          pseudo ? rule.selector.pseudoElement : null,
        );
        if (findings.isEmpty) continue;
        if (!elements.any(rule.selector.matches)) continue;
        findings.forEach(note);
      }
    }
    for (final element in elements) {
      _checkElement(element).forEach(note);
      final style = element.attributes['style'];
      if (style != null) {
        _classify(parseDeclarations(style), null).forEach(note);
      }
    }
  }
  return report;
}

class _Finding {
  const _Finding(this.feature, {this.unsupported = false});
  final String feature;
  final bool unsupported;
}

List<_Finding> _classify(List<Declaration> declarations, String? pseudo) {
  final values = <String, String>{
    for (final declaration in declarations)
      declaration.property: declaration.value.trim().toLowerCase(),
  };
  final found = <_Finding>[];
  if (pseudo != null) {
    if (pseudo == 'first-letter' || pseudo == 'first-line') {
      found.add(const _Finding('::first-letter and ::first-line'));
    }
    final content = values['content'];
    if ((pseudo == 'before' || pseudo == 'after') &&
        content != null &&
        !RegExp(r'''^(none|normal|""|'')$''').hasMatch(content)) {
      found.add(const _Finding('generated content'));
    }
    return found;
  }
  final position = values['position'];
  if (position == 'absolute' || position == 'fixed') {
    final offset = values['left'] ?? values['top'] ?? '';
    // Books move text that only screen readers need far off the page.
    found.add(
      offset.startsWith('-')
          ? const _Finding('text moved off the page is left out')
          : const _Finding('an absolute or fixed box drawn as a block'),
    );
  } else if (position == 'relative') {
    found.add(const _Finding('relative position offsets'));
  }
  final writing = values['writing-mode'] ?? values['-epub-writing-mode'];
  if (writing != null &&
      (writing.startsWith('vertical') || writing.startsWith('tb'))) {
    found.add(const _Finding('vertical writing', unsupported: true));
  }
  final columns = values['column-count'] ?? values['columns'];
  if (columns != null && columns != 'auto' && columns != '1') {
    found.add(const _Finding('multiple columns', unsupported: true));
  }
  final display = values['display'];
  if (display == 'flex' || display == 'inline-flex') {
    found.add(
      values['flex-direction'] == 'column'
          ? const _Finding('a flex column drawn as blocks')
          : const _Finding('a flex row drawn as blocks'),
    );
  } else if (display == 'grid' || display == 'inline-grid') {
    found.add(const _Finding('a grid drawn as blocks'));
  } else if (display != null && display.startsWith('table')) {
    found.add(const _Finding('display: table on a non-table drawn as a block'));
  } else if (display == 'inline-block') {
    found.add(const _Finding('inline-block drawn as a shrink-to-fit block'));
  }
  final float = values['float'];
  if (float == 'left' || float == 'right') {
    found.add(const _Finding('float drawn as a block'));
  }
  final vertical = values['vertical-align'];
  if (vertical != null &&
      !const {'baseline', 'super', 'sub'}.contains(vertical)) {
    found.add(const _Finding('vertical-align other than super and sub'));
  }
  if (values['hyphens'] == 'auto' || values['-webkit-hyphens'] == 'auto') {
    found.add(const _Finding('automatic hyphenation'));
  }
  final wrap = values['text-wrap'];
  if (wrap == 'pretty' || wrap == 'balance') {
    found.add(const _Finding('text-wrap: pretty or balance'));
  }
  if (values.containsKey('background-image') ||
      (values['background']?.contains('url(') ?? false)) {
    found.add(const _Finding('background images'));
  }
  if (values.containsKey('all')) {
    found.add(const _Finding('the all property'));
  }
  if (values['direction'] == 'rtl') {
    found.add(const _Finding('right-to-left text', unsupported: true));
  }
  return found;
}

List<_Finding> _checkElement(DomElement element) {
  final found = <_Finding>[];
  switch (element.name) {
    case 'td' || 'th' when (element.attributes['rowspan'] ?? '1') != '1':
      found.add(const _Finding('rowspan counted as 1'));
    case 'svg':
      found.add(const _Finding('inline SVG', unsupported: true));
    case 'math':
      found.add(const _Finding('MathML', unsupported: true));
    case 'ruby':
      found.add(const _Finding('ruby annotations', unsupported: true));
    case 'video' || 'audio' || 'canvas' || 'iframe' || 'object' || 'embed':
      found.add(const _Finding('media or embedded content', unsupported: true));
    case 'img'
        when (element.attributes['src'] ?? '').toLowerCase().endsWith('.svg'):
      found.add(const _Finding('SVG images drawn as outlines'));
  }
  if (element.attributes['dir'] == 'rtl') {
    found.add(const _Finding('right-to-left text', unsupported: true));
  }
  return found;
}
