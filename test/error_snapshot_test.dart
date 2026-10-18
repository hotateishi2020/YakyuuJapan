import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/error_snapshot.dart';
import '../backend/app/ErrorSnapshot.dart';

void main() {
  testWidgets('captures painted app and stores PNG privately', (tester) async {
    await tester.pumpWidget(RepaintBoundary(
      key: ErrorSnapshot.boundaryKey,
      child: const MaterialApp(home: Scaffold(body: Text('エラー発生時の画面'))),
    ));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final encoded = await ErrorSnapshot.capture();
      expect(encoded, isNotNull);
      final directory =
          await Directory.systemTemp.createTemp('error-snapshot-test-');
      try {
        final store = ErrorSnapshotStore(path: directory.path);
        final id = await store.save(encoded);
        expect(id, isNotNull);
        expect(await store.read(id!), base64Decode(encoded!));
        expect(await store.read('../outside'), isNull);
      } finally {
        await directory.delete(recursive: true);
      }
    });
  });

  test('unmounted screen and invalid attachments do not prevent logging',
      () async {
    expect(await ErrorSnapshot.capture(), isNull);
    expect(ErrorSnapshotStore.decode('not png'), isNull);
    expect(
        ErrorSnapshotStore.decode(base64Encode(List.filled(100, 0))), isNull);
    expect(ErrorSnapshotStore.decode('a' * 2000001), isNull);
  });
}
