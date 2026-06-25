#!/bin/sh
# Установка WDTT с компьютера (когда GitHub недоступен с роутера)
# Запуск на ПК: sh scripts/install-from-pc.sh [root@192.168.1.1]

set -e

ROUTER="${1:-root@192.168.1.1}"
REPO="https://github.com/RSokolovRS/WDTT-Cudy-TR3000-256mb"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="/tmp/wdtt-pc-install"

mkdir -p "$TMP"

echo "=== Download on PC ==="
curl -fsSL -o "$TMP/install.sh" \
	"$REPO/raw/main/install.sh" || \
curl -fsSL -o "$TMP/install.sh" \
	"https://cdn.jsdelivr.net/gh/RSokolovRS/WDTT-Cudy-TR3000-256mb@main/install.sh"

curl -fsSL -L -o "$TMP/wdttd" \
	"$REPO/releases/download/v1.0.0/wdttd-linux-arm64"

echo "=== Copy to router $ROUTER ==="
scp "$TMP/install.sh" "$ROUTER:/tmp/wdtt-install.sh"
scp "$TMP/wdttd" "$ROUTER:/tmp/wdttd"

echo "=== Run installer on router ==="
ssh "$ROUTER" "chmod +x /tmp/wdttd /tmp/wdtt-install.sh && WDTT_LOCAL_BIN=/tmp/wdttd sh /tmp/wdtt-install.sh"

echo "=== Done ==="
