// Plain JSON dumps of what prepare makes, for tests that compare two
// prepared sections or two parts of one section.
import 'package:bookfin/reader/epub/css.dart' show Length;
import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/prepare.dart';

/// Everything that [section] holds, in plain JSON values: its DOM, its
/// flow items, its run styles and its faces. Two prepared sections are the
/// same when their dumps are equal.
Object? dumpPrepared(PreparedSection section) => {
  'index': section.index,
  'dom': [_dumpNode(section.dom.root), section.dom.body.order],
  'visible': section.dom.visibleLength,
  'flow': [for (final item in section.flow) dumpItem(item)],
  'styles': [for (final style in section.styles) _dumpStyle(style)],
};

/// [item] in plain JSON values. With [styles], each run style index is
/// the dump of the style that it names in [styles], so that items of two
/// sections that number their styles in another order compare equal.
Object? dumpItem(FlowItem item, [List<RunStyle>? styles]) => switch (item) {
  BlockStart() => [
    'start',
    item.node,
    _dumpPlacement(item.placement),
    '${item.marginTop}',
    '${item.marginBottom}',
    [for (final side in item.padding) '$side'],
    [for (final side in item.border) '$side'],
    [
      item.marker?.text,
      item.marker == null ? null : _styleOf(item.marker!.style, styles),
    ],
    item.shrinkToFit,
    item.avoidBreakBefore,
    item.avoidBreakAfter,
    item.avoidBreakInside,
  ],
  BlockEnd() => ['end'],
  ParagraphItem() => [
    'paragraph',
    _dumpText(item.text, styles),
    _dumpLength(item.indent),
    item.orphans,
    item.widows,
  ],
  ImageItem() => [
    'image',
    item.node,
    _dumpImage(item.image),
    _dumpSizing(item.sizing),
    '${item.marginLeft}',
    item.centered,
    '${item.marginTop}',
    '${item.marginBottom}',
  ],
  TableItem() => [
    'table',
    [
      for (final row in item.rows)
        [
          for (final cell in row)
            [
              [for (final each in cell.flow) dumpItem(each, styles)],
              cell.colspan,
              [for (final side in cell.padding) '$side'],
              [for (final side in cell.border) '$side'],
              '${cell.align}',
            ],
        ],
    ],
    '${item.width}',
    ['${item.spacing.$1}', '${item.spacing.$2}'],
  ],
  SkippedItem() => ['skipped'],
};

Object? _styleOf(int index, List<RunStyle>? styles) =>
    styles == null ? index : _dumpStyle(styles[index]);

Object? _dumpText(StyledText text, List<RunStyle>? styles) => [
  _styleOf(text.style, styles),
  text.align.name,
  [for (final run in text.runs) _dumpRun(run, styles)],
];

Object? _dumpRun(InlineRun run, List<RunStyle>? styles) => switch (run) {
  TextRun() => [
    'text',
    run.text,
    _styleOf(run.style, styles),
    run.node,
    run.offsets.toList(),
  ],
  BreakRun() => ['break', run.node],
  ImageRun() => [
    'image',
    run.node,
    _dumpImage(run.image),
    _dumpSizing(run.sizing),
  ],
  RaisedRun() => [
    'raised',
    run.node,
    _dumpText(run.text, styles),
    '${run.shift}',
  ],
};

Object? _dumpNode(DomNode node) => switch (node) {
  DomText() => [node.order, node.textIndex, node.visibleBefore, node.text],
  DomElement() => [
    node.order,
    node.elementIndex,
    node.name,
    [
      for (final key in node.attributes.keys.toList()..sort())
        [key, node.attributes[key]],
    ],
    [for (final child in node.children) _dumpNode(child)],
    [for (final element in node.elements) element.order],
  ],
};

Object? _dumpPlacement(BoxPlacement placement) => [
  '${placement.marginLeft}',
  '${placement.marginRight}',
  '${placement.horizontal}',
  '${placement.used}',
  placement.autoLeft,
  placement.autoRight,
  placement.parentAlign?.name,
];

Object? _dumpImage(DrawnImage image) => [
  image.path,
  '${image.invert}',
  image.alt,
];

Object? _dumpSizing(ImageSizing sizing) => [
  '${sizing.intrinsicWidth}',
  '${sizing.intrinsicHeight}',
  _dumpLength(sizing.width),
  _dumpLength(sizing.height),
  '${sizing.attributeWidth}',
  '${sizing.attributeHeight}',
  _dumpLength(sizing.maxWidth),
  '${sizing.maxHeight}',
];

Object? _dumpLength(Length length) => ['${length.value}', length.unit.name];

Object? _dumpStyle(RunStyle style) => [
  style.family,
  '${style.size}',
  style.weight,
  style.italic,
  '${style.letterSpacing}',
  '${style.wordSpacing}',
  '${style.lineHeight}',
  style.underline,
  style.lineThrough,
  style.smallCaps,
  style.oldstyleFigures,
];
