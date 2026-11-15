#!/usr/bin/env bash
# Собирает готовое приложение build/Стив.app (всё нужное внутри пакета, ничего не ставится на компьютер).
# Использование: scripts/build-app.sh [debug|release]
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
APP="build/Стив.app"

echo "Сборка ($CONFIG)…"
swift build -c "$CONFIG"
BINARY="$(swift build -c "$CONFIG" --show-bin-path)/Steve"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Steve"

echo "Значок…"
swift scripts/make-icon.swift build
cp build/Steve.icns "$APP/Contents/Resources/Steve.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Steve</string>
  <key>CFBundleIdentifier</key><string>app.steve.helper</string>
  <key>CFBundleName</key><string>Стив</string>
  <key>CFBundleDisplayName</key><string>Стив</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>Steve</string>
  <key>CFBundleDevelopmentRegion</key><string>ru</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Стив слушает вас, чтобы понимать команды голосом. Речь распознаётся на устройстве.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Стив превращает вашу речь в текст прямо на Mac, без интернета.</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Стив добавляет события в «Календарь», когда вы об этом просите.</string>
  <key>NSAppleEventsUsageDescription</key><string>Стив создаёт заметки в приложении «Заметки» по вашей просьбе.</string>
</dict>
</plist>
PLIST

# подпись «для себя»: достаточно, чтобы приложение запускалось на этом Mac
codesign --force --deep --sign - -r='designated => identifier "app.steve.helper"' "$APP" # фиксированное требование: macOS не забывает разрешения после пересборки
echo "Готово: $APP"
