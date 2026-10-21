# 過去年度のオールスター・レギュラー情報

## オールスター

`dart run tool_refresh_allstar_history.dart 2026` で1951年以降を取得。
2002年以降はNPB公式名簿、1951〜2001年は「プロ野球史 NPB MLB WBC」の年度別名簿。
2020年は開催中止。歴代資料の◇は補充選出。辞退選手は辞退マーク付きで保持し、
監督・コーチは除外。各選手の出典URLを保持し、守備位置は公式守備成績・出場記録で補完。
1981年以降は同年度・同球団のスタメン資料でも補完し、補完元を保持する。
守備位置を一意に確認できない選手は「守備位置未確認」に残す。
出典: https://npb.jp/allstar/ 、 https://data-man.com/proyakyu/history/?format=players&type=allstar&y=1951

## レギュラー

- NPB: `python3 tool_refresh_regular_history.py`。索引掲載の1981〜2025年、540球団年度を集計。
  日本シリーズ・CS・プレーオフ等は除外。前身球団は現在の球団にまとめ、近鉄は独立して保持。
- MLB: `dart run tool_refresh_regular_mlb.dart`。2005〜2025年の公式守備先発・試合別打順を取得。
  旧略称を現在の球団に対応させ、同姓同名は公式選手IDで区別。
- `regular-history.json` / `regular-history-mlb.json` を `/regular-history` APIで読み、既存スナップショットの不足年度を補完。
  `t_team_strength` は変更しない。既存年度の情報がある場合はその値を優先。
- 採用試合数と出典URLを保持。左右別投手起用・途中出場はスタメンから推測しない。
  過去年には資料にある先発投手欄を追加表示。左右別実績を推測しない。

出典: https://sta-men.jp/ 、 https://statsapi.mlb.com/api/v1/

## 球場画像

2軍12球場・地方162球場の内観と外観を、既存1軍画像をスタイル参照として生成。
内観は濃紺背景の俯瞰模型風、外観は透過背景の建築イラスト。
組み込みimage_genを使用。対象は `data/stadium-image-refresh-v2.json`。
各画像の生成プロンプトと参照画像は `data/stadium-image-prompts-v2.json`。
保存先は `assets/images/stadiums/{inside,outside}/*-generated-v2.png`。
生成済みの新画像を優先し、未生成箇所は従来のパスを使用。1軍画像は変更しない。
AI生成イメージとして表示し、現地写真や正確な建築図と区別する。
`python3 tool_verify_stadium_art.py` で画像の読込・重複・外観の透過を検査し、
目視確認用の一覧を `/tmp/koko-stadium-review` に出力する。
