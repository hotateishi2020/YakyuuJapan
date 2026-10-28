import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/mlb_event_name.dart';
void main() {
  test('event names only; retain positions and event labels', () {
    expect(mlbEventDetail('代走:アーロン・ジャッジ→大谷 翔平', []), '代走:ジャッジ→大谷');
    expect(mlbEventDetail('守備位置転換:ムーキー・ベッツ(右→遊)', []), '守備位置転換:ベッツ(右→遊)');
    expect(mlbEventDetail('盗塁:Shohei Ohtani', []), '盗塁:Ohtani');
    expect(mlbEventSurname('エリー・デラクルーズ', []), 'デラクルーズ');
    expect(mlbEventSurname('大谷翔平', [{'name_full':'大谷 翔平','name_last':'大谷'}]), '大谷');
    expect(mlbEventSurname('Luis De La Cruz', [{'name_full':'Luis De La Cruz','name_last':'De La Cruz'}]), 'DeLaCruz');
  });
  test('MLB batting names show the first three surname characters and retain event labels', () {
    expect(mlbBattingName('アーロン・ジャッジ', []), 'ジャッ');
    expect(mlbBattingName('エリー・デラクルーズ', []), 'デラク');
    expect(mlbBattingName('大谷 翔平', []), '大谷');
    expect(mlbBattingName('大谷翔平', [{'name_full': '大谷 翔平', 'name_last': '大谷'}]), '大谷');
    expect(mlbEventDetail('守備位置転換:エリー・デラクルーズ(遊→三)', [], shortenNames: true), '守備位置転換:デラク(遊→三)');
    expect(mlbEventDetail('投手:ゲリット・コール→クレイトン・カーショー', [], shortenNames: true), '投手:コール→カーシ');
  });
}
