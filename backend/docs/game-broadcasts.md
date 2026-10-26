# 試合の配信・地域別放送

- アカウントの居住地は `m_user.residence_prefecture`。47都道府県のみ保存可能。
- `tool_migrate_residence.dart` は未設定の userid=1/2 を佐賀県/長野県に初期設定。
- `/game-broadcasts` は日付・対戦カードで公式放映表を抽出し、居住地で絞る。
- 現在の自動取得元はパ・リーグ6球団の月別公式放映表。純粋なセ・リーグ戦、MLB、未対応HTMLの取得は未実装。
- ラジオはradikoの都道府県別局一覧と当日の放送予定の積集合。地上波は明示された局の地域、または確認済み `prefectures` / `nationwide` の指定を使用。系列からの推測はしない。
- 地上波の自動地域対応表は佐賀・長野・福岡・関東。その他の地域は確認済み個別データで補完が必要。
- `data/game-broadcasts.json` は日付、home、away、broadcasts の配列。地域中継、配信動画直リンク、公式ロゴURLを出典とともに追加できる。
- サービスのトップページは配信動画URLとして使わない。直リンク未確認のサービスはロゴのみ（クリック不可）。
- ページ・ロゴは30分キャッシュ。更新は閲覧時。ネットワーク失敗時は未確認の放送を生成しない。
- ロゴは公式サイトのPNGアイコンまたはradikoの局ロゴ。画像未取得時は局名・サービス名で代替。

参照:
- https://www.softbankhawks.co.jp/news/broadcast/202610/
- https://radiko.jp/v3/station/list/JP41.xml
- https://radiko.jp/v3/station/list/JP20.xml
- https://tver.jp/live/special/leub1wc2x8
- https://www.hulu.jp/livetv/285

2026-10-27 修正:
- RKB地上波の受信対象に佐賀を追加（受信環境による）。
- 球団放映表の「TBSテレビ」だけでは地域局を取得できないため、日本シリーズ第1〜3戦（10/24・25・27）のRKB中継を確認済みデータで補完。TBS公式日程とユーザーからのRKB中継情報を使用。未確認の別番組・系列局に自動展開しない。
- 日程出典: https://www.tbs.co.jp/sports/baseball/onair.html
- 佐賀のRKB提供例: https://www.bunbun.co.jp/tv/channel_lineup.html
