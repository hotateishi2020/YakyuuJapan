# ---- build stage ----
    FROM dart:stable AS build
    WORKDIR /app/backend
    
    # 依存関係解決
    COPY backend/pubspec.* ./ 
    RUN dart pub get
    
    # 残りをコピー（public を含む）
    COPY backend/ ./
    
    # 実行バイナリを作成
    RUN dart compile exe index.dart -o bin/server
    
    # ---- run stage ----
    FROM debian:bookworm-slim
    WORKDIR /app/backend
    
    # 生成物と必要ファイルだけを持ってくる
    COPY --from=build /runtime/ /
    COPY --from=build /app/backend/bin/server /app/backend/bin/server
    COPY --from=build /app/backend/public /app/backend/public
    
    # Render が与える環境変数 PORT を使う
    ENV PORT=8080
    EXPOSE 8080
    
    CMD ["/app/backend/bin/server"]