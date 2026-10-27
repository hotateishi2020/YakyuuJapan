#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

# Render は lib/ をビルドせず backend/public/ を配信する。
# ビルド成功時だけ配信用ファイルを更新する。
flutter build web --release --pwa-strategy=none
python3 tool/stamp_web_version.py
mkdir -p backend/public
# Publish the version marker last so clients only refresh after assets exist.
cp build/web/app_version.json build/app_version.pending.json
rm build/web/app_version.json
cp -R build/web/. backend/public/
mv build/app_version.pending.json backend/public/app_version.json
cp backend/public/app_version.json build/web/app_version.json
