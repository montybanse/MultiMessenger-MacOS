#!/bin/bash
# Baut MultiMessenger.app (inkl. Share-Extension) aus dem Swift-Package und legt
# ein fertiges .app-Bundle im Ordner "dist" ab. Ad-hoc-signiert (lokal, kostenlos).
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="MultiMessenger"
EXT_NAME="MMShareExtension"
CONFIG="release"
BUILD_DIR=".build/${CONFIG}"
DIST="dist"
APP="${DIST}/${APP_NAME}.app"
APPEX="${APP}/Contents/PlugIns/ShareExtension.appex"

echo "==> Kompiliere (${CONFIG}) …"
swift build -c "${CONFIG}"

echo "==> Baue App-Bundle …"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP}/Contents/Info.plist"

# App-Icon erzeugen, falls noch nicht vorhanden
if [ ! -f "Resources/AppIcon.icns" ]; then
    ./make-icon.sh
fi
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"
fi

# --- Share-Extension (.appex) einbetten ---
echo "==> Baue Share-Extension …"
mkdir -p "${APPEX}/Contents/MacOS"
cp "${BUILD_DIR}/${EXT_NAME}" "${APPEX}/Contents/MacOS/${EXT_NAME}"
cp "Resources/ShareExtension-Info.plist" "${APPEX}/Contents/Info.plist"

# --- Signatur: stabiles lokales Zertifikat nutzen, sonst ad-hoc ---
SIGN_ID="-"   # "-" = ad-hoc (Fallback)
if security find-identity -v -p codesigning 2>/dev/null | grep -q "MultiMessenger Local"; then
    SIGN_ID="MultiMessenger Local"
    echo "==> Signiere mit stabilem Zertifikat \"${SIGN_ID}\" …"
else
    echo "==> Ad-hoc-Signatur (kein lokales Zertifikat gefunden – ./setup-cert.sh führt eines ein) …"
fi

# erst die innere Extension, dann die App
codesign --force --sign "${SIGN_ID}" "${APPEX}"
codesign --force --sign "${SIGN_ID}" "${APP}/Contents/MacOS/${APP_NAME}"
codesign --force --deep --sign "${SIGN_ID}" "${APP}"

echo ""
echo "Fertig: ${APP}"
echo "Starten mit:  open \"${APP}\""
echo "Tipp: einmal nach /Applications ziehen, damit Teilen-Menü & Icon registriert werden."
