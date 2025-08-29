# syntax=docker/dockerfile:1

FROM dart:stable AS build
WORKDIR /app

COPY pubspec.yaml pubspec.lock* ./
RUN dart pub get

COPY . .
RUN dart compile exe index.dart -o bin/server

FROM debian:bookworm-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/bin/server /app/server
COPY --from=build /app/public   /app/public

ENV PORT=8080
EXPOSE 8080
CMD ["/app/server"]