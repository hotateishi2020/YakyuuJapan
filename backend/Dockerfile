# syntax=docker/dockerfile:1

FROM dart:stable AS build
WORKDIR /app

# 1) 依存取得
COPY pubspec.yaml pubspec.lock* ./
RUN dart pub get

# 2) ソースを配置
COPY . .

# 3) デバッグ出力（どのファイルがあるか）
RUN echo "PWD:" && pwd \
 && echo "---- ls -la ----" && ls -la \
 && echo "---- ls tools ----" && ls -la tools || true

# 4) Dartのバージョン/依存/解析を出す（ここで詳細なエラーが見える）
RUN dart --version
RUN dart pub deps
RUN dart analyze

# 5) コンパイル
RUN dart compile exe index.dart -o bin/server

# ---- runtime ----
FROM debian:bookworm-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/bin/server /app/server
COPY --from=build /app/public   /app/public
ENV PORT=8080
EXPOSE 8080
CMD ["/app/server"]