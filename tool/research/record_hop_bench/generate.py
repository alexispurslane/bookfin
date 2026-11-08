"""Copies the pure-Dart work of the record store into gen/ for bench.dart.

The record store imports Flutter, so `dart compile exe` cannot build it. This
script copies the code that a record-store hop runs, unchanged, and replaces
only the imports that need Flutter. Run it from this directory.
"""
import pathlib
import re

root = pathlib.Path(__file__).resolve().parents[3]
lib = root / 'lib'
gen = pathlib.Path(__file__).resolve().parent / 'gen'
gen.mkdir(exist_ok=True)

journal = (lib / 'sync/journal.dart').read_text()
journal = journal.replace("import 'package:flutter/foundation.dart';", "import 'shim.dart';")
(gen / 'journal.dart').write_text(journal)
(gen / 'shim.dart').write_text(
    "bool listEquals<T>(List<T>? a, List<T>? b) {\n"
    "  if (a == null) return b == null;\n"
    "  if (b == null || a.length != b.length) return false;\n"
    "  for (var i = 0; i < a.length; i++) {\n"
    "    if (a[i] != b[i]) return false;\n"
    "  }\n"
    "  return true;\n"
    "}\n"
)


def block(text, start):
    """The text from the line that starts with [start] to the end of its block."""
    begin = text.index(start)
    depth = 0
    seen = False
    # The body starts after the parameter list, which can hold braces.
    for index in range(text.index(') {\n', begin) + 2, len(text)):
        if text[index] == '{':
            depth += 1
            seen = True
        elif text[index] == '}':
            depth -= 1
            if seen and depth == 0:
                return text[begin:index + 1]
    raise ValueError(start)


def typedef(text, name):
    begin = text.index(f'typedef {name} =')
    return text[begin:text.index(');', begin) + 2]


database = (lib / 'playback/database.dart').read_text()
(gen / 'database.dart').write_text('\n\n'.join([
    "import 'dart:convert';\n\nimport 'journal.dart';",
    typedef(database, 'AccountRows'),
    typedef(database, 'RecordCommit'),
    typedef(database, 'KeptRows'),
    'typedef HeldIdentities = ({Set<String> actions, Set<String> records});',
    'abstract class RecordReader {\n'
    '  Future<({AccountRows? rows, bool damaged})> rows(String account);\n'
    '  Future<KeptRows> kept();\n'
    '  Future<Map<String, HeldIdentities>> held(Iterable<String> accounts);\n'
    '}',
    'class RecordDatabase {\n  '
    + block(database, 'static Map<String, dynamic> decode(')
    + '\n\n  '
    + block(database, 'static RecordCommit encodeCommit(')
    + '\n}',
]) + '\n')

store = (lib / 'playback/store.dart').read_text()
work = store[store.index('void _validateActionValue('):]
(gen / 'store.dart').write_text('\n\n'.join([
    "import 'dart:convert';\nimport 'dart:math';\n\n"
    f"import '{(lib / 'playback/records.dart').as_uri()}';\n"
    "import 'database.dart';\nimport 'journal.dart';",
    *(typedef(store, name) for name in ['_StoredAccount', '_View', '_Views', '_Restored']),
    work,
    '// The work that the benchmark times.\n'
    'Object restoreRows(({String account, AccountRows rows}) input) => _restoreRows(input);\n'
    'Object restoreText(({String account, String text, bool database}) input) => _restoreText(input);\n'
    'Object viewsOfVersions(({Map<String, dynamic> metadata, Map<String, List<Map<String, dynamic>>> versions}) input) => _viewsOfVersions(input);\n'
    'Map<String, dynamic> metadataOf(Map<String, dynamic> snapshot) => _metadata(snapshot);\n',
]))
