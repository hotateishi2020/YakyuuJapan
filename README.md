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

flutter build web --release 

rm -rf backend/public/* 

cp -R build/web/* backend/public/ 

git add . 

git commit -m "ゲーム差を視覚的に表現する図を表示するようにしました。" 

git push 

cd /Users/standapp/StudioProjects/Koko/backend

dart run tool_sql.dart

dart run tool_sql2.dart

コピペ：：dart run index.dart 