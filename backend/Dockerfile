# ========= Build stage =========
FROM dart:stable AS build
WORKDIR /app

# 依存関係の解決（キャッシュを効かせるため最初に pubspec 系だけ）
COPY pubspec.yaml pubspec.lock* ./
RUN dart pub get

# アプリ本体をコピー
COPY . .

# bin が無いとコンパイル時に失敗するので作成
RUN mkdir -p bin
# AOT コンパイル（index.dart → bin/server）
RUN dart compile exe index.dart -o bin/server

# ========= Runtime stage =========
FROM debian:stable-slim AS runtime
WORKDIR /app

# ルート証明書（https 用）
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# 実行ファイルと静的ファイルをコピー
COPY --from=build /app/bin/server /app/bin/server
COPY --from=build /app/public     /app/public

# Render が渡す PORT を使う
ENV PORT=10000
EXPOSE 10000

CMD ["/app/bin/server"]