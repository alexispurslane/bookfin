// The survey of a PDF that Bookfin keeps beside its download (tb-lnak).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../downloads/derived_files.dart';
import '../downloads/downloads.dart';
import '../foundation/hop.dart';
import 'book_crop.dart';
import 'running_lines.dart';

/// What the survey of a book keeps: every page that it surveyed, and the
/// book profile once it froze.
typedef KeptSurvey = ({List<SurveyedPage> pages, BookProfile? profile});

/// Lends the download of the open book to [use] while Downloads owns it:
/// [owned] says whether it still does. It does not call [use] when the
/// download cannot be read.
typedef SurveyLease = Future<void> Function(
  Future<void> Function(VerifiedFile original, bool Function() owned) use,
);

/// Makes the kept survey of the book whose PDF has the SHA-256 [book], in
/// the download that [lease] lends. [SurveyFiles.new] is one.
typedef SurveyStoreOf = SurveyFiles Function(
  SurveyLease lease, {
  required String book,
  IsolateHop hop,
});

/// The survey of one book that Bookfin keeps with its download.
///
/// The survey is the file `survey` in the download's survey directory
/// ([DerivedBookFiles.surveyDirectory]), so removing the download removes
/// it. It is UTF-8 JSON:
///
/// - `format`: [format]. `book`: the SHA-256 of the PDF. A survey of
///   another format or another book reads as absent, and the next write
///   replaces it.
/// - `pages`: for each surveyed page, a list: its source page number, its
///   height and body line height in page units, 1 for a body page or 0,
///   its core box (left, top, right and bottom) or null, and its edge
///   lines. An edge line is a list: its line index, its box, its gap or
///   null for none, and its text or null.
/// - `profile`: null until the book profile froze. Then an object:
///   `lineHeight`, `texts` (a signature and a box for each), `folios`,
///   `shapes` (a side and a box for each), and `boxes`, the box of each side
///   or null.
///
/// Encoding and decoding run through the hop. A survey of a 400-page book
/// takes about 100 KB.
class SurveyFiles {
  /// The kept survey of the book whose PDF has the SHA-256 [book], in the
  /// download that [lease] lends. [hop] encodes and decodes it.
  SurveyFiles(this._lease, {required this.book, this.hop = compute});

  /// The format of the file. A change of the page analysis, the content
  /// rule or the file's shape needs a new format, so that older surveys
  /// read as absent and the survey runs again.
  static const format = 1;

  final SurveyLease _lease;
  final String book;
  final IsolateHop hop;

  /// Whether a [read] reached the download, so that a write cannot replace
  /// a survey that this store did not read.
  bool _reached = false;

  /// The kept survey, or null when none is kept for this book.
  ///
  /// A survey that cannot be read is renamed to `survey.unreadable`, which
  /// replaces the one before it, and reported to Flutter's error handler.
  /// It reads as absent, so the survey runs again. Null too when the
  /// download cannot be read or now holds another PDF. Then [write] keeps
  /// nothing.
  Future<KeptSurvey?> read() async {
    KeptSurvey? kept;
    await _lease((original, owned) async {
      final file = _fileOf(original);
      if (file == null || !owned()) return;
      try {
        switch (await FileSystemEntity.type(file.path, followLinks: false)) {
          case FileSystemEntityType.notFound:
            _reached = true;
            return;
          case FileSystemEntityType.file:
            break;
          default:
            return;
        }
        final bytes = await file.readAsBytes();
        try {
          kept = await hop(_decode, (book: book, bytes: bytes));
          _reached = true;
        } on FormatException catch (error, stack) {
          await file.rename('${file.path}.unreadable');
          _reached = true;
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'bookfin reader',
              context: ErrorDescription(
                'while reading the kept survey of a PDF. It was kept aside '
                'as ${file.path}.unreadable, and the survey runs again',
              ),
            ),
          );
        }
      } on FileSystemException {
        // The survey runs without its kept pages, and keeps nothing.
      }
    });
    return kept;
  }

  /// Keeps [survey] in place of the survey before it, once a [read] reached
  /// the download. The write is [DerivedBookFiles.write], so a process that
  /// dies during it leaves the old survey or the new one whole. A survey
  /// that cannot be written costs survey work at the next open, so the
  /// write does not fail.
  Future<void> write(KeptSurvey survey) async {
    if (!_reached) return;
    final bytes = await hop(_encode, (book: book, survey: survey));
    await _lease((original, owned) async {
      final file = _fileOf(original);
      if (file == null || !owned()) return;
      try {
        await DerivedBookFiles.write(file, bytes);
      } on FileSystemException {
        // The next batch, or the next open, tries again.
      }
    });
  }

  /// The survey's file in the download [original], or null when the
  /// download now holds another PDF than the open book.
  File? _fileOf(VerifiedFile original) {
    if (original.digest != book || original.uri.scheme != 'file') return null;
    final directory = DerivedBookFiles.surveyDirectory(
      File.fromUri(original.uri),
    );
    return File('${directory.path}/survey');
  }
}

/// The file bytes of [kept]'s survey (see [SurveyFiles]). It runs in a hop.
Uint8List _encode(({String book, KeptSurvey survey}) kept) {
  List<double> box(PageBox box) => [box.left, box.top, box.right, box.bottom];
  final profile = kept.survey.profile;
  final templates = profile?.templates;
  return utf8.encode(
    jsonEncode({
      'format': SurveyFiles.format,
      'book': kept.book,
      'pages': [
        for (final page in kept.survey.pages)
          [
            page.sourcePage,
            page.height,
            page.edges.bodyLineHeight,
            page.body ? 1 : 0,
            page.core == null ? null : box(page.core!),
            [
              for (final edge in page.edges.edges)
                [
                  edge.line,
                  ...box(edge.box),
                  edge.gap.isFinite ? edge.gap : null,
                  edge.text,
                ],
            ],
          ],
      ],
      'profile': profile == null
          ? null
          : {
              'lineHeight': templates!.lineHeight,
              'texts': [
                for (final text in templates.texts)
                  [text.signature, ...box(text.box)],
              ],
              'folios': templates.folioOffsets,
              'shapes': [
                for (final shape in templates.shapes)
                  [shape.side, ...box(shape.box)],
              ],
              'boxes': [
                for (final side in profile.boxes)
                  side == null ? null : box(side),
              ],
            },
    }),
  );
}

/// The survey that the file [kept] holds for its book, or null when it is a
/// survey of another format or another book. Throws a [FormatException]
/// when the file is not a survey. It runs in a hop.
KeptSurvey? _decode(({String book, Uint8List bytes}) kept) {
  final Object? value;
  try {
    value = jsonDecode(utf8.decode(kept.bytes));
  } on FormatException {
    rethrow;
  }
  final file = _map(value);
  if (file['format'] != SurveyFiles.format || file['book'] != kept.book) {
    return null;
  }
  final pages = <SurveyedPage>[];
  for (final entry in _list(file['pages'])) {
    final page = _list(entry);
    if (page.length != 6) throw const FormatException('Not a surveyed page.');
    pages.add(
      SurveyedPage(
        edges: (
          sourcePage: _int(page[0]),
          bodyLineHeight: _double(page[2]),
          body: _int(page[3]) == 1,
          edges: [
            for (final value in _list(page[5]))
              switch (_list(value)) {
                [final line, _, _, _, _, final gap, final text]
                    when text == null || text is String =>
                  (
                    line: _int(line),
                    box: _box(_list(value).sublist(1, 5)),
                    gap: gap == null ? double.infinity : _double(gap),
                    text: text as String?,
                  ),
                _ => throw const FormatException('Not an edge line.'),
              },
          ],
        ),
        height: _double(page[1]),
        core: page[4] == null ? null : _box(_list(page[4])),
      ),
    );
  }
  final profile = file['profile'];
  return (
    pages: pages,
    profile: profile == null ? null : _profile(_map(profile)),
  );
}

BookProfile _profile(Map<String, Object?> value) {
  final boxes = [
    for (final side in _list(value['boxes']))
      side == null ? null : _box(_list(side)),
  ];
  if (boxes.length != 2) throw const FormatException('A book has two sides.');
  return BookProfile(
    templates: RunningTemplates(
      lineHeight: _double(value['lineHeight']),
      texts: [
        for (final text in _list(value['texts']))
          switch (_list(text)) {
            [final String signature, _, _, _, _] => (
              signature: signature,
              box: _box(_list(text).sublist(1)),
            ),
            _ => throw const FormatException('Not a text template.'),
          },
      ],
      folioOffsets: [for (final offset in _list(value['folios'])) _int(offset)],
      shapes: [
        for (final shape in _list(value['shapes']))
          switch (_list(shape)) {
            [final side, _, _, _, _] => (
              side: _int(side),
              box: _box(_list(shape).sublist(1)),
            ),
            _ => throw const FormatException('Not a shape template.'),
          },
      ],
    ),
    boxes: boxes,
  );
}

PageBox _box(List<Object?> value) {
  if (value.length != 4) throw const FormatException('Not a box.');
  return (
    left: _double(value[0]),
    top: _double(value[1]),
    right: _double(value[2]),
    bottom: _double(value[3]),
  );
}

Map<String, Object?> _map(Object? value) => value is Map<String, Object?>
    ? value
    : throw const FormatException('Not an object.');

List<Object?> _list(Object? value) =>
    value is List<Object?> ? value : throw const FormatException('Not a list.');

int _int(Object? value) =>
    value is int ? value : throw const FormatException('Not a whole number.');

double _double(Object? value) => value is num && value.isFinite
    ? value.toDouble()
    : throw const FormatException('Not a number.');
