#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

# Render は lib/ をビルドせず backend/public/ を配信する。
# ビルド成功時だけ配信用ファイルを更新する。
flutter build web --release
mkdir -p backend/public
cp -R build/web/. backend/public/
