#!/usr/bin/env bash
# Проверяет, что в готовой сборке Android лежит файл настроек .env.
#
# Без него приложение не знает адреса базы и падает до первого кадра —
# на экране остаётся заставка. Сборка при этом проходит «успешно»: именно
# так в релиз «latest» попал APK, который не открывался ни на одном
# телефоне (см. tool/prepare_android.sh). Эта проверка превращает такой
# случай в красную сборку.
#
# Запуск: bash tool/check_env_bundled.sh путь/к/app.apk|app.aab
set -euo pipefail
FILE="$1"
if unzip -l "$FILE" | grep -q 'flutter_assets/\.env$'; then
  echo "→ .env в сборке есть: $FILE"
else
  echo "::error::В сборке нет файла .env — приложение не запустится. См. tool/prepare_android.sh."
  exit 1
fi
