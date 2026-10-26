# 選手の同一性と表示名

`m_player.name_patterns`（text[]）に元の表記を件数制限なく保存します。
`name_pattern_keys` は照合用、`name_ja` / `name_en` は表示用です。
`identity_sources` は名前空間ごとの公式ID（MLB、NPB、Yahoo）を保持します。
字体・アクセント・空白・中黒の違いは正規化しますが、姓やイニシャルだけを
一意な本人の証拠として登録・統合することはありません。

## 登録

- `PlayerIdentity.ensure` を使用。公式ID → 登録済み別名 → 出典プロフィールの順で照合。
- 新しい英語名と日本語名は、公式プロフィールと日本語名鑑の生年月日・身長・投打を照合。
- 日本語名が確認できない場合、推測でカタカナ化せず元の英語名を保持。
- 候補が複数ある場合、`t_player_identity_review` に記録して登録を保留。
- MLBの出典なしの新しい実況名は新規マスターを作成せず、プロフィール確認を待つ。
- DBトリガーも別名を保持し、英語更新による日本語名の上書きと古いSQLからの重複INSERTを防ぐ。
- MLB/NPB公式IDには有効行に対する一意インデックスを設定。
- 旧 `selectInsertNewPlayersNPB` は使用しない。`FROM m_player WHERE NOT EXISTS` が
  既存行数分の新規行を生成する経路は、共通登録処理へ置き換え済み。

## スキーマ適用・検証

バックエンドコードを配備する前に backend ディレクトリで実行します。

```sh
dart run tool_setup_player_identity.dart
dart run tool_verify_player_identity.dart
```

検証ツールのテスト用登録・更新は必ずロールバックします。

## 再監査・情報収集

```sh
dart run tool_audit_player_identity.dart
dart run tool_identity_schema_audit.dart
python3 tools/identity/collect_mlb_names.py
python3 tools/identity/plan_player_identity.py
```

収集先はスポーツナビの30球団選手名鑑とMLB公式Stats API。
`data/mlb-player-name-evidence.json` に取得日、出典、照合項目を保存します。
NPB/MLB公式IDの橋渡しには既存の出典付きChadwick対応表も使用します。
キケ／エンリケの日本語表記は以下も確認しました。

- https://www.mlb.com/player/enrique-hernandez-571771
- https://www.jsports.co.jp/baseball/mlb/player/1100/

同じ生年月日だけで統合しません。異なるMLB公式ID、異なるNPB公式数字IDがある
候補は統合せずレビューへ送ります。誕生日未登録の旧プレースホルダーは、
現所属球団と名鑑の**フルネーム**が一致するものだけを補足確認します。

## 計画の適用

```sh
dart run tool_apply_player_identity.dart                 # 件数確認のみ
dart run tool_apply_player_identity.dart --check         # 実DB内で検証し全変更をロールバック
dart run tool_apply_player_identity.dart --apply
```

`--plan=パス` で別の計画を指定可能。適用済み計画の再実行は拒否します。
2026-10-24 の初回計画と補足計画は、それぞれ
`data/player-identity-plan.json` と `data/player-identity-followup-plan.json` に保存。
これらを再実行せず、新しい監査から計画を作成してください。

- 統合前の全対象行は `t_player_identity_migration_backup` に実行日時・表名別に保存。
- `t_player_identity_merge` に元の選手行、最終ID、根拠を保存。
- 旧選手行は削除せず `merged_into_player_id` を持つ無効行にする。
- 成績、予想、試合、画像、選手詳細の参照を最終IDへ付け替える。
- 打撃・投球はそれぞれ出場量が最も揃った行のブロックを保持し、重複の成績を加算しない。
- 同じキーのキャッシュ等は正規行を優先。元の行は上記の退避表に残る。
- 保存済みMLB選手一覧を公式ID／一意な別名で日本語化し、当年の個人成績スナップショットを再作成。

未確認データは `SELECT * FROM t_player_identity_review WHERE status='pending'` で確認できます。
過去年度を含む全選手への推測による一括翻訳や、未確認の同姓選手の統合は行いません。

## 2026-10-24 適用結果

- 重複7,928行を統合。MLB公式IDを持つ1,376人に日本語名を設定。
- 2026年MLB個人成績の英語のみの選手名は0件。本人確認未完了23件は保留。
- 上記2計画に加え `player-identity-observed-alias-plan.json` と
  `player-identity-final-plan.json` を適用済み。expanded / roster-history は
  finalに含まれるため個別に再適用しない。
- NPB公式12球団の名簿・プロフィールの過去所属、Yahooのランキング44ページも照合。
  `player-name-link-evidence.json` に出典を保存。
- Brooks Lee / Taj Bradley、Austin Riley / Dylan Leeで混在していた
  別人の成績は、打撃・投球記録と公式プロフィールを確認して本人へ付け替えた。
  final計画の `role_splits` に根拠を保存。元のプロフィール由来キャッシュも退避。
- NPB↔MLB移籍でも既存の出典付きID対応表で同じ選手を検索する。
  現在のNPB公式名簿取込だけが所属球団を更新し、過去成績の取込で現所属を戻さない。
- DB検証結果は `data/player-identity-verification.json`、保留一覧は
  `data/player-identity-pending-review.json`。

関連テスト101件、静的解析、バックエンド実行ファイルのビルドを確認済み。
既存の `player_snapshot_read_test.dart` には、選手名簿の追加読込とSQLモックの
期待値が一致しない失敗が1件あり、変更前のHEADでも同じ失敗を確認した。
新しい取込・照合処理の稼働にはバックエンドの再起動／配備が必要。
DB制約、統合データ、保存済み表示データへの修正は適用済み。

## NPBの追加監査（2026-10-24）

`plan_npb_identity.py` は全有効選手の正規化フルネームを球団・年度をまたいで比較し、
NPB公式プロフィールの生年月日と過去所属で同一人物を確認します。
異なる公式ID・生年月日の選手は統合しません。名前だけ一致する外国人選手も保留します。
字体違いと移籍前後の登録、MLB移籍選手のNPB時代の登録も対象です。

```sh
dart run tool_audit_player_identity.dart
python3 tools/identity/plan_npb_identity.py
dart run tool_apply_player_identity.dart --check --plan=data/npb-player-identity-plan.json
dart run tool_apply_player_identity.dart --apply --plan=data/npb-player-identity-plan.json
dart run tool_verify_npb_identity.dart
```

出典と統合根拠は `data/npb-player-identity-plan.json` に保存。
適用済みの計画は再実行せず、新しい監査から別計画を作成します。
検証ツールは公式IDでの照合・旧IDへの参照が残っていないことを確認し、
未解決候補をDBレビューに記録します。結果は `data/npb-player-identity-verification.json`。

追加計画は適用済み：29人分の重複40行を統合。
取込時の旧名・公式IDでの照合と、移籍前・過年度成績からの参照を維持します。
同姓別人が確認できる候補は別人として保持し、根拠不足の候補は確認待ちです。
