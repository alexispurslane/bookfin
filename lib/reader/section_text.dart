import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml_events.dart';

/// Whether [code] is white space: exactly what `\s` matches in Dart.
bool isWhiteSpace(int code) =>
    code >= 0x09 && code <= 0x0D ||
    code == 0x20 ||
    code == 0xA0 ||
    code == 0x1680 ||
    code >= 0x2000 && code <= 0x200A ||
    code == 0x2028 ||
    code == 0x2029 ||
    code == 0x202F ||
    code == 0x205F ||
    code == 0x3000 ||
    code == 0xFEFF;

/// Walks the section [bytes] once and returns its non-whitespace UTF-16
/// count. [onText] receives runs that are wholly whitespace or wholly
/// non-whitespace, with their visible offset from the section's start.
/// [onElement] receives start and end events with the same offset units,
/// including elements before the body, so their IDs keep their offsets.
///
/// Text and CDATA count from the first body start onward, including text
/// after its end. This preserves the reader's body-event rule; CSS does
/// not decide visibility here. Invalid UTF-8 is replaced. A parse failure
/// throws, and callers must discard all results from this section.
int walkSection(
  Uint8List bytes, {
  void Function(String text, int visible, bool whitespace)? onText,
  void Function(XmlEvent event, int visible)? onElement,
}) {
  var visible = 0;
  var body = false;
  for (final event in parseEvents(utf8.decode(bytes, allowMalformed: true))) {
    switch (event) {
      case XmlStartElementEvent(:final localName):
        if (localName == 'body') body = true;
        onElement?.call(event, visible);
      case XmlEndElementEvent():
        onElement?.call(event, visible);
      case XmlTextEvent(:final value) || XmlCDATAEvent(:final value) when body:
        var start = 0;
        while (start < value.length) {
          final whitespace = isWhiteSpace(value.codeUnitAt(start));
          var end = start + 1;
          while (end < value.length &&
              isWhiteSpace(value.codeUnitAt(end)) == whitespace) {
            end++;
          }
          onText?.call(value.substring(start, end), visible, whitespace);
          if (!whitespace) visible += end - start;
          start = end;
        }
      default:
    }
  }
  return visible;
}
