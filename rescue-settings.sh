#!/bin/bash
# Stellt store.json (Dienste/Workspaces) aus dem neuesten Time-Machine-Snapshot
# wieder her, der noch Dienste enthält. Mountet das Daten-Volume read-only.
set -uo pipefail

DEST="$HOME/Library/Application Support/MultiMessenger/store.json"
REL="mba/Library/Application Support/MultiMessenger/store.json"
MNT=/tmp/mm_tmsnap
DATADEV=$(diskutil info /System/Volumes/Data | awk -F: '/Device Node/{gsub(/ /,"",$2);print $2}')

echo "Daten-Volume: $DATADEV"
mkdir -p "$MNT"
umount "$MNT" 2>/dev/null

for SNAP in $(tmutil listlocalsnapshots / | grep com.apple.TimeMachine | sort -r); do
    umount "$MNT" 2>/dev/null
    mount_apfs -o ro,nobrowse -s "$SNAP" "$DATADEV" "$MNT" 2>/dev/null || continue
    SRC="$MNT/$REL"
    if [ -f "$SRC" ]; then
        COUNT=$(python3 -c "import json;print(len(json.load(open('$SRC')).get('services',[])))" 2>/dev/null || echo 0)
        printf "  %s -> %s Dienste\n" "$SNAP" "$COUNT"
        if [ "${COUNT:-0}" -gt 0 ]; then
            echo ""
            echo "Gefunden: $COUNT Dienste in $SNAP"
            cp "$DEST" "$DEST.leer-$(date +%s).json" 2>/dev/null
            cp "$SRC" "$DEST"
            python3 -c "import json;d=json.load(open('$DEST'));print('Wiederhergestellt:',[s['name'] for s in d['services']])"
            umount "$MNT" 2>/dev/null; rmdir "$MNT" 2>/dev/null
            exit 0
        fi
    fi
    umount "$MNT" 2>/dev/null
done

echo "Kein Snapshot mit Diensten gefunden."
rmdir "$MNT" 2>/dev/null
exit 1
