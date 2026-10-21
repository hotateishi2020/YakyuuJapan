import 'package:test/test.dart';
import '../app/BaseballTimeline.dart';

void main() {
  test('年表は組織と選択年で絞り込み、公式カタログを読み込む', () {
    final npb = readBaseballTimeline('npb', 2022);
    expect(npb, isNotEmpty);
    expect(npb.every((e) => e['org'] == 'npb' && e['year'] <= 2022), isTrue);
    expect(npb.where((e) => e['year'] == 2022 && '${e['text']}'.contains('三冠王')), hasLength(1));
    expect(npb.where((e) => e['year'] == 2015 && '${e['text']}'.contains('トリプルスリー')), hasLength(2));
    expect(npb.map((e) => e['category']).toSet(), containsAll(timelineCategories));
    expect(npb.every((e) => '${e['source']}'.startsWith('https://')), isTrue);
    final mlb = readBaseballTimeline('mlb', 2022);
    expect(mlb.every((e) => e['org'] == 'mlb'), isTrue);
    expect(mlb.any((e) => '${e['text']}'.contains('262安打')), isTrue);
  });
}
