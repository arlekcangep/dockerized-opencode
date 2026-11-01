#!/usr/bin/env bash
# Переводит контейнер в режим «PID 1 = opencode serve» и пересоздаёт его.
# Запускается из helper-контейнера (нужен docker.sock): пересоздание убивает
# процесс агента, поэтому нельзя запускать это изнутри основного контейнера.
set -uo pipefail

LOG=/repo/web-setup.log
exec > >(tee -a "$LOG") 2>&1

echo "=== $(date -Is) apply serve mode ==="
cd /repo || exit 1

docker compose -p opencode up -d --force-recreate
echo "compose rc=$?"

for _ in $(seq 1 90); do
  state=$(docker inspect -f '{{.State.Status}}' opencode 2>/dev/null || echo missing)
  [ "$state" = "running" ] && break
  sleep 1
done
echo "container state: $state"

echo "--- published ports ---"
docker port opencode || true

echo "--- listen sockets inside container ---"
docker exec opencode bash -lc '(ss -tln 2>/dev/null || netstat -tln 2>/dev/null) | head -20' || true

echo "--- HTTP check ---"
for i in $(seq 1 45); do
  code=$(docker exec opencode bash -lc 'curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:49374/' 2>/dev/null || echo 000)
  echo "try $i: http=$code"
  [ "$code" = "200" ] && break
  sleep 2
done

echo "--- API check (client discovers running service) ---"
docker exec opencode bash -lc 'opencode api get /api/info' || true

echo "--- processes inside container ---"
docker exec opencode ps aux | head -10 || true

echo "=== done $(date -Is) ==="
