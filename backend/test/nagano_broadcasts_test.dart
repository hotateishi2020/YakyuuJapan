import 'package:test/test.dart';
import '../app/NaganoBroadcasts.dart';
import '../app/GameBroadcasts.dart';

String schedule(List<String> titles,
        {String day = '20261027', String channel = 'SBC信越放送1'}) =>
    '''
<meta name="pv" content='{"broad_cast":"td","broad_cast_date":"$day"}'>
<div id="ch_area"><li class="js_channel"><p>$channel</p></li></div>
<div id="program_area"><ul>${titles.map((t) => '<li s="${day}1750" e="${day}2055"><a class="title_link" href="/tv_events/test"><p class="program_title">$t</p></a></li>').join()}</ul></div>''';
void main() {
  test('six Nagano channels and prefecture visibility', () {
    for (final station in naganoStations.entries) {
      final rows = parseNaganoBroadcasts(
          schedule(['プロ野球 阪神 対 巨人'], channel: station.key),
          DateTime(2026, 10, 27),
          '阪神',
          '巨人');
      expect(rows.single['name'], station.value);
      expect(filterGameBroadcasts(rows, '長野県'), hasLength(1));
      expect(filterGameBroadcasts(rows, ''), isEmpty);
      expect(filterGameBroadcasts(rows, '佐賀県'), isEmpty);
    }
  });
  test('NPB full-width text and MLB team aliases', () {
    expect(
        parseNaganoBroadcasts(schedule(['ＳＭＢＣ日本シリーズ２０２６「ソフトバンク×ＤｅＮＡ」']),
            DateTime(2026, 10, 27), 'ソフトバンク', 'DeNA'),
        hasLength(1));
    expect(
        parseNaganoBroadcasts(
            schedule(['MLB ワールドシリーズ「ブルワーズ」対「レイズ」'], channel: 'NHK総合1'),
            DateTime(2026, 10, 27),
            'ブリュワーズ',
            'レイズ'),
        hasLength(1));
  });
  test('exclude wrong dates, cards, news, highlights and replays', () {
    for (final title in [
      'MLB2分ハイライト ブルワーズ対レイズ',
      'ニュース MLB ブルワーズ対レイズ',
      'MLB ブルワーズ対レイズ 再放送',
      'MLB ドジャース対ヤンキース'
    ]) {
      expect(
          parseNaganoBroadcasts(
              schedule([title]), DateTime(2026, 10, 27), 'ブリュワーズ', 'レイズ'),
          isEmpty);
    }
    expect(
        parseNaganoBroadcasts(
            schedule(['プロ野球 阪神対巨人']), DateTime(2026, 10, 28), '阪神', '巨人'),
        isEmpty);
    expect(
        parseNaganoBroadcasts(schedule(['プロ野球 阪神対巨人'], channel: 'BS局'),
            DateTime(2026, 10, 27), '阪神', '巨人'),
        isEmpty);
  });
  test('split programming only emits one station', () {
    expect(
        parseNaganoBroadcasts(schedule(['プロ野球 阪神対巨人', 'プロ野球 阪神対巨人']),
            DateTime(2026, 10, 27), '阪神', '巨人'),
        hasLength(1));
  });
}
