# README【YakyuuJapan】

【Neon・Renderの請求】

[https://console.neon.tech/app/org-empty-fog-22600075/billing](https://console.neon.tech/app/org-empty-fog-22600075/billing)

[https://dashboard.render.com/billing](https://dashboard.render.com/billing)

【コミット&デプロイ記述】

cd /Users/standapp/StudioProjects/Koko 

sh tool/build_web.sh

git add . 

git commit -m "修正を調整しました。" 

git push 

cd /Users/standapp/StudioProjects/Koko/backend

【別途実行】

dart run tool_sql.dart

dart run tool_sql2.dart

コピペ：：dart run index.dart 

【データ登録用URL】

- ++[http://127.0.0.1:8080/](http://127.0.0.1:8080/)++fetchGamesNPB
- ++[http://127.0.0.1:8080/fetchStatsTeamNPB](http://127.0.0.1:8080/fetchStatsTeamNPB)++
- ++[http://127.0.0.1:8080/](http://127.0.0.1:8080/)++fetchStatsPlayerNPB
- ++[http://127.0.0.1:8080/](http://127.0.0.1:8080/)++insertNewPlayersNPB

【ショートカット】

関数をたたむショートカット（Cmd R → 0）

【サーバーでの定期実行処理】

ping.yml【github actionsでの定期実行処理】

render.yaml【Renderのcronjobでの定期実行処理】

【本番環境URL】

++[https://yakyuujapan.onrender.com/](https://yakyuujapan.onrender.com/)++