# Правила

## Сначала ответ, потом действия

- Начинай ответ с прямого ответа на вопрос или с короткого подтверждения задачи.
- Только после этого выполняй действия, показывай детали, код и пояснения.
- Не начинай с описания процесса, если можно сразу дать ответ или решение.

_Записано по просьбе пользователя 2026-10-25._

## Где я нахожусь (окружение)

- Я работаю **внутри Docker-контейнера** (есть `/.dockerenv`), а не на хосте.
- **Образ** собирается из `/workspace/opencode/Dockerfile.opencode` — это источник
  правды для окружения. **Compose:** `/workspace/opencode/docker-compose.yml`.
- **Конфигурация OpenCode:** каталог `/workspace/opencode/config/` (на хосте),
  смонтирован в `/home/appuser/.config/opencode/` (vboxsf).
  - `opencode.json` — провайдеры и **LSP**;
  - `cli.json`, `service.json` — настройки клиента/сервиса;
  - `AGENTS.md` — этот файл (глобальная память).
- **Проекты:** `/workspace` (на хосте `/home/vagrant/shared`), общий каталог.
- **Пользователь:** `appuser` (uid/gid 1000), **без `sudo`**.
- **Docker на хосте (Do-oD):** сокет `/var/run/docker.sock` проброшен, я в группе
  `docker` (gid 986). **У меня есть права создавать и запускать контейнеры на самой
  хостовой системе** — `docker run`, `docker compose`, сборка образов и т. п.
  (client/server 29.9.2). Это реальные контейнеры на хосте, а не только внутри
  моего — запускать аккуратно (предпочитать `--rm` и убирать за собой).
- ⚠️ **Всё, что поставлено в контейнере вручную, теряется при пересборке.**
  Ставить инструменты только через изменение `Dockerfile.opencode` (см. раздел ниже).
- **Временный каталог контейнера:** `~/opencodetmp` — **один** named volume
  (`opencodetmp` в docker-compose), смонтированный вне vboxfs (там работают симлинки,
  поэтому pip/venv живые). Внутри — всё временное: venv проектов
  (`~/opencodetmp/venvs/<проект>`, для Persinder — `~/opencodetmp/venvs/persinder`),
  кэши npm (`~/opencodetmp/cache/npm`, `npm_config_cache`) и NuGet
  (`~/opencodetmp/cache/nuget/packages`, `NUGET_PACKAGES`) и прочее.
  venv создаётся/восстанавливается скриптом проекта (`Persinder/scripts/venv.sh`).
- ⚠️ **`opencodetmp` — одноразовый и восстановимый.** Named volume живёт внутри Docker
  внутри VM; при **пересоздании VM или тома он пропадёт**. Источник правды — репозиторий
  и скрипты, а не содержимое каталога. После пересоздания просто прогнать
  `scripts/venv.sh`.

## Инвентарь инструментов

База: Ubuntu 22.04.5 (jammy), 2 CPU, ~7.8 ГиБ RAM, `/workspace` ~325 ГБ.

| Инструмент | Путь | Версия / статус |
|---|---|---|
| python3 | `/usr/bin/python3` | 3.10.12 (только stdlib) |
| pip / pip3 | `/usr/bin/pip3` | 22.0.2 (Python 3.10) |
| sqlite3 (модуль Python) | stdlib | 3.37.2, **FTS5 есть** |
| sqlite3 (CLI) | — | НЕТ |
| jq | — | НЕТ |
| node | `/usr/bin/node` | v24.22.2 |
| npm | `/usr/bin/npm` | 11.19.1 |
| npx | `/usr/bin/npx` | есть |
| java / javac | `/opt/java/openjdk/bin/` | OpenJDK 21.0.13 |
| mvn | `/usr/bin/mvn` | Apache Maven 3.6.3 |
| jdtls (Java LSP) | `/opt/jdtls/launcher.jar` | есть |
| dotnet | `/usr/local/bin/dotnet` | 10.0.403 |
| csharp-ls | `/usr/local/bin/csharp-ls` | есть |
| git | `/usr/bin/git` | 2.34.1 |
| bash / sh | `/usr/bin/` | есть |
| curl / wget | `/usr/bin/` | есть |
| docker (CLI) | `/usr/bin/docker` | Do-oD через сокет хоста |
| docker compose | плагин | v5.6.1 |
| shellcheck | `/usr/bin/shellcheck` | есть |
| typescript | npm -g | 7.0.2 |
| typescript-language-server | npm -g | 6.0.2 |
| bash-language-server | npm -g | 5.8.1 |
| yaml-language-server | npm -g | 2.0.0 |
| ruff | `/usr/local/bin/ruff` | 0.17.3 |
| mypy | `/usr/local/bin/mypy` | 2.4.1 |
| pyright (+langserver) | `/usr/bin/pyright` | 1.1.414 |
| pytest | `/usr/local/bin/pytest` | 9.2.0 |
| build | `python3 -m build` | 1.6.1 |
| snowballstemmer | pip | есть |
| uv | — | НЕТ |

**Python-тулинг установлен** (Dockerfile: секция 1 — `python3-pip/venv/dev`;
секция 4 — `pyright@1.1.414` и LSP `pyright-langserver`; секция 4b — `pip3 install
ruff mypy pytest build snowballstemmer`). Проверено на Persinder: `ruff check`,
`ruff format`, `pyright`, `mypy`, `pytest` — всё зелёное.

⚠️ **Кэш ruff на vboxsf.** По умолчанию ruff пишет `.ruff_cache` в проекте и падает
(`Text file busy`, os error 26). Запускать с `--no-cache`
(или `--cache-dir` вне vboxfs).

## Правило об установке инструментов

Если нужного инструмента нет:

1. **Сначала спросить разрешение у пользователя** — ничего не ставить молча.
2. Ставить так, **чтобы не пропало**: обновить `Dockerfile.opencode`, а не только
   текущий контейнер. Куда именно:
   - системный пакет (apt) → список в **секции 1**;
   - Python-пакет (pip) → **секция 4b**;
   - npm-пакет/CLI → `npm install -g` в **секции 4**, версию — через `ARG ..._VERSION`;
   - новый LSP → запись в блок `lsp` файла `config/opencode.json`.
3. Версии **пинить** (`ARG`), как это сделано для остальных инструментов.
4. После правок попросить пользователя пересобрать:
   `docker compose build opencode && docker compose up -d opencode`.
5. Обновить этот инвентарь в `AGENTS.md`.

_Инвентарь составлен 2026-11-04._
