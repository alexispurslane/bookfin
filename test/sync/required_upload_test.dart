import 'dart:async';
import 'dart:io';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/coordinator.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../catalog/controller_test.dart' show account;
import '../playback/incremental_save_test.dart' show bookmark;
import 'controlled_transport.dart';
import 'phone.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final sqlite in [false, true]) {
    group(sqlite ? 'SQLite required upload' : 'preferences required upload', () {
      late LocalResumeStore records;
      Phone? phone;
      late RecordSync sync;
      late JellyfinSession session;
      Future<void> Function()? exchange;
      final sent = <String>[];
      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        phone = sqlite ? await Phone.open('clear-records') : null;
        records = phone?.store ?? LocalResumeStore();
        session = account('alice');
        sent.clear();
        exchange = null;
        sync = RecordSync(
          records: records,
          transport: ControlledTransport(records, (who, _) async {
            final pending = await records.pendingUploads(who.scope.key);
            await exchange?.call();
            sent.addAll(
              pending
                  .map((action) => (action['value'] as Map?)?['title'])
                  .whereType<String>(),
            );
            await records.acknowledgeBatch(
              who.scope.key,
              pending.map(RecordJournal.identity),
            );
            return (replaced: 0);
          }),
        )..suspend();
        sync.bind(session);
      });
      tearDown(() => sync.dispose());
      Future<LocalResumeStore> restart() async {
        if (phone case final phone?) {
          await phone.restart();
          return phone.store;
        }
        return LocalResumeStore();
      }

      Future<void> save(String title, {String? key}) =>
          records.write(key ?? session.scope.key, {
            'bookmarks': [bookmark(title, title: title)],
          });

      test('required upload waits for the writer and durable server acknowledgment', () async {
        final writing = Completer<void>();
        final releaseWrite = Completer<void>();
        final uploading = Completer<void>();
        final releaseUpload = Completer<void>();
        records.registerWriter(
          account: () => session.scope.key,
          flush: () async {
            writing.complete();
            await releaseWrite.future;
            await save('Saved before clear');
          },
          refresh: () async {},
        );
        exchange = () async {
          uploading.complete();
          await releaseUpload.future;
        };
        var finished = false;
        final operation = sync
            .requireUploaded(session)
            .then((_) => finished = true);
        // A no-op scaffold finishes, which is the missing guarantee.
        await Future.any([writing.future, operation]);
        expect(finished, isFalse);
        expect(sent, isEmpty);
        releaseWrite.complete();
        await uploading.future;
        expect(finished, isFalse);
        expect(await records.hasPendingUploads(session.scope.key), isTrue);
        releaseUpload.complete();
        await operation;
        expect(sent, ['Saved before clear']);
        final reopened = await restart();
        expect(await reopened.hasPendingUploads(session.scope.key), isFalse);
        expect(
          (await reopened.read(
            session.scope.key,
          ))!['bookmarks'].single['title'],
          'Saved before clear',
        );
      });

      test(
        'a change saved during upload is also acknowledged before completion',
        () async {
          await save('First');
          exchange = () async {
            exchange = null;
            await save('During upload');
          };
          await sync.requireUploaded(session);
          expect(sent, containsAll(['First', 'During upload']));
          expect(
            await (await restart()).hasPendingUploads(session.scope.key),
            isFalse,
          );
        },
      );

      test(
        'a required upload failure keeps the pending record across restart',
        () async {
          await save('Keep me');
          exchange = () async => throw const SocketException('offline');
          await expectLater(
            sync.requireUploaded(session),
            throwsA(isA<Exception>()),
          );
          final reopened = await restart();
          expect(await reopened.hasPendingUploads(session.scope.key), isTrue);
          expect(
            (await reopened.read(
              session.scope.key,
            ))!['bookmarks'].single['title'],
            'Keep me',
          );
        },
      );

      test('a writer failure prevents the exchange', () async {
        await save('Already durable');
        records.registerWriter(
          account: () => session.scope.key,
          flush: () async => throw const FileSystemException('full'),
          refresh: () async {},
        );
        await expectLater(
          sync.requireUploaded(session),
          throwsA(isA<Exception>()),
        );
        expect(sent, isEmpty);
        expect(await records.hasPendingUploads(session.scope.key), isTrue);
      });

      test('a programming error is never converted into success', () async {
        final bug = StateError('writer bug');
        records.registerWriter(
          account: () => session.scope.key,
          flush: () async => throw bug,
          refresh: () async {},
        );
        await expectLater(sync.requireUploaded(session), throwsA(same(bug)));
      });

      for (final step in ['save', 'upload']) {
        for (final replacement in [false, true]) {
          test(
            '${replacement ? 'credential replacement' : 'account switch'} during $step cannot authorize clearing',
            () async {
              await save('Alice record');
              final entered = Completer<void>();
              final release = Completer<void>();
              Future<void> hold() async {
                entered.complete();
                await release.future;
              }

              if (step == 'save') {
                records.registerWriter(
                  account: () => session.scope.key,
                  flush: hold,
                  refresh: () async {},
                );
              } else {
                exchange = hold;
              }
              final operation = sync.requireUploaded(session);
              final outcome = expectLater(operation, throwsA(isA<Exception>()));
              await Future.any([
                entered.future,
                operation.catchError((Object _) {}),
              ]);
              expect(entered.isCompleted, isTrue);
              final next = account(replacement ? 'alice' : 'bob');
              sync.bind(next);
              release.complete();
              await outcome;
              expect(await records.read(account('bob').scope.key), isNull);
            },
          );
        }
      }

      test('a different account writer cannot block this account', () async {
        records.registerWriter(
          account: () => account('bob').scope.key,
          flush: () async => throw const FileSystemException('other account'),
          refresh: () async {},
        );
        await save('Alice only');
        await sync.requireUploaded(session);
        expect(sent, ['Alice only']);
      });
    });
  }
}
