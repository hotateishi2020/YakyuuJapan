# Stage 1: build env
FROM dart:stable AS build
WORKDIR /app

# 依存解決
COPY pubspec.* ./
RUN dart pub get --no-precompile

# ソース投入
COPY . .

# 便利ログ（トラブル時の確認用）
RUN dart --version && ls -la && echo "----" && dart analyze || true

# まずは run で起動（ログが読みやすい）
EXPOSE 8080
CMD ["dart", "run", "index.dart"]