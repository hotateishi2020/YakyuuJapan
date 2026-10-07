import 'package:test/test.dart';

import '../app/FetchURL.dart';

void main() {
  test('schema ensure waiters do not block initial display forever', () {
    expect(FetchURL.schemaEnsureTimeout, const Duration(seconds: 8));
  });
}
