# syntax=docker/dockerfile:1

FROM dart:stable AS build
WORKDIR /app

# 依存だけ先に解決してキャッシュ効かせる
COPY pubspec.yaml pubspec.lock* ./
RUN dart pub get

# アプリ本体をコピー
COPY . .   # ← コンテキストが backend/ なのでこれでOK（backend/ を書かない）

# バイナリ化
RUN dart compile exe index.dart -o bin/server

# ---- ランタイム
FROM debian:bookworm-slim
WORKDIR /app
# Dart ランタイム（AOT 実行に必要）
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/bin/server /app/server
COPY --from=build /app/public   /app/public

ENV PORT=8080
EXPOSE 8080
CMD ["/app/server"]