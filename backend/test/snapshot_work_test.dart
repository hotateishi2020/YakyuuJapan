import 'package:test/test.dart';
import '../app/SnapshotWork.dart';

void main() {
  tearDown(SnapshotWork.finish);
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
