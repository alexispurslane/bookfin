// The Android arm64 build of the speech library holds ARMv8.2 instructions
// (native/speech/CMakeLists.txt). A CPU that lacks one of them would stop
// the whole app at the first window, so the library asks the CPU first and
// gives no model there (bs_open in native/speech/bookfin_speech.c).
//
// The host cannot ask an Android CPU, so these tests give the decision the
// feature bits that real phones report in AT_HWCAP. The bit numbers are the
// Linux kernel's for arm64 (arch/arm64/include/uapi/asm/hwcap.h).
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The features that a Cortex-A53 or a Cortex-A73 reports, as in a Pixel 2:
/// fp asimd evtstrm aes pmull sha1 sha2 crc32. Both are ARMv8.0 cores.
const armv80 = 0xff;

/// The features that the Cortex-A75 and Cortex-A55 of a Pixel 3 report, the
/// first ARMv8.2 phone cores: those of [armv80], and atomics fphp asimdhp
/// cpuid asimdrdm lrcpc dcpop asimddp.
const armv82 = 0x119fff;

/// The feature bits that the speech library needs, by the kernel's name.
const needed = {
  'crc32': 1 << 7,
  'atomics': 1 << 8,
  'fphp': 1 << 9,
  'asimdhp': 1 << 10,
  'asimdrdm': 1 << 12,
  'asimddp': 1 << 20,
};

void main() {
  final library = DynamicLibrary.open(
    Platform.environment['BOOKFIN_SPEECH_LIBRARY']!,
  );
  final runsSpeech = library
      .lookupFunction<Int32 Function(UnsignedLong), int Function(int)>(
        'bs_cpu_runs_speech',
      );

  test('an ARMv8.2 phone CPU with dot products and half floats runs the '
      'speech library', () {
    expect(runsSpeech(armv82), 1);
  });

  test('an ARMv8.0 phone CPU does not run the speech library', () {
    expect(runsSpeech(armv80), 0);
  });

  for (final MapEntry(key: name, value: bit) in needed.entries) {
    test('a CPU without $name does not run the speech library', () {
      expect(runsSpeech(armv82 & ~bit), 0);
    });
  }

  test('a CPU with more features than the library needs runs it', () {
    // Every bit of the low 32, as a later core can report.
    expect(runsSpeech(0xffffffff), 1);
  });
}
