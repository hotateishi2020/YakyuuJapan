# README【YakyuuJapan】

【コミット&デプロイ記述】

cd /Users/standapp/StudioProjects/Koko 

sh tool/build_web.sh

git add . 

git commit -m "選手の契約情報を参照できる機能を追加しました。" 

git push 

cd /Users/standapp/StudioProjects/Koko/backend

dart run tool_sql.dart

【別途実行】

dart run tool_sql2.dart

コピペ：：dart run index.dart 

【データ登録用URL】

- ++[[http://127.0.0.1:8080/](http://127.0.0.1:8080/)++fetchGamesNPB]([http://127.0.0.1:8080/fetchGamesNPB](http://127.0.0.1:8080/fetchGamesNPB))
- ++[http://127.0.0.1:8080/fetchStatsTeamNPB](http://127.0.0.1:8080/fetchStatsTeamNPB)++
- ++[[http://127.0.0.1:8080/](http://127.0.0.1:8080/)++fetchStatsPlayerNPB]([http://127.0.0.1:8080/fetchStatsPlayerNPB](http://127.0.0.1:8080/fetchStatsPlayerNPB))
- ++[[http://127.0.0.1:8080/](http://127.0.0.1:8080/)++insertNewPlayersNPB]([http://127.0.0.1:8080/insertNewPlayersNPB](http://127.0.0.1:8080/insertNewPlayersNPB))

【ショートカット】

関数をたたむショートカット（Cmd R → 0）

【サーバーでの定期実行処理】

ping.yml【github actionsでの定期実行処理】

render.yaml【Renderのcronjobでの定期実行処理】

【本番環境URL】

++[https://yakyuujapan.onrender.com/](https://yakyuujapan.onrender.com/)++

経歴・追加功績の更新は `cd backend` 後に `dart run tool_refresh_career_honors.dart 2026`、登録確認は `dart run tool_verify_career_honors.dart 2026`。公式プロフィール・受賞一覧・代表名簿・MLBドラフト資料を照合し、`t_strength_player_status` と戦力スナップショットへ追記します。未分類の海外プロ球団を社会人チームとして扱いません。五輪・WBCの「レギュラー級」は大会の過半数の野手先発、投手は2先発または3登板以上という表示上の基準です。功績の評価面積はアプリ独自の比較です。取得失敗は `/tmp/koko-achievements-年度/career-honors-errors.json` に記録します。
