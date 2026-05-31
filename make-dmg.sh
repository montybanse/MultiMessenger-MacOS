#!/bin/bash
# Baut eine verteilbare .dmg aus dist/MultiMessenger.app.
# Enthält die App + einen Symlink auf /Applications (Drag-to-install).
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MultiMessenger"
APP="dist/${APP_NAME}.app"
DMG="dist/${APP_NAME}.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

if [ ! -d "$APP" ]; then
    echo "Fehler: $APP fehlt. Erst ./build-app.sh ausführen."
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo 0.1.0)"

echo "==> Staging vorbereiten …"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> Erzeuge ${DMG} …"
rm -f "$DMG"
hdiutil create -volname "${APP_NAME} ${VERSION}" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null

echo ""
echo "✅ Fertig: ${DMG}"
echo "Größe: $(du -h "$DMG" | cut -f1)"
echo ""
echo "Der Empfänger öffnet die .dmg und zieht MultiMessenger auf 'Applications'."
echo "Hinweis: Da nur lokal/selbst-signiert, muss der Empfänger die App beim"
echo "ersten Start per Rechtsklick → Öffnen starten (Gatekeeper)."
