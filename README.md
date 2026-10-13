# koko

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

↓デプロイ記述↓

cd /Users/standapp/StudioProjects/Koko 

sh tool/build_web.sh

`lib/` の変更は、そのままでは公開サイトに反映されません。このスクリプトで
リリースビルドと `backend/public/` へのコピーを行い、生成ファイルもコミットしてください。

git add . 

git commit -m "表示の修正を行いました。" 

git push 

cd /Users/standapp/StudioProjects/Koko/backend

dart run tool_sql.dart

dart run tool_sql2.dart

コピペ：：dart run index.dart
