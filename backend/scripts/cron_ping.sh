#!/usr/bin/env bash
# ping.yml と同じ API を Render Cron Job から叩く。
# 必須環境変数: CRON_JOB
#   stats-team        → GET /fetchStatsTeamNPB
#   stats-player      → GET /fetchStatsPlayerNPB（リトライ付き）
#   games             → GET /fetchGamesNPB
#   stats-team-mlb    → GET /fetchStatsTeamMLB
#   stats-player-mlb  → GET /fetchStatsPlayerMLB
#   games-mlb         → GET /fetchGamesMLB
set -euo pipefail

BASE_URL="${PING_BASE_URL:-https://yakyuujapan.onrender.com}"
JOB="${CRON_JOB:-}"
BASE_URL="${BASE_URL%/}"

echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] CRON_JOB=${JOB} BASE_URL=${BASE_URL}"

if [[ -z "${JOB}" ]]; then
  echo "CRON_JOB is not set (stats-team | stats-player | games | *-mlb)" >&2
  exit 1
fi

call_simple() {
  local path="$1"
  echo "GET ${BASE_URL}${path}"
  curl -fsS --connect-timeout 30 --max-time 1800 "${BASE_URL}${path}"
  echo
}

call_player_stats() {
  local path="$1"
  echo "GET ${BASE_URL}${path}"
  curl --silent --show-error \
    --fail-with-body \
    --location \
    --retry 10 \
    --retry-delay 10 \
    --retry-all-errors \
    --connect-timeout 30 \
    --max-time 1800 \
    --write-out "\nHTTP status: %{http_code}\n" \
    "${BASE_URL}${path}"
}

case "${JOB}" in
  stats-team)
    call_simple "/fetchStatsTeamNPB"
    ;;
  stats-player)
    call_player_stats "/fetchStatsPlayerNPB"
    ;;
  games)
    call_simple "/fetchGamesNPB"
    ;;
  stats-team-mlb)
    call_simple "/fetchStatsTeamMLB"
    ;;
  stats-player-mlb)
    call_player_stats "/fetchStatsPlayerMLB"
    ;;
  games-mlb)
    call_simple "/fetchGamesMLB"
    ;;
  *)
    echo "Unknown CRON_JOB=${JOB}" >&2
    exit 1
    ;;
esac

echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] done"
