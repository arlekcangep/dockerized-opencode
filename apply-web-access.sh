#!/usr/bin/env bash
# Применяет проброс веб-порта OpenCode (выполняется из helper-контейнера на VM).
# Пишет результат в /repo/web-setup.log, чтобы его можно было прочитать снаружи.
set -uo pipefail

LOG=/repo/web-setup.log
exec > >(tee -a "$LOG") 2>&1

echo "=== $(date -Is) apply web access ==="
cd /repo || exit 1

docker compose -p opencode up -d
echo "compose rc=$?"

for _ in $(seq 1 60); do
  state=$(docker inspect -f '{{.State.Status}}' opencode 2>/dev/null || echo missing)
  [ "$state" = "running" ] && break
  sleep 1
done
echo "container state: $state"

echo "--- published ports ---"
docker port opencode || true

echo "--- listen sockets inside container ---"
docker exec opencode bash -lc '(ss -tln 2>/dev/null || netstat -tln 2>/dev/null) | head -20' || true

echo "--- HTTP check via container bridge IP ---"
for i in $(seq 1 45); do
  code=$(docker exec opencode bash -lc 'curl -s -o /dev/null -w "%{http_code}" http://172.18.0.2:49374/' 2>/dev/null || echo 000)
  echo "try $i: http=$code"
  [ "$code" = "200" ] && break
  sleep 2
done

echo "--- pairing link (одноразовый, 5 минут) ---"
docker exec opencode bash -lc 'opencode pair --url http://192.168.100.100:49374' || true

echo "=== done $(date -Is) ==="
