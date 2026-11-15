#!/usr/bin/env bash
# Установка Стива одной командой:
#   curl -fsSL https://raw.githubusercontent.com/auurika/steve-helper/main/install.sh | bash
# Скачивает последнюю сборку, кладёт её в «Программы», снимает метку карантина (приложение подписано «для себя»,
# без неё macOS пишет, что оно повреждено) и запускает.
set -euo pipefail

URL="https://github.com/auurika/steve-helper/releases/latest/download/Steve-macOS.zip"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Скачиваю Стива…"
curl -fL --progress-bar "$URL" -o "$TMP/Steve.zip"
ditto -x -k "$TMP/Steve.zip" "$TMP"

DEST="${STEVE_INSTALL_DIR:-/Applications}"
if [ ! -w "$DEST" ]; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
fi

[ -n "${STEVE_SKIP_LAUNCH:-}" ] || pkill -x Steve 2>/dev/null || true
rm -rf "$DEST/Стив.app"
cp -R "$TMP/Стив.app" "$DEST/"
xattr -dr com.apple.quarantine "$DEST/Стив.app" 2>/dev/null || true

echo "Готово: $DEST/Стив.app"
[ -n "${STEVE_SKIP_LAUNCH:-}" ] || open "$DEST/Стив.app"
echo "Чтобы Стив болтал на любые темы, откройте Настройки → «Свободный разговор» → «Установить». Один раз, около 2,7 ГБ."
