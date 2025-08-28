FROM dart:stable AS build

# アプリをコピー
WORKDIR /app
COPY . .

# pub get
RUN dart pub get

# 本番用にコンパイル
RUN dart compile exe bin/server.dart -o bin/server

# 最終イメージ
FROM debian:stable-slim
WORKDIR /app
COPY --from=build /app/bin/server /app/server

# ポート指定（Render は環境変数 PORT を使う）
EXPOSE 8080
CMD ["./server"]