import 'package:bookfin/sync/journal.dart';
import 'package:bookfin/sync/record_address.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the address retains the exact identity while naming decoded parts', () {
    const legacy = r' [ "future", "notes", "it\u0065m" ] ';
    final address = RecordAddress.parse(legacy);
    expect(
      (address.domain, address.collection, address.id),
      ('future', 'notes', 'item'),
    );
    expect(address.encoded, legacy);
    expect(address, RecordAddress.parse(legacy));
    expect({address: 1}[RecordAddress.parse(legacy)], 1);
    expect(address, isNot(RecordAddress('future', 'notes', 'item')));
    final journal = RecordJournal('alice', 'phone')
      ..change(address.encoded, null);
    expect(journal.uploads.single['record'], legacy);
  });

  test('new addresses write the existing format including escaped record identities', () {
    final address = RecordAddress(
      'reading',
      'resumes',
      '["edition","source","revision"]',
    );
    expect(
      address.encoded,
      r'["reading","resumes","[\"edition\",\"source\",\"revision\"]"]',
    );
    expect(RecordAddress.parse(address.encoded), address);
  });

  test('malformed addresses are rejected by both the address and journal boundaries', () {
    for (final malformed in [
      'not-json',
      '{}',
      '[]',
      '["a","b"]',
      '["a","b","c","d"]',
      '["a","b",1]',
      '["a","b",null]',
      '["a","b",""]',
      '["","b","c"]',
      '["a","","c"]',
    ]) {
      expect(() => RecordAddress.parse(malformed), throwsFormatException);
      expect(
        () => RecordJournal('alice', 'phone').change(malformed, null),
        throwsFormatException,
      );
    }
    expect(() => RecordAddress('', 'history', 'id'), throwsFormatException);
    expect(() => RecordAddress('audio', '', 'id'), throwsFormatException);
    expect(() => RecordAddress('audio', 'history', ''), throwsFormatException);
  });
}
