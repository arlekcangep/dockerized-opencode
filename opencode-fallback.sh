#!/usr/bin/env bash
#
# opencode-fallback.sh
# --------------------
# Обёртка над `opencode` с автоматическим фолбэком:
#   1. Пытается работать с основной моделью (deepseek).
#   2. При ошибке / лимите (exit code != 0 или строка rate-limit в stderr)
#      переключает модель на nemotron-3.5-super-vl-free и перезапускает.
#
# Переменные окружения:
#   OPENCODE_PRIMARY_MODEL   — основная модель (по умолчанию из opencode.json)
#   OPENCODE_FALLBACK_MODEL  — модель-фолбэк (по умолчанию opencode/nemotron-3.5-super-vl-free)
#   OPENCODE_MODE            — "tui" (по умолчанию) или "serve"
#   OPENCODE_PORT            — порт для serve (по умолчанию 49374)
#   OPENCODE_HOSTNAME        — хост для serve (по умолчанию 0.0.0.0)
#
# Использование:
#   ./opencode-fallback.sh            # TUI с фолбэком
#   OPENCODE_MODE=serve ./opencode-fallback.sh   # serve с фолбэком

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config/opencode.json"

PRIMARY_MODEL="${OPENCODE_PRIMARY_MODEL:-opencode/deepseek-v4.1-flash-free}"
FALLBACK_MODEL="${OPENCODE_FALLBACK_MODEL:-opencode/nemotron-3.5-super-vl-free}"
MODE="${OPENCODE_MODE:-tui}"
PORT="${OPENCODE_PORT:-49374}"
HOSTNAME="${OPENCODE_HOSTNAME:-0.0.0.0}"

# --- helpers ----------------------------------------------------------------

log() {
  echo "[opencode-fallback] $*"
}

set_model() {
  local model="$1"
  log "Переключаю модель на: $model"
  # Python — самый надёжный способ править JSON без зависимостей от jq
  python3 - "$CONFIG_FILE" "$model" <<'PY'
import json, sys
path, model = sys.argv[1], sys.argv[2]
with open(path) as f:
    cfg = json.load(f)
cfg["model"] = model
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PY
  log "Конфиг обновлён: $CONFIG_FILE"
}

is_rate_limit_or_error() {
  local output="$1"
  # Признаки: 429, rate limit, quota, unauthorized, bad gateway, timeout
  echo "$output" | grep -qiE "429|rate.?limit|quota|unauthorized|401|403|502|503|504|timed.?out|model.*not.*found|invalid.*api.?key" && return 0
  return 1
}

run_tui() {
  local model="$1"
  shift
  log "Запуск TUI с моделью: $model"
  set_model "$model"
  opencode "$@"
  local code=$?
  return $code
}

run_serve() {
  local model="$1"
  shift
  log "Запуск serve с моделью: $model (порт $PORT, хост $HOSTNAME)"
  set_model "$model"
  opencode serve --service --hostname "$HOSTNAME" --port "$PORT" "$@"
  local code=$?
  return $code
}

# --- main -------------------------------------------------------------------

log "Первичная модель: $PRIMARY_MODEL"
log "Фолбэк-модель:    $FALLBACK_MODEL"
log "Режим:            $MODE"

ATTEMPT=1
CURRENT_MODEL="$PRIMARY_MODEL"

while true; do
  log "Попытка #$ATTEMPT (модель: $CURRENT_MODEL)"

  if [ "$MODE" = "serve" ]; then
    OUTPUT=$(run_serve "$CURRENT_MODEL" 2>&1)
    CODE=$?
  else
    OUTPUT=$(run_tui "$CURRENT_MODEL" 2>&1)
    CODE=$?
  fi

  if [ "$CODE" -eq 0 ]; then
    log "Завершено успешно (код 0)."
    exit 0
  fi

  log "Завершено с кодом $CODE."

  # Проверяем, не закончились ли попытки
  if [ "$CURRENT_MODEL" = "$FALLBACK_MODEL" ]; then
    log "Фолбэк-модель тоже завершилась с ошибкой. Фолбэков больше нет."
    echo "$OUTPUT"
    exit "$CODE"
  fi

  # Проверяем, стоит ли переходить на фолбэк
  if is_rate_limit_or_error "$OUTPUT"; then
    log "Обнаружен признак ошибки/лимита — перехожу на фолбэк."
  else
    log "Ошибка не похожа на лимит/блокировку. Проверьте вывод выше."
    echo "$OUTPUT"
    exit "$CODE"
  fi

  CURRENT_MODEL="$FALLBACK_MODEL"
  ATTEMPT=$((ATTEMPT + 1))
done
