#!/bin/bash
# Erstellt EINMALIG ein selbst-signiertes Code-Signing-Zertifikat namens
# "MultiMessenger Local" im Login-Schlüsselbund. Damit signiert build-app.sh die
# App immer mit demselben Fingerabdruck → der Schlüsselbund fragt nicht mehr bei
# jedem Update erneut, und macOS verknüpft App-Icon/Notifications stabil.
#
# Es wird dein Schlüsselbund-Passwort abgefragt (von macOS, nicht im Skript).
set -euo pipefail
cd "$(dirname "$0")"

NAME="MultiMessenger Local"
KC="$HOME/Library/Keychains/login.keychain-db"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
    echo "✅ Zertifikat \"$NAME\" existiert bereits – nichts zu tun."
    exit 0
fi

echo "==> Erzeuge Schlüssel + Zertifikat (Code Signing) …"
cat > "$TMP/cfg.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $NAME
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -config "$TMP/cfg.cnf" >/dev/null 2>&1

# OpenSSL 3 verschlüsselt .p12 standardmäßig so, dass der macOS-Schlüsselbund
# sie NICHT importieren kann ("MAC verification failed"). Daher das Legacy-
# Verfahren (3DES/SHA1) erzwingen – das versteht macOS.
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/id.p12" -passout pass:mm -name "$NAME" \
    -legacy -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES >/dev/null 2>&1

echo "==> Importiere ins Login-Schlüsselbund …"
security import "$TMP/id.p12" -k "$KC" -P "mm" -T /usr/bin/codesign -A

echo "==> Erlaube codesign den nicht-interaktiven Zugriff …"
echo "    (macOS fragt jetzt EINMAL nach deinem Schlüsselbund-Passwort.)"
security set-key-partition-list -S apple-tool:,apple: -s "$KC" >/dev/null 2>&1 || true

echo "==> Als für Code-Signierung vertrauenswürdig markieren …"
security add-trusted-cert -p codeSign -k "$KC" "$TMP/cert.pem" 2>/dev/null || true

echo ""
echo "✅ Fertig. Identität:"
security find-identity -v -p codesigning | grep "$NAME" || \
    echo "   (Falls hier nichts steht: App einmal ab-/anmelden, dann ./build-app.sh erneut.)"
echo ""
echo "Jetzt:  ./build-app.sh   (nutzt das Zertifikat automatisch)"
