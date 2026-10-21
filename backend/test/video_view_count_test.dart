import 'package:test/test.dart';
import '../app/VideoFeed.dart';

void main() {
  test('再生数の日本語と英語の省略表記を数値にする', () {
    expect(parseVideoViewCount('12,345 回視聴'), 12345);
    expect(parseVideoViewCount('1.2万 回視聴'), 12000);
    expect(parseVideoViewCount('2.5M views'), 2500000);
    expect(parseVideoViewCount('1日前'), isNull);
    expect(parseVideoViewCount('No views'), isNull);
  });
}
