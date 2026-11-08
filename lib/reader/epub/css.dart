// The CSS subset of the EPUB renderer: style sheet parsing, selector
// matching, and the cascade that gives each element its computed style.
//
// The parser is the safety boundary for a book's style sheets. It resolves
// `url()` and `@import` only to files in the publication and reads nothing
// else, and it limits the rules, selector length, nesting and import depth
// of each sheet. It runs in the prepare worker, so a slow sheet cannot stall
// a frame.
//
// The cascade follows the order that Chromium uses for a page of the
// WebView reader: the user agent's sheet, then the book's sheets and the
// reader's own rules in document order, then style attributes, then
// important declarations. Unknown properties and values are left out, as a
// browser leaves them out.
import 'dart:math' as math;

import 'dom.dart';

/// A length as the cascade leaves it. Font-relative units are already
/// pixels. A percentage resolves against the containing block's width
/// during layout.
class Length {
  const Length.px(this.value) : unit = LengthUnit.px;
  const Length.percent(this.value) : unit = LengthUnit.percent;
  const Length.auto() : value = 0, unit = LengthUnit.auto;
  const Length.none() : value = 0, unit = LengthUnit.none;
  final double value;
  final LengthUnit unit;

  bool get isAuto => unit == LengthUnit.auto;
  bool get isNone => unit == LengthUnit.none;

  /// The length in pixels inside a containing block [base] pixels wide.
  /// Auto and none are zero.
  double resolve(double base) => switch (unit) {
    LengthUnit.px => value,
    LengthUnit.percent => value * base / 100,
    _ => 0,
  };

  /// The length in pixels, or null when it is auto or none.
  double? resolveOrNull(double base) =>
      unit == LengthUnit.auto || unit == LengthUnit.none ? null : resolve(base);
}

enum LengthUnit { px, percent, auto, none }

enum Display { none, block, inline, listItem, inlineBlock }

enum Align { start, end, left, right, center, justify }

enum WhiteSpace { normal, pre, preWrap, preLine, nowrap }

enum VerticalAlign { baseline, superscript, subscript, top, middle, bottom }

enum Transform { none, upper, lower, capitalize }

/// The `hyphens` property: whether a line may break inside a word with a
/// hyphen. `manual` breaks only at the book's own soft hyphens.
enum Hyphens { none, manual, auto }

/// The computed style of one element.
class Style {
  Style._();

  /// The initial style, which the root element inherits from.
  factory Style.initial() => Style._();

  Display display = Display.inline;

  /// Whether the box is a flex or grid container. Each of its children then
  /// lays out as a block, as a flex or grid item is blockified.
  bool flexOrGrid = false;
  bool floated = false;
  String position = 'static';

  /// The `left` and `top` offsets of a positioned box.
  Length left = const Length.auto();
  Length top = const Length.auto();

  /// Whether the box is placed absolutely or fixed and moved off the page
  /// by a negative left or top offset. Books move text that only screen
  /// readers need that way.
  bool get movedOffPage =>
      (position == 'absolute' || position == 'fixed') &&
      (left.value < 0 || top.value < 0);
  List<Length> margin = const [
    Length.px(0),
    Length.px(0),
    Length.px(0),
    Length.px(0),
  ];
  List<Length> padding = const [
    Length.px(0),
    Length.px(0),
    Length.px(0),
    Length.px(0),
  ];

  /// Each side's border width in pixels and whether its style draws it,
  /// from top to left. A side whose style is none has no used width.
  List<double> borderWidth = const [3, 3, 3, 3];
  List<bool> borderVisible = const [false, false, false, false];
  double usedBorder(int side) => borderVisible[side] ? borderWidth[side] : 0;
  Length width = const Length.auto();
  Length maxWidth = const Length.none();
  Length height = const Length.auto();
  Length maxHeight = const Length.none();
  bool borderBox = false;
  BreakRule breakBefore = BreakRule.auto;
  BreakRule breakAfter = BreakRule.auto;
  bool avoidBreakInside = false;

  // Inherited properties.
  Length textIndent = const Length.px(0);
  Align textAlign = Align.start;
  int fontWeight = 400;
  bool italic = false;
  List<String> fontFamily = const ['serif'];
  double fontSize = 16;
  bool smallCaps = false;
  bool oldstyleFigures = false;

  /// The line height: a factor of [fontSize] when [lineHeightFactor] is
  /// true, pixels otherwise, or null for `normal`.
  double? lineHeight;
  bool lineHeightFactor = false;
  double letterSpacing = 0;
  double wordSpacing = 0;
  Transform transform = Transform.none;
  WhiteSpace whiteSpace = WhiteSpace.normal;
  Hyphens hyphens = Hyphens.manual;

  /// The element's language, a BCP 47 tag such as `en-GB`: that of its
  /// [languageAttribute], or else of its parent. Null when no element up
  /// to the root names one, and empty when the nearest names an unknown
  /// language.
  String? language;
  bool underline = false;
  bool lineThrough = false;
  String listStyleType = 'disc';
  bool listStyleInside = false;
  int orphans = 2;
  int widows = 2;

  /// A table's `border-spacing` in pixels: across, between its columns,
  /// and down, between its rows.
  (double, double) borderSpacing = (0, 0);

  /// Whether a table's borders collapse (`border-collapse: collapse`): two
  /// cells that touch share one border.
  bool collapseBorders = false;
  VerticalAlign verticalAlign = VerticalAlign.baseline;

  /// The line height in pixels, or null for `normal`.
  double? get lineHeightPx => lineHeight == null
      ? null
      : lineHeightFactor
      ? lineHeight! * fontSize
      : lineHeight;

  Style inherit() => Style._()
    ..textIndent = textIndent
    ..textAlign = textAlign
    ..fontWeight = fontWeight
    ..italic = italic
    ..fontFamily = fontFamily
    ..fontSize = fontSize
    ..smallCaps = smallCaps
    ..oldstyleFigures = oldstyleFigures
    ..lineHeight = lineHeight
    ..lineHeightFactor = lineHeightFactor
    ..letterSpacing = letterSpacing
    ..wordSpacing = wordSpacing
    ..transform = transform
    ..whiteSpace = whiteSpace
    ..hyphens = hyphens
    ..language = language
    // Text decorations are not inherited, but they draw across every
    // descendant's text, which comes to the same here.
    ..underline = underline
    ..lineThrough = lineThrough
    ..listStyleType = listStyleType
    ..listStyleInside = listStyleInside
    ..orphans = orphans
    ..widows = widows
    ..borderSpacing = borderSpacing
    ..collapseBorders = collapseBorders;
}

enum BreakRule { auto, page, avoid }

/// One declaration of a rule, such as `margin-top: 1em`.
class Declaration {
  const Declaration(this.property, this.value, this.important);
  final String property;
  final String value;
  final bool important;
}

/// A style rule with one selector. A rule with a selector list becomes one
/// rule per selector.
class StyleRule {
  StyleRule(this.selector, this.declarations, this.order);
  final Selector selector;
  final List<Declaration> declarations;

  /// The rule's place in the cascade: the order of sheets, then of rules.
  final int order;
}

/// One `@font-face` rule: a font file of the publication and the family,
/// weight and style that it draws.
class FontFaceRule {
  const FontFaceRule({
    required this.family,
    required this.path,
    this.weight = 400,
    this.italic = false,
  });

  /// The family that the rule declares, in lower case, because CSS matches
  /// family names without regard to case.
  final String family;

  /// The publication path of the font file.
  final String path;

  /// The CSS font weight that the face draws, from 100 to 900.
  final int weight;
  final bool italic;

  /// The family that the face registers under in the book whose faces carry
  /// [prefix] (`SectionSource.fontPrefix`).
  String familyIn(String prefix) => '$prefix-$family';

  @override
  bool operator ==(Object other) =>
      other is FontFaceRule &&
      other.family == family &&
      other.path == path &&
      other.weight == weight &&
      other.italic == italic;

  @override
  int get hashCode => Object.hash(family, path, weight, italic);

  @override
  String toString() =>
      'FontFaceRule($family, $path, $weight${italic ? ', italic' : ''})';
}

/// A parsed style sheet.
class StyleSheet {
  StyleSheet._(this.rules, this.pseudoRules, this.fontFaces);

  /// Parses [css], the text of the file at publication [path]. `url()` and
  /// `@import` resolve against [path] and only to publication paths, so
  /// with a null [path] they resolve to nothing. [read] gives the CSS text
  /// of an imported sheet's path, or null. The [order] of the rules starts
  /// at [firstOrder]. [media] decides `@media` conditions and imports.
  ///
  /// Imports reach [maxImportDepth] sheets deep, and no sheet is read
  /// twice. A sheet past [maxSheetRules], [maxSelectorLength] or
  /// [maxNesting] keeps the rules before that point.
  factory StyleSheet.parse(
    String css, {
    String? path,
    String? Function(String path)? read,
    int firstOrder = 0,
    MediaContext media = const MediaContext(),
  }) {
    final output = _Output(firstOrder, media, read ?? (_) => null);
    if (path != null) output.readPaths.add(path);
    _SheetParser(css, path, 0, output).parseSheet();
    return StyleSheet._(output.rules, output.pseudoRules, output.fontFaces);
  }

  /// The rules that style elements.
  final List<StyleRule> rules;

  /// The rules that style pseudo-elements, such as `p::first-letter`,
  /// which the renderer does not draw. Their selectors match the
  /// element that the pseudo-element belongs to.
  final List<StyleRule> pseudoRules;

  /// The `@font-face` rules that apply.
  final List<FontFaceRule> fontFaces;
}

/// What `@media` conditions see.
class MediaContext {
  const MediaContext({this.width = 412, this.height = 671, this.night = false});
  final double width;
  final double height;

  /// Whether the page uses the night colors.
  final bool night;

  bool matches(String query) {
    for (final part in query.split(',')) {
      if (_matchesOne(part.trim().toLowerCase())) return true;
    }
    return false;
  }

  bool _matchesOne(String query) {
    var negate = false;
    var rest = query;
    if (rest.startsWith('not ')) {
      negate = true;
      rest = rest.substring(4).trim();
    } else if (rest.startsWith('only ')) {
      rest = rest.substring(5).trim();
    }
    var result = true;
    for (final term in rest.split(RegExp(r'\s+and\s+'))) {
      final condition = term.trim();
      if (condition.isEmpty) continue;
      if (!condition.startsWith('(')) {
        if (condition != 'all' && condition != 'screen') result = false;
        continue;
      }
      final inner = condition.substring(1, condition.length - 1).trim();
      final colon = inner.indexOf(':');
      final name = colon < 0 ? inner : inner.substring(0, colon).trim();
      final value = colon < 0 ? null : inner.substring(colon + 1).trim();
      final number = value == null
          ? null
          : double.tryParse(value.replaceAll(RegExp(r'[a-z]+$'), ''));
      result &= switch (name) {
        'prefers-color-scheme' =>
          value == null || value == (night ? 'dark' : 'light'),
        'color' => true,
        'min-width' => number != null && width >= number,
        'max-width' => number != null && width <= number,
        'min-height' => number != null && height >= number,
        'max-height' => number != null && height <= number,
        'orientation' => value == (height >= width ? 'portrait' : 'landscape'),
        _ => false,
      };
    }
    return negate ? !result : result;
  }
}

/// The most style rules that one sheet keeps, one for each selector of a
/// selector list.
const maxSheetRules = 20000;

/// The longest selector of a selector list, in characters.
const maxSelectorLength = 1024;

/// The most blocks inside each other, counting a style rule's own block.
const maxNesting = 32;

/// How many sheets deep imports reach below a linked sheet.
const maxImportDepth = 4;

/// What every sheet of one parse adds to: the rules and font faces in
/// cascade order, the next order, and the paths of the sheets read.
class _Output {
  _Output(this.order, this.media, this.textOf);
  int order;
  final MediaContext media;

  /// The CSS text of the sheet at a publication path, or null.
  final String? Function(String path) textOf;
  final rules = <StyleRule>[];
  final pseudoRules = <StyleRule>[];
  final fontFaces = <FontFaceRule>[];
  final readPaths = <String>{};
}

class _SheetParser {
  _SheetParser(String css, this.path, this.depth, this.output)
    : text = css.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  final String text;

  /// The sheet's publication path, which its references resolve against.
  final String? path;

  /// How many imports lead to this sheet: 0 for a linked sheet.
  final int depth;
  final _Output output;
  int index = 0;

  /// The style rules that this sheet kept, without its imports.
  var _kept = 0;

  /// Whether the sheet passed a limit, which ends it.
  var _ended = false;

  /// Whether an `@import` here still counts. Like Chromium, an import counts
  /// only before every rule other than `@charset`, `@layer` and imports.
  var _importsCount = true;

  void parseSheet() => parseRules(text.length, true, 0);

  void _end() {
    _ended = true;
    index = text.length;
  }

  /// Parses rules up to [end] inside [nesting] blocks. Rules inside a
  /// condition that does not hold are read but not kept when [apply] is
  /// false.
  void parseRules(int end, bool apply, int nesting) {
    while (!_ended) {
      _skipSpace(end);
      if (index >= end) return;
      if (text.codeUnitAt(index) == 0x40 /* @ */ ) {
        _atRule(end, apply, nesting);
        continue;
      }
      _importsCount = false;
      final open = text.indexOf('{', index);
      if (open < 0 || open >= end) {
        index = end;
        return;
      }
      final prelude = text.substring(index, open).trim();
      if (nesting + 1 > maxNesting ||
          _splitTop(
            prelude,
            ',',
          ).any((part) => part.trim().length > maxSelectorLength)) {
        return _end();
      }
      final close = _matching(open);
      final body = text.substring(open + 1, close);
      index = close + 1;
      final selectors = Selector.parseList(prelude);
      if (selectors == null || !apply) continue;
      if (_kept + selectors.length > maxSheetRules) return _end();
      _kept += selectors.length;
      final declarations = parseDeclarations(body);
      final number = output.order++;
      for (final selector in selectors) {
        (selector.pseudoElement == null ? output.rules : output.pseudoRules)
            .add(StyleRule(selector, declarations, number));
      }
    }
  }

  void _atRule(int end, bool apply, int nesting) {
    final match = RegExp(r'@([a-zA-Z-]+)').matchAsPrefix(text, index);
    final name = match?.group(1)?.toLowerCase() ?? '';
    index = match?.end ?? index + 1;
    final boundary = _boundary(end);
    if (boundary >= end || text.codeUnitAt(boundary) == 0x3b /* ; */ ) {
      final prelude = text.substring(index, boundary).trim();
      index = boundary >= end ? end : boundary + 1;
      if (name == 'import') {
        if (_importsCount) _import(prelude);
      } else if (name != 'charset' && name != 'layer') {
        _importsCount = false;
      }
      return;
    }
    _importsCount = false;
    final open = boundary;
    final prelude = text.substring(index, open).trim();
    final close = _matching(open);
    switch (name) {
      case 'media' || 'supports':
        if (nesting + 1 > maxNesting) return _end();
        index = open + 1;
        // Chromium supports every @supports condition that books test.
        parseRules(
          close,
          apply && (name == 'supports' || output.media.matches(prelude)),
          nesting + 1,
        );
        if (_ended) return;
      case 'font-face':
        if (apply) _fontFace(text.substring(open + 1, close));
      default:
        break;
    }
    index = close + 1;
  }

  /// Parses the sheet that an `@import` with [prelude] names, in place.
  void _import(String prelude) {
    if (depth >= maxImportDepth) return;
    if (_reference(prelude) case (final reference, final media)) {
      final target = _resolve(reference);
      if (target == null) return;
      if (media.isNotEmpty && !output.media.matches(media)) return;
      if (!output.readPaths.add(target)) return;
      final css = output.textOf(target);
      if (css == null) return;
      _SheetParser(css, target, depth + 1, output).parseSheet();
    }
  }

  void _fontFace(String body) {
    String? family;
    String? file;
    var weight = 400;
    var italic = false;
    for (final declaration in parseDeclarations(body)) {
      final value = declaration.value.trim();
      final lower = value.toLowerCase();
      switch (declaration.property) {
        case 'font-family':
          family = lower.replaceAll(RegExp(r'''^["']|["']$'''), '').trim();
        case 'src':
          file = _fontFile(value);
        case 'font-weight':
          // A variable face names a range. Its first weight stands for it.
          weight = switch (_tokens(lower).firstOrNull) {
            'bold' => 700,
            final token? => int.tryParse(token) ?? 400,
            null => 400,
          };
        case 'font-style':
          italic = lower.startsWith('italic') || lower.startsWith('oblique');
      }
    }
    if (family == null || family.isEmpty || file == null) return;
    output.fontFaces.add(
      FontFaceRule(family: family, path: file, weight: weight, italic: italic),
    );
  }

  /// The publication path of the first source in the `src` [value] that the
  /// renderer can read, as Chromium takes the first source that it
  /// supports. WOFF 2, EOT and SVG fonts are not read.
  String? _fontFile(String value) {
    for (final part in _splitTop(value, ',')) {
      final source = part.trim();
      if (!source.toLowerCase().startsWith('url(')) continue;
      if (_reference(source) case (final reference, final hints)) {
        final format = RegExp(r'''format\(\s*["']?([^"')\s]+)''')
            .firstMatch(hints.toLowerCase())
            ?.group(1);
        final readable = format == null
            ? !RegExp(
                r'\.(woff2|eot|svgz?)$',
                caseSensitive: false,
              ).hasMatch(reference.split('#').first)
            : _readableFormats.contains(format);
        if (!readable) continue;
        if (_resolve(reference) case final target?) return target;
      }
    }
    return null;
  }

  String? _resolve(String reference) {
    final base = path;
    return base == null ? null : resolvePath(base, reference);
  }

  /// The index of the first `;` or `{` from [index] on that is outside
  /// strings and parentheses, or [end].
  int _boundary(int end) {
    var depth = 0;
    for (var cursor = index; cursor < end; cursor++) {
      final unit = text.codeUnitAt(cursor);
      if (unit == 0x22 || unit == 0x27) {
        final close = text.indexOf(String.fromCharCode(unit), cursor + 1);
        if (close < 0 || close >= end) return end;
        cursor = close;
      } else if (unit == 0x28) {
        depth++;
      } else if (unit == 0x29) {
        if (depth > 0) depth--;
      } else if (depth == 0 && (unit == 0x3b || unit == 0x7b)) {
        return cursor;
      }
    }
    return end;
  }

  int _matching(int open) {
    var depth = 0;
    for (var cursor = open; cursor < text.length; cursor++) {
      final unit = text.codeUnitAt(cursor);
      if (unit == 0x22 || unit == 0x27) {
        final close = text.indexOf(String.fromCharCode(unit), cursor + 1);
        if (close < 0) return text.length;
        cursor = close;
      } else if (unit == 0x7b) {
        depth++;
      } else if (unit == 0x7d) {
        depth--;
        if (depth == 0) return cursor;
      }
    }
    return text.length;
  }

  void _skipSpace(int end) {
    while (index < end) {
      final unit = text.codeUnitAt(index);
      // `<!--` and `-->` may wrap a sheet in old books.
      if (isSpace(unit) || unit == 0x3b) {
        index++;
      } else if (text.startsWith('<!--', index)) {
        index += 4;
      } else if (text.startsWith('-->', index)) {
        index += 3;
      } else {
        return;
      }
    }
  }
}

const _readableFormats = {
  'woff',
  'truetype',
  'opentype',
  'woff-variations',
  'truetype-variations',
  'opentype-variations',
};

/// The reference at the start of [text], a `url()` or a string, and the
/// text after it, or null.
(String, String)? _reference(String text) {
  final match = RegExp(
    r'''^(?:url\(\s*(?:"([^"]*)"|'([^']*)'|([^)\s"']*))\s*\)|"([^"]*)"|'([^']*)')''',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return null;
  final reference = [
    for (var group = 1; group <= 5; group++) match.group(group),
  ].nonNulls.first;
  return (reference.trim(), text.substring(match.end).trim());
}

/// The publication path that [reference] in the file at [base] names, or
/// null when it leaves the publication.
String? resolvePath(String base, String reference) {
  if (reference.isEmpty || reference.contains(':')) return null;
  final path = Uri.decodeComponent(reference.split('#').first);
  final parts = base.split('/')..removeLast();
  for (final part in path.split('/')) {
    if (part == '.' || part.isEmpty) continue;
    if (part == '..') {
      if (parts.isEmpty) return null;
      parts.removeLast();
    } else {
      parts.add(part);
    }
  }
  return parts.join('/');
}

/// The declarations of a rule's body or of a style attribute.
List<Declaration> parseDeclarations(String body) {
  final result = <Declaration>[];
  var depth = 0;
  var start = 0;
  String? quote;
  void take(int end) {
    final part = body.substring(start, end);
    final colon = part.indexOf(':');
    if (colon > 0) {
      final property = part.substring(0, colon).trim().toLowerCase();
      var value = part.substring(colon + 1).trim();
      final important = RegExp(
        r'!\s*important$',
        caseSensitive: false,
      ).hasMatch(value);
      if (important) value = value.substring(0, value.lastIndexOf('!')).trim();
      if (property.isNotEmpty && value.isNotEmpty) {
        result.add(Declaration(property, value, important));
      }
    }
    start = end + 1;
  }

  for (var cursor = 0; cursor < body.length; cursor++) {
    final character = body[cursor];
    if (quote != null) {
      if (character == quote) quote = null;
    } else if (character == '"' || character == "'") {
      quote = character;
    } else if (character == '(') {
      depth++;
    } else if (character == ')') {
      depth--;
    } else if (character == ';' && depth == 0) {
      take(cursor);
    }
  }
  take(body.length);
  return result;
}

enum Combinator { descendant, child, adjacent, sibling }

/// A complex selector, such as `section > h2 + p`.
class Selector {
  Selector(this.compounds, this.combinators, this.pseudoElement);

  /// The compounds from left to right. [combinators] has one fewer entry.
  final List<Compound> compounds;
  final List<Combinator> combinators;
  final String? pseudoElement;

  /// The selector's specificity as one number: ids, then classes,
  /// attributes and pseudo-classes, then types.
  late final int specificity = compounds.fold(
    pseudoElement == null ? 0 : 1,
    (total, compound) => total + compound.specificity,
  );

  /// Parses a selector list, or returns null when one of its selectors is
  /// invalid, which makes a browser drop the whole rule.
  static List<Selector>? parseList(String text) {
    final result = <Selector>[];
    for (final part in _splitTop(text, ',')) {
      final selector = _SelectorParser(part.trim()).parse();
      if (selector == null) return null;
      result.add(selector);
    }
    return result.isEmpty ? null : result;
  }

  bool matches(DomElement element) =>
      _matchesFrom(element, compounds.length - 1);

  bool _matchesFrom(DomElement element, int index) {
    if (!compounds[index].matches(element)) return false;
    if (index == 0) return true;
    switch (combinators[index - 1]) {
      case Combinator.child:
        final parent = element.parent;
        return parent != null && _matchesFrom(parent, index - 1);
      case Combinator.descendant:
        for (var parent = element.parent; parent != null;) {
          if (_matchesFrom(parent, index - 1)) return true;
          parent = parent.parent;
        }
        return false;
      case Combinator.adjacent:
        final previous = _previousElement(element);
        return previous != null && _matchesFrom(previous, index - 1);
      case Combinator.sibling:
        for (var previous = _previousElement(element); previous != null;) {
          if (_matchesFrom(previous, index - 1)) return true;
          previous = _previousElement(previous);
        }
        return false;
    }
  }
}

DomElement? _previousElement(DomElement element) {
  final parent = element.parent;
  if (parent == null || element.elementIndex == 0) return null;
  return parent.elements[element.elementIndex - 1];
}

List<String> _splitTop(String text, String separator) {
  final parts = <String>[];
  var depth = 0;
  var start = 0;
  for (var cursor = 0; cursor < text.length; cursor++) {
    final character = text[cursor];
    if (character == '(' || character == '[') depth++;
    if (character == ')' || character == ']') depth--;
    if (character == separator && depth == 0) {
      parts.add(text.substring(start, cursor));
      start = cursor + 1;
    }
  }
  parts.add(text.substring(start));
  return parts;
}

/// A compound selector, such as `p.first-child:not(.x)`.
class Compound {
  String? tag;
  String? id;
  final classes = <String>[];
  final attributes = <_AttributeTest>[];
  final pseudoClasses = <_PseudoClass>[];

  int get specificity =>
      (id == null ? 0 : 10000) +
      100 * (classes.length + attributes.length) +
      pseudoClasses.fold<int>(
        0,
        (total, pseudo) => total + pseudo.specificity,
      ) +
      (tag == null ? 0 : 1);

  bool matches(DomElement element) {
    if (tag != null && tag != element.name) return false;
    if (id != null && element.id != id) return false;
    for (final name in classes) {
      if (!element.classes.contains(name)) return false;
    }
    for (final test in attributes) {
      if (!test.matches(element)) return false;
    }
    for (final pseudo in pseudoClasses) {
      if (!pseudo.matches(element)) return false;
    }
    return true;
  }
}

class _AttributeTest {
  _AttributeTest(
    this.name,
    this.operator,
    this.value, {
    this.anyPrefix = false,
  });
  final String name;
  final String? operator;
  final String value;
  final bool anyPrefix;

  bool matches(DomElement element) {
    final String? actual;
    if (anyPrefix) {
      actual = element.attributes.entries
          .where((entry) => entry.key == name || entry.key.endsWith(':$name'))
          .firstOrNull
          ?.value;
    } else {
      actual = element.attributes[name];
    }
    if (actual == null) return false;
    return switch (operator) {
      null => true,
      '=' => actual == value,
      '~=' => actual.split(RegExp(r'\s+')).contains(value),
      '|=' => actual == value || actual.startsWith('$value-'),
      '^=' => value.isNotEmpty && actual.startsWith(value),
      r'$=' => value.isNotEmpty && actual.endsWith(value),
      '*=' => value.isNotEmpty && actual.contains(value),
      _ => false,
    };
  }
}

class _PseudoClass {
  _PseudoClass(
    this.name, {
    this.a = 0,
    this.b = 0,
    this.selectors = const [],
    this.argument = '',
  });
  final String name;
  final String argument;
  final int a;
  final int b;
  final List<Selector> selectors;

  int get specificity => switch (name) {
    'where' => 0,
    'not' || 'is' => selectors.fold<int>(
      0,
      (best, selector) => math.max(best, selector.specificity),
    ),
    _ => 100,
  };

  bool matches(DomElement element) {
    final parent = element.parent;
    switch (name) {
      case 'root':
        return parent == null;
      case 'empty':
        return element.children.every(
          (child) => child is DomText && child.text.isEmpty,
        );
      case 'link' || 'any-link':
        return element.name == 'a' && element.attributes.containsKey('href');
      case 'not':
        return !selectors.any((selector) => selector.matches(element));
      case 'is' || 'where':
        return selectors.any((selector) => selector.matches(element));
      case 'lang':
        for (DomElement? node = element; node != null; node = node.parent) {
          final lang = languageAttribute(node);
          if (lang != null) {
            final wanted = argument.toLowerCase();
            final actual = lang.toLowerCase();
            return actual == wanted || actual.startsWith('$wanted-');
          }
        }
        return false;
      case 'never':
        return false;
    }
    if (parent == null) return false;
    final siblings = parent.elements;
    int position;
    int count;
    switch (name) {
      case 'first-child' || 'last-child' || 'only-child':
      case 'nth-child' || 'nth-last-child':
        position = element.elementIndex + 1;
        count = siblings.length;
      default:
        final same = siblings
            .where((sibling) => sibling.name == element.name)
            .toList();
        position = same.indexOf(element) + 1;
        count = same.length;
    }
    final fromEnd = count - position + 1;
    return switch (name) {
      'first-child' || 'first-of-type' => position == 1,
      'last-child' || 'last-of-type' => fromEnd == 1,
      'only-child' || 'only-of-type' => count == 1,
      'nth-child' || 'nth-of-type' => _nth(position),
      'nth-last-child' || 'nth-last-of-type' => _nth(fromEnd),
      _ => false,
    };
  }

  bool _nth(int position) {
    if (a == 0) return position == b;
    final n = (position - b) / a;
    return n >= 0 && n == n.truncateToDouble();
  }
}

class _SelectorParser {
  _SelectorParser(this.text);
  final String text;
  int index = 0;

  static const _dynamic = {
    'hover',
    'active',
    'focus',
    'focus-visible',
    'focus-within',
    'visited',
    'target',
    'checked',
    'disabled',
    'enabled',
    'indeterminate',
    'default',
    'required',
    'optional',
    'read-only',
    'read-write',
    'placeholder-shown',
    'in-range',
    'out-of-range',
    'valid',
    'invalid',
    'scope',
  };
  static const _pseudoElements = {
    'before',
    'after',
    'first-letter',
    'first-line',
    'marker',
    'selection',
    'placeholder',
  };

  Selector? parse() {
    final compounds = <Compound>[];
    final combinators = <Combinator>[];
    String? pseudoElement;
    while (true) {
      final hadSpace = _skipSpace();
      if (index >= text.length) break;
      if (compounds.isNotEmpty) {
        final character = text[index];
        if (character == '>' || character == '+' || character == '~') {
          index++;
          _skipSpace();
          combinators.add(switch (character) {
            '>' => Combinator.child,
            '+' => Combinator.adjacent,
            _ => Combinator.sibling,
          });
        } else if (hadSpace) {
          combinators.add(Combinator.descendant);
        } else {
          return null;
        }
      }
      if (pseudoElement != null) return null;
      final compound = Compound();
      var any = false;
      final name = _identifier(allowStar: true);
      if (name != null) {
        any = true;
        if (index < text.length && text[index] == '|') {
          // A type selector with a namespace: books use only the XHTML one.
          index++;
          final local = _identifier(allowStar: true);
          if (local == null) return null;
          if (local != '*') compound.tag = local.toLowerCase();
        } else if (name != '*') {
          compound.tag = name.toLowerCase();
        }
      }
      while (index < text.length) {
        final character = text[index];
        if (character == '#') {
          index++;
          final id = _identifier();
          if (id == null) return null;
          compound.id = id;
        } else if (character == '.') {
          index++;
          final name = _identifier();
          if (name == null) return null;
          compound.classes.add(name);
        } else if (character == '[') {
          final test = _attribute();
          if (test == null) return null;
          compound.attributes.add(test);
        } else if (character == ':') {
          index++;
          final element = index < text.length && text[index] == ':';
          if (element) index++;
          final name = _identifier()?.toLowerCase();
          if (name == null) return null;
          if (element || _pseudoElements.contains(name)) {
            if (!_pseudoElements.contains(name)) return null;
            pseudoElement = name;
          } else {
            final pseudo = _pseudoClass(name);
            if (pseudo == null) return null;
            compound.pseudoClasses.add(pseudo);
          }
        } else {
          break;
        }
        any = true;
      }
      if (!any) return null;
      compounds.add(compound);
    }
    if (compounds.isEmpty || combinators.length != compounds.length - 1) {
      return null;
    }
    return Selector(compounds, combinators, pseudoElement);
  }

  _PseudoClass? _pseudoClass(String name) {
    if (_dynamic.contains(name)) return _PseudoClass('never');
    const plain = {
      'root',
      'empty',
      'link',
      'any-link',
      'first-child',
      'last-child',
      'only-child',
      'first-of-type',
      'last-of-type',
      'only-of-type',
    };
    if (plain.contains(name)) return _PseudoClass(name);
    if (index >= text.length || text[index] != '(') return null;
    final close = _close(index);
    if (close < 0) return null;
    final argument = text.substring(index + 1, close).trim();
    index = close + 1;
    switch (name) {
      case 'not' || 'is' || 'where' || 'matches' || '-webkit-any':
        final selectors = Selector.parseList(argument);
        if (selectors == null) {
          // :is() and :where() forgive an invalid argument.
          return name == 'not' ? null : _PseudoClass('never');
        }
        return _PseudoClass(
          name == 'not' ? 'not' : (name == 'where' ? 'where' : 'is'),
          selectors: selectors,
        );
      case 'lang':
        return _PseudoClass(
          'lang',
          argument: argument.replaceAll(RegExp(r'''["']'''), ''),
        );
      case 'nth-child' ||
          'nth-last-child' ||
          'nth-of-type' ||
          'nth-last-of-type':
        final formula = _nth(argument.toLowerCase().replaceAll(' ', ''));
        if (formula == null) return null;
        return _PseudoClass(name, a: formula.$1, b: formula.$2);
    }
    return null;
  }

  (int, int)? _nth(String value) {
    if (value == 'odd') return (2, 1);
    if (value == 'even') return (2, 0);
    final match = RegExp(r'^([+-]?\d*)n([+-]\d+)?$').firstMatch(value);
    if (match != null) {
      final raw = match.group(1)!;
      final a = raw == '' || raw == '+'
          ? 1
          : (raw == '-' ? -1 : int.parse(raw));
      return (a, int.parse(match.group(2) ?? '0'));
    }
    final b = int.tryParse(value);
    return b == null ? null : (0, b);
  }

  int _close(int open) {
    var depth = 0;
    for (var cursor = open; cursor < text.length; cursor++) {
      if (text[cursor] == '(') depth++;
      if (text[cursor] == ')' && --depth == 0) return cursor;
    }
    return -1;
  }

  _AttributeTest? _attribute() {
    final close = text.indexOf(']', index);
    if (close < 0) return null;
    final inside = text.substring(index + 1, close).trim();
    index = close + 1;
    final match = RegExp(
      r'''^(?:([\w-]*|\*)\|)?([\w:-]+)\s*(?:([~|^$*]?=)\s*(?:"([^"]*)"|'([^']*)'|([^\s\]]+))\s*(i)?)?$''',
    ).firstMatch(inside);
    if (match == null) return null;
    final prefix = match.group(1);
    final local = match.group(2)!;
    return _AttributeTest(
      prefix == null || prefix.isEmpty || prefix == '*'
          ? local
          : '$prefix:$local',
      match.group(3),
      match.group(4) ?? match.group(5) ?? match.group(6) ?? '',
      anyPrefix: prefix == '*',
    );
  }

  String? _identifier({bool allowStar = false}) {
    if (allowStar && index < text.length && text[index] == '*') {
      index++;
      return '*';
    }
    final match = RegExp(r'-?[_a-zA-Z -￿][\w -￿-]*').matchAsPrefix(text, index);
    if (match == null) return null;
    index = match.end;
    return match.group(0);
  }

  bool _skipSpace() {
    final start = index;
    while (index < text.length && isSpace(text.codeUnitAt(index))) {
      index++;
    }
    return index > start;
  }
}

/// The rules of one section's sheets, indexed for matching, and the
/// cascade over them.
class Cascade {
  /// The cascade over [userAgent], the browser's default rules, and
  /// [rules], the book's and the reader's. A normal declaration of [rules]
  /// beats every normal declaration of [userAgent], whatever their
  /// specificity, as the origins of CSS cascade. The user agent rules have
  /// no important declarations.
  Cascade(
    Iterable<StyleRule> rules, {
    Iterable<StyleRule> userAgent = const [],
    this.overrides = const {},
  }) : _userAgent = Set.identity()..addAll(userAgent) {
    for (final rule in [...userAgent, ...rules]) {
      final key = rule.selector.compounds.last;
      if (key.id != null) {
        (_byId[key.id!] ??= []).add(rule);
      } else if (key.classes.isNotEmpty) {
        (_byClass[key.classes.first] ??= []).add(rule);
      } else if (key.tag != null) {
        (_byTag[key.tag!] ??= []).add(rule);
      } else {
        _universal.add(rule);
      }
    }
  }

  final Set<StyleRule> _userAgent;
  final _byId = <String, List<StyleRule>>{};
  final _byClass = <String, List<StyleRule>>{};
  final _byTag = <String, List<StyleRule>>{};
  final _universal = <StyleRule>[];

  /// Declarations that act as an element's style attribute, by element,
  /// such as the ones that epub.js sets on the body.
  final Map<DomElement, List<Declaration>> overrides;

  /// The computed style of [element], whose parent has [parent].
  Style compute(DomElement element, Style parent, double rootFontSize) {
    final candidates = <StyleRule>[
      ..._universal,
      ...?_byTag[element.name],
      for (final name in element.classes) ...?_byClass[name],
      if (element.id != null) ...?_byId[element.id],
    ];
    final winners = <String, (int, int, int, String)>{};
    void offer(Declaration declaration, int level, int specificity, int order) {
      for (final (property, value) in _expand(declaration)) {
        final current = winners[property];
        final rank = (declaration.important ? 2 : 0) + level;
        if (current == null ||
            rank > current.$1 ||
            (rank == current.$1 &&
                (specificity > current.$2 ||
                    (specificity == current.$2 && order >= current.$3)))) {
          winners[property] = (rank, specificity, order, value);
        }
      }
    }

    for (final rule in candidates) {
      if (!rule.selector.matches(element)) continue;
      for (final declaration in rule.declarations) {
        offer(
          declaration,
          _userAgent.contains(rule) ? -1 : 0,
          rule.selector.specificity,
          rule.order,
        );
      }
    }
    final attribute = element.attributes['style'];
    if (attribute != null) {
      for (final declaration in parseDeclarations(attribute)) {
        offer(declaration, 1, 0, 0);
      }
    }
    for (final declaration in overrides[element] ?? const <Declaration>[]) {
      offer(declaration, 1, 0, 1);
    }
    final style = parent.inherit();
    if (languageAttribute(element) case final language?) {
      style.language = language;
    }
    // Font size comes first: em lengths of the other properties use it.
    final size = winners.remove('font-size')?.$4;
    if (size != null) {
      style.fontSize = _fontSize(size, parent.fontSize, rootFontSize);
    }
    if (element.parent == null) rootFontSize = style.fontSize;
    for (final MapEntry(key: property, value: winner) in winners.entries) {
      _apply(style, parent, property, winner.$4.trim(), rootFontSize);
    }
    // A float and a positioned box are blocks. So is a flex or grid item.
    if ((style.floated ||
            style.position == 'absolute' ||
            style.position == 'fixed') &&
        style.display == Display.inline) {
      style.display = Display.block;
    }
    if (parent.flexOrGrid &&
        (style.display == Display.inline ||
            style.display == Display.inlineBlock)) {
      style.display = Display.block;
    }
    return style;
  }
}

const _sides = ['top', 'right', 'bottom', 'left'];

/// The longhand declarations of [declaration].
Iterable<(String, String)> _expand(Declaration declaration) sync* {
  final property = declaration.property;
  final value = declaration.value;
  switch (property) {
    case 'margin' || 'padding':
      final parts = _tokens(value);
      if (parts.isEmpty || parts.length > 4) return;
      final four = switch (parts.length) {
        1 => [parts[0], parts[0], parts[0], parts[0]],
        2 => [parts[0], parts[1], parts[0], parts[1]],
        3 => [parts[0], parts[1], parts[2], parts[1]],
        _ => parts,
      };
      for (var side = 0; side < 4; side++) {
        yield ('$property-${_sides[side]}', four[side]);
      }
    case 'border' ||
        'border-top' ||
        'border-right' ||
        'border-bottom' ||
        'border-left':
      final sides = property == 'border'
          ? _sides
          : [property.substring('border-'.length)];
      var width = 'medium';
      var style = 'none';
      for (final token in _tokens(value)) {
        if (_borderStyles.contains(token.toLowerCase())) {
          style = token.toLowerCase();
        } else if (_isLength(token) ||
            const {'thin', 'medium', 'thick'}.contains(token)) {
          width = token;
        }
      }
      for (final side in sides) {
        yield ('border-$side-width', width);
        yield ('border-$side-style', style);
      }
    case 'border-width' || 'border-style':
      final parts = _tokens(value);
      if (parts.isEmpty || parts.length > 4) return;
      final kind = property.substring('border-'.length);
      final four = switch (parts.length) {
        1 => [parts[0], parts[0], parts[0], parts[0]],
        2 => [parts[0], parts[1], parts[0], parts[1]],
        3 => [parts[0], parts[1], parts[2], parts[1]],
        _ => parts,
      };
      for (var side = 0; side < 4; side++) {
        yield ('border-${_sides[side]}-$kind', four[side]);
      }
    case 'margin-block' || 'padding-block':
      final parts = _tokens(value);
      final base = property.split('-').first;
      if (parts.isEmpty) return;
      yield ('$base-top', parts.first);
      yield ('$base-bottom', parts.last);
    case 'margin-inline' || 'padding-inline':
      final parts = _tokens(value);
      final base = property.split('-').first;
      if (parts.isEmpty) return;
      yield ('$base-left', parts.first);
      yield ('$base-right', parts.last);
    case 'margin-block-start' || 'padding-block-start':
      yield ('${property.split('-').first}-top', value);
    case 'margin-block-end' || 'padding-block-end':
      yield ('${property.split('-').first}-bottom', value);
    case 'margin-inline-start' || 'padding-inline-start':
      yield ('${property.split('-').first}-left', value);
    case 'margin-inline-end' || 'padding-inline-end':
      yield ('${property.split('-').first}-right', value);
    case 'page-break-before' || 'page-break-after' || 'page-break-inside':
      final side = property.substring('page-break-'.length);
      yield ('break-$side', value == 'always' ? 'page' : value);
    case 'font':
      final match = RegExp(
        r'^((?:(?:italic|oblique|normal|small-caps|bold|bolder|lighter|\d00)\s+)*)([^\s/]+)(?:\s*/\s*(\S+))?\s+(.+)$',
      ).firstMatch(value.trim());
      if (match == null) return;
      final words = match.group(1)!.split(RegExp(r'\s+'));
      yield ('font-style', words.contains('italic') ? 'italic' : 'normal');
      yield (
        'font-variant',
        words.contains('small-caps') ? 'small-caps' : 'normal',
      );
      yield (
        'font-weight',
        words.firstWhere(
          (word) => RegExp(r'^(bold|bolder|lighter|\d00)$').hasMatch(word),
          orElse: () => 'normal',
        ),
      );
      yield ('font-size', match.group(2)!);
      yield ('line-height', match.group(3) ?? 'normal');
      yield ('font-family', match.group(4)!);
    case 'list-style':
      for (final token in _tokens(value)) {
        if (token == 'inside' || token == 'outside') {
          yield ('list-style-position', token);
        } else if (!token.startsWith('url(')) {
          yield ('list-style-type', token);
        }
      }
    case 'text-decoration':
      yield ('text-decoration-line', value);
    case 'font-variant-caps':
      yield ('font-variant', value);
    case 'all':
      for (final longhand in _longhands) {
        yield (longhand, value);
      }
    // A value that is not valid drops the declaration, so the one that it
    // would replace stays, as in Chromium.
    case 'border-spacing':
      if (_keyword(value) || _spacing(value, 16, 16) != null) {
        yield (property, value);
      }
    case 'border-collapse':
      if (_keyword(value) ||
          const {'collapse', 'separate'}.contains(value.trim().toLowerCase())) {
        yield (property, value);
      }
    // Chromium parses -webkit-hyphens as another name of hyphens.
    case 'hyphens' || '-webkit-hyphens':
      if (_keyword(value) ||
          const {
            'none',
            'manual',
            'auto',
          }.contains(value.trim().toLowerCase())) {
        yield ('hyphens', value);
      }
    default:
      yield (property, value);
  }
}

/// The language that [element] names for itself: its `xml:lang`
/// attribute, which wins as in HTML, or its `lang` attribute. Null when it
/// names none.
String? languageAttribute(DomElement element) =>
    element.attributes['xml:lang'] ?? element.attributes['lang'];

/// Whether [value] is `inherit`, `initial` or `unset`.
bool _keyword(String value) =>
    const {'inherit', 'initial', 'unset'}.contains(value.trim().toLowerCase());

/// The `border-spacing` that [value] gives, across and down in pixels, in
/// an element whose font is [fontSize] pixels: one length for both, or
/// two. Null when [value] is not valid: a percentage or a negative length.
(double, double)? _spacing(String value, double fontSize, double root) {
  final lengths = [
    for (final token in _tokens(value)) parseLength(token, fontSize, root),
  ];
  if (lengths.isEmpty || lengths.length > 2) return null;
  final pixels = <double>[];
  for (final length in lengths) {
    if (length == null ||
        length.isAuto ||
        length.isNone ||
        length.unit == LengthUnit.percent ||
        length.value < 0) {
      return null;
    }
    pixels.add(length.resolve(0));
  }
  return (pixels.first, pixels.last);
}

const _borderStyles = {
  'none',
  'hidden',
  'solid',
  'dotted',
  'dashed',
  'double',
  'groove',
  'ridge',
  'inset',
  'outset',
};

List<String> _tokens(String value) => value
    .trim()
    .split(RegExp(r'\s+'))
    .where((part) => part.isNotEmpty)
    .toList();

bool _isLength(String token) =>
    RegExp(r'^-?(\d+\.?\d*|\.\d+)(px|em|rem|pt|%|ex|ch|vw|vh|in|cm|mm|pc)?$')
        .hasMatch(token);

/// [value] in pixels when it is a length: em units against [fontSize], rem
/// against [rootFontSize]. A percentage is kept for layout. Null when it is
/// not a length.
Length? parseLength(
  String value,
  double fontSize,
  double rootFontSize, {
  double viewportWidth = 412,
  double viewportHeight = 671,
}) {
  final text = value.trim().toLowerCase();
  if (text == 'auto') return const Length.auto();
  if (text == 'none') return const Length.none();
  if (text == '0') return const Length.px(0);
  final match = RegExp(
    r'^(-?(?:\d+\.?\d*|\.\d+))(px|em|rem|pt|%|ex|ch|vw|vh|in|cm|mm|pc)$',
  ).firstMatch(text);
  if (match == null) return null;
  final number = double.parse(match.group(1)!);
  return switch (match.group(2)) {
    'px' => Length.px(number),
    'em' => Length.px(number * fontSize),
    'rem' => Length.px(number * rootFontSize),
    'pt' => Length.px(number * 4 / 3),
    'pc' => Length.px(number * 16),
    'in' => Length.px(number * 96),
    'cm' => Length.px(number * 96 / 2.54),
    'mm' => Length.px(number * 96 / 25.4),
    'ex' || 'ch' => Length.px(number * fontSize / 2),
    'vw' => Length.px(number * viewportWidth / 100),
    'vh' => Length.px(number * viewportHeight / 100),
    '%' => Length.percent(number),
    _ => null,
  };
}

double _fontSize(String value, double parent, double root) {
  final text = value.trim().toLowerCase();
  const keywords = {
    'xx-small': 9.0,
    'x-small': 10.0,
    'small': 13.0,
    'medium': 16.0,
    'large': 18.0,
    'x-large': 24.0,
    'xx-large': 32.0,
    'xxx-large': 48.0,
  };
  if (keywords.containsKey(text)) return keywords[text]!;
  if (text == 'smaller') return parent / 1.2;
  if (text == 'larger') return parent * 1.2;
  if (text == 'inherit' || text == 'unset') return parent;
  if (text == 'initial') return 16;
  final length = parseLength(text, parent, root);
  if (length == null || length.isAuto || length.isNone) return parent;
  return length.unit == LengthUnit.percent
      ? parent * length.value / 100
      : length.value;
}

void _apply(
  Style style,
  Style parent,
  String property,
  String value,
  double root,
) {
  final lower = value.toLowerCase();
  Length? length() => parseLength(lower, style.fontSize, root);
  if (lower == 'inherit' || lower == 'initial' || lower == 'unset') {
    final inherited = _inheritedProperties.contains(property);
    _copyFrom(
      style,
      lower == 'inherit' || (lower == 'unset' && inherited)
          ? parent
          : Style.initial(),
      property,
    );
    return;
  }
  switch (property) {
    case 'display':
      style.display = switch (lower) {
        'none' => Display.none,
        'inline' => Display.inline,
        'list-item' => Display.listItem,
        'inline-block' ||
        'inline-table' ||
        'inline-flex' => Display.inlineBlock,
        // The renderer lays out flex and grid boxes as plain blocks, and
        // prepare finds tables by their elements.
        _ => Display.block,
      };
      style.flexOrGrid = const {
        'flex',
        'inline-flex',
        'grid',
        'inline-grid',
      }.contains(lower);
    case 'float':
      style.floated = lower == 'left' || lower == 'right';
    case 'position':
      style.position = lower;
    case 'left' || 'top':
      final parsed = length();
      if (parsed == null || parsed.isNone) return;
      if (property == 'left') {
        style.left = parsed;
      } else {
        style.top = parsed;
      }
    case 'margin-top' || 'margin-right' || 'margin-bottom' || 'margin-left':
      final parsed = length();
      if (parsed != null && !parsed.isNone) {
        style.margin = [...style.margin]
          ..[_sides.indexOf(property.substring(7))] = parsed;
      }
    case 'padding-top' || 'padding-right' || 'padding-bottom' || 'padding-left':
      final parsed = length();
      if (parsed != null && !parsed.isAuto && !parsed.isNone) {
        style.padding = [...style.padding]
          ..[_sides.indexOf(property.substring(8))] = parsed;
      }
    case 'border-top-width' ||
        'border-right-width' ||
        'border-bottom-width' ||
        'border-left-width':
      final side = _sides.indexOf(property.split('-')[1]);
      final width = switch (lower) {
        'thin' => 1.0,
        'medium' => 3.0,
        'thick' => 5.0,
        _ => length()?.resolve(0),
      };
      if (width != null) {
        style.borderWidth = [...style.borderWidth]..[side] = width;
      }
    case 'border-top-style' ||
        'border-right-style' ||
        'border-bottom-style' ||
        'border-left-style':
      style.borderVisible = [...style.borderVisible]
        ..[_sides.indexOf(property.split('-')[1])] =
            lower != 'none' && lower != 'hidden';
    case 'width' || 'max-width' || 'height' || 'max-height':
      final parsed = length();
      if (parsed == null) return;
      switch (property) {
        case 'width':
          style.width = parsed;
        case 'max-width':
          style.maxWidth = parsed;
        case 'height':
          style.height = parsed;
        case 'max-height':
          style.maxHeight = parsed;
      }
    case 'box-sizing':
      style.borderBox = lower == 'border-box';
    case 'break-before' || 'break-after':
      final rule = switch (lower) {
        'page' ||
        'left' ||
        'right' ||
        'recto' ||
        'verso' ||
        'always' => BreakRule.page,
        'avoid' || 'avoid-page' => BreakRule.avoid,
        _ => BreakRule.auto,
      };
      if (property == 'break-before') {
        style.breakBefore = rule;
      } else {
        style.breakAfter = rule;
      }
    case 'break-inside':
      style.avoidBreakInside = lower.startsWith('avoid');
    case 'text-indent':
      final parsed = length();
      if (parsed != null && !parsed.isAuto) style.textIndent = parsed;
    case 'text-align':
      style.textAlign = switch (lower) {
        'left' => Align.left,
        'right' => Align.right,
        'center' || '-webkit-center' => Align.center,
        'justify' => Align.justify,
        'end' => Align.end,
        _ => Align.start,
      };
    case 'font-weight':
      style.fontWeight = switch (lower) {
        'normal' => 400,
        'bold' => 700,
        'bolder' =>
          parent.fontWeight < 400
              ? 400
              : parent.fontWeight < 600
              ? 700
              : 900,
        'lighter' =>
          parent.fontWeight < 600
              ? 100
              : parent.fontWeight < 800
              ? 400
              : 700,
        _ => int.tryParse(lower) ?? style.fontWeight,
      };
    case 'font-style':
      style.italic = lower == 'italic' || lower.startsWith('oblique');
    case 'font-family':
      style.fontFamily = [
        for (final name in value.split(','))
          name.trim().replaceAll(RegExp(r'''^["']|["']$'''), ''),
      ];
    case 'font-variant':
      style.smallCaps = lower.contains('small-caps');
    case 'font-variant-numeric':
      style.oldstyleFigures = lower.contains('oldstyle-nums');
    case 'line-height':
      if (lower == 'normal') {
        style.lineHeight = null;
      } else if (double.tryParse(lower) case final factor?) {
        style.lineHeight = factor;
        style.lineHeightFactor = true;
      } else if (length() case final parsed?) {
        style.lineHeight = parsed.unit == LengthUnit.percent
            ? style.fontSize * parsed.value / 100
            : parsed.value;
        style.lineHeightFactor = false;
      }
    case 'letter-spacing' || 'word-spacing':
      final spacing = lower == 'normal' ? 0.0 : length()?.resolve(0);
      if (spacing == null) return;
      if (property == 'letter-spacing') {
        style.letterSpacing = spacing;
      } else {
        style.wordSpacing = spacing;
      }
    case 'text-transform':
      style.transform = switch (lower) {
        'uppercase' => Transform.upper,
        'lowercase' => Transform.lower,
        'capitalize' => Transform.capitalize,
        _ => Transform.none,
      };
    case 'white-space':
      style.whiteSpace = switch (lower) {
        'pre' => WhiteSpace.pre,
        'pre-wrap' || 'break-spaces' => WhiteSpace.preWrap,
        'pre-line' => WhiteSpace.preLine,
        'nowrap' => WhiteSpace.nowrap,
        _ => WhiteSpace.normal,
      };
    case 'text-decoration-line':
      style.underline = lower.contains('underline');
      style.lineThrough = lower.contains('line-through');
    case 'hyphens':
      style.hyphens = switch (lower) {
        'none' => Hyphens.none,
        'auto' => Hyphens.auto,
        _ => Hyphens.manual,
      };
    case 'list-style-type':
      style.listStyleType = lower;
    case 'list-style-position':
      style.listStyleInside = lower == 'inside';
    case 'orphans':
      style.orphans = int.tryParse(lower) ?? style.orphans;
    case 'widows':
      style.widows = int.tryParse(lower) ?? style.widows;
    case 'border-spacing':
      style.borderSpacing =
          _spacing(lower, style.fontSize, root) ?? style.borderSpacing;
    case 'border-collapse':
      style.collapseBorders = lower == 'collapse';
    case 'vertical-align':
      style.verticalAlign = switch (lower) {
        'super' => VerticalAlign.superscript,
        'sub' => VerticalAlign.subscript,
        'top' || 'text-top' => VerticalAlign.top,
        'middle' => VerticalAlign.middle,
        'bottom' || 'text-bottom' => VerticalAlign.bottom,
        _ => VerticalAlign.baseline,
      };
  }
}

const _inheritedProperties = {
  'text-indent',
  'text-align',
  'font-weight',
  'font-style',
  'font-family',
  'font-size',
  'font-variant',
  'font-variant-numeric',
  'line-height',
  'letter-spacing',
  'word-spacing',
  'text-transform',
  'white-space',
  'hyphens',
  'list-style-type',
  'list-style-position',
  'orphans',
  'widows',
  'border-spacing',
  'border-collapse',
};

/// The longhand properties that the renderer computes, which `all`
/// sets at once.
const _longhands = [
  'display',
  'float',
  'position',
  'left',
  'top',
  'width',
  'max-width',
  'height',
  'max-height',
  'box-sizing',
  'break-before',
  'break-after',
  'break-inside',
  'margin-top',
  'margin-right',
  'margin-bottom',
  'margin-left',
  'padding-top',
  'padding-right',
  'padding-bottom',
  'padding-left',
  'border-top-width',
  'border-right-width',
  'border-bottom-width',
  'border-left-width',
  'border-top-style',
  'border-right-style',
  'border-bottom-style',
  'border-left-style',
  'text-indent',
  'text-align',
  'font-weight',
  'font-style',
  'font-family',
  'font-size',
  'font-variant',
  'font-variant-numeric',
  'line-height',
  'letter-spacing',
  'word-spacing',
  'text-transform',
  'white-space',
  'hyphens',
  'text-decoration-line',
  'list-style-type',
  'list-style-position',
  'orphans',
  'widows',
  'border-spacing',
  'border-collapse',
  'vertical-align',
];

/// Sets [property] of [style] to its value in [source]: the parent's
/// style for `inherit`, or the initial style for `initial`.
void _copyFrom(Style style, Style source, String property) {
  final border = property.startsWith('border-')
      ? _sides.indexOf(property.split('-')[1])
      : -1;
  switch (property) {
    case 'margin-top' || 'margin-right' || 'margin-bottom' || 'margin-left':
      final side = _sides.indexOf(property.substring(7));
      style.margin = [...style.margin]..[side] = source.margin[side];
    case 'padding-top' || 'padding-right' || 'padding-bottom' || 'padding-left':
      final side = _sides.indexOf(property.substring(8));
      style.padding = [...style.padding]..[side] = source.padding[side];
    case _ when border >= 0 && property.endsWith('-width'):
      style.borderWidth = [...style.borderWidth]
        ..[border] = source.borderWidth[border];
    case _ when border >= 0 && property.endsWith('-style'):
      style.borderVisible = [...style.borderVisible]
        ..[border] = source.borderVisible[border];
    case 'display':
      style.display = source.display;
      style.flexOrGrid = source.flexOrGrid;
    case 'float':
      style.floated = source.floated;
    case 'position':
      style.position = source.position;
    case 'left':
      style.left = source.left;
    case 'top':
      style.top = source.top;
    case 'width':
      style.width = source.width;
    case 'max-width':
      style.maxWidth = source.maxWidth;
    case 'height':
      style.height = source.height;
    case 'max-height':
      style.maxHeight = source.maxHeight;
    case 'box-sizing':
      style.borderBox = source.borderBox;
    case 'break-before':
      style.breakBefore = source.breakBefore;
    case 'break-after':
      style.breakAfter = source.breakAfter;
    case 'break-inside':
      style.avoidBreakInside = source.avoidBreakInside;
    case 'text-indent':
      style.textIndent = source.textIndent;
    case 'text-align':
      style.textAlign = source.textAlign;
    case 'font-weight':
      style.fontWeight = source.fontWeight;
    case 'font-style':
      style.italic = source.italic;
    case 'font-family':
      style.fontFamily = source.fontFamily;
    case 'font-size':
      style.fontSize = source.fontSize;
    case 'font-variant':
      style.smallCaps = source.smallCaps;
    case 'font-variant-numeric':
      style.oldstyleFigures = source.oldstyleFigures;
    case 'line-height':
      style.lineHeight = source.lineHeight;
      style.lineHeightFactor = source.lineHeightFactor;
    case 'letter-spacing':
      style.letterSpacing = source.letterSpacing;
    case 'word-spacing':
      style.wordSpacing = source.wordSpacing;
    case 'text-transform':
      style.transform = source.transform;
    case 'white-space':
      style.whiteSpace = source.whiteSpace;
    case 'hyphens':
      style.hyphens = source.hyphens;
    case 'text-decoration-line':
      style.underline = source.underline;
      style.lineThrough = source.lineThrough;
    case 'list-style-type':
      style.listStyleType = source.listStyleType;
    case 'list-style-position':
      style.listStyleInside = source.listStyleInside;
    case 'orphans':
      style.orphans = source.orphans;
    case 'widows':
      style.widows = source.widows;
    case 'border-spacing':
      style.borderSpacing = source.borderSpacing;
    case 'border-collapse':
      style.collapseBorders = source.collapseBorders;
    case 'vertical-align':
      style.verticalAlign = source.verticalAlign;
  }
}
