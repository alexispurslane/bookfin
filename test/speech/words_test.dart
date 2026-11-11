import 'package:bookfin/speech/words.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a written number reads as the words that a narrator speaks', () {
    expect(normalizeWords('Chapter 21, 300 men'), [
      'chapter',
      'twenty',
      'one',
      'three',
      'hundred',
      'men',
    ]);
  });

  test('case, punctuation and dashes do not part a narrator from the book', () {
    expect(normalizeWords('“It was—the best… of TIMES,” he said.'), [
      'it',
      'was',
      'the',
      'best',
      'of',
      'times',
      'he',
      'said',
    ]);
  });

  test('an apostrophe stays inside its word', () {
    expect(normalizeWords("Marley's ghost didn't"), [
      'marleys',
      'ghost',
      'didnt',
    ]);
  });

  test('heard tokens join into words at the time of their first token', () {
    final heard = Heard.fromTokens(
      '0\t Alice\n400\t was\n640\t begin\n820\tning\n1200\t to\n'
      '1300\t[_TT_150]\n1400\t<|endoftext|>\n',
    );
    expect(heard.words, ['alice', 'was', 'beginning', 'to']);
    expect(heard.ms, [0, 400, 640, 1200]);
  });

  test('a heard number becomes several words at one time', () {
    final heard = Heard.fromTokens('0\t In\n300\t 1865\n');
    expect(heard.words, [
      'in',
      'one',
      'thousand',
      'eight',
      'hundred',
      'sixty',
      'five',
    ]);
    expect(heard.ms, [0, 300, 300, 300, 300, 300, 300]);
  });
}
