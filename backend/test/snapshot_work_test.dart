import 'dart:async';
import 'package:test/test.dart';
import '../app/SnapshotWork.dart';

void main() {
  tearDown(SnapshotWork.finish);
  test('game jobs wait for a snapshot and run one at a time in FIFO order', () async {
    expect(SnapshotWork.tryStart(), isTrue);
    final started = <String>[];
    final release = Completer<void>();
    final first = SnapshotWork.run(() async {
      started.add('npb');
      await release.future;
    });
    final second = SnapshotWork.run(() async { started.add('mlb'); });
    await Future<void>.delayed(Duration.zero);
    expect(started, isEmpty);
    SnapshotWork.finish();
    await Future<void>.delayed(Duration.zero);
    expect(started, ['npb']);
    expect(SnapshotWork.tryStart(), isFalse);
    release.complete();
    await Future.wait([first, second]);
    expect(started, ['npb', 'mlb']);
    expect(SnapshotWork.tryStart(), isTrue);
  });
  test('failed queued work releases the next game job', () async {
    expect(SnapshotWork.tryStart(), isTrue);
    final failed = SnapshotWork.run<void>(() async { throw StateError('failed'); });
    final checked = expectLater(failed, throwsStateError);
    var ran = false;
    final next = SnapshotWork.run(() async { ran = true; });
    SnapshotWork.finish();
    await checked;
    await next;
    expect(ran, isTrue);
    expect(SnapshotWork.tryStart(), isTrue);
  });
  test('overlapping builders defer and the next tick can run after failure', () async {
    expect(SnapshotWork.tryStart(), isTrue);
    expect(SnapshotWork.tryStart(), isFalse);
    try {
      throw StateError('build failed');
    } on StateError {
      // The existing persisted result is retained by each builder.
    } finally {
      SnapshotWork.finish();
    }
    expect(SnapshotWork.tryStart(), isTrue);
    expect(SnapshotWork.tryStart(), isFalse);
  });
}
