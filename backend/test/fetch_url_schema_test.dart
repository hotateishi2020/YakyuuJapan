import 'package:test/test.dart';

import '../app/FetchURL.dart';

void main() {
  test('schema ensure does not wait indefinitely on startup DDL', () {
    expect(FetchURL.schemaEnsureTimeout, const Duration(seconds: 8));
  });
}
