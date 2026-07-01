#!/bin/sh
# Установка WDTT с компьютера (GitHub/CDN недоступны с роутера)
# Запуск на ПК:
#   sh scripts/install-from-pc.sh root@192.168.1.1
#   sh scripts/install-from-pc.sh root@192.168.1.1 --clean

set -e

ROUTER="${1:-root@192.168.1.1}"
CLEAN_ARG=""
[ "$2" = "--clean" ] && CLEAN_ARG="--clean"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="/tmp/wdtt-pc-install"
VERSION="3.7.2"
REPO="https://github.com/RSokolovRS/WDTT-Cudy-TR3000-256mb"

mkdir -p "$TMP"

echo "=== Download wdttd v${VERSION} on PC ==="
curl -fsSL -L -o "$TMP/wdttd" \
	"https://cdn.jsdelivr.net/gh/RSokolovRS/WDTT-Cudy-TR3000-256mb@main/bin/wdttd-linux-arm64" || \
curl -fsSL -L -o "$TMP/wdttd" \
	"$REPO/releases/download/v${VERSION}/wdttd-linux-arm64"

echo "=== Bundle repo files ==="
tar czf "$TMP/wdtt-repo.tar.gz" -C "$DIR" \
	install.sh \
	wdtt-client/files/wdtt-routing \
	wdtt-client/files/wdtt-fix-config \
	wdtt-client/files/wdtt-doctor \
	luci-app-wdtt/root/etc/init.d/wdtt \
	luci-app-wdtt/root/etc/config/wdtt \
	luci-app-wdtt/root/etc/firewall.wdtt \
	luci-app-wdtt/root/etc/uci-defaults/99-wdtt \
	luci-app-wdtt/root/etc/hotplug.d/iface/99-wdtt \
	luci-app-wdtt/root/usr/libexec/rpcd/wdtt \
	luci-app-wdtt/root/usr/share/luci/menu.d/luci-app-wdtt.json \
	luci-app-wdtt/root/usr/share/rpcd/acl.d/luci-app-wdtt.json \
	luci-app-wdtt/htdocs/luci-static/resources/view/wdtt/overview.js

echo "=== Copy to router $ROUTER ==="
scp "$TMP/wdttd" "$ROUTER:/tmp/wdttd"
scp "$TMP/wdtt-repo.tar.gz" "$ROUTER:/tmp/wdtt-repo.tar.gz"
scp "$DIR/install.sh" "$ROUTER:/tmp/wdtt-install.sh"

echo "=== Run offline installer on router ==="
ssh "$ROUTER" "set -e
	rm -rf /tmp/wdtt-repo
	mkdir -p /tmp/wdtt-repo
	tar xzf /tmp/wdtt-repo.tar.gz -C /tmp/wdtt-repo
	chmod +x /tmp/wdttd /tmp/wdtt-install.sh
	WDTT_SKIP_PROBE=1 \
	WDTT_LOCAL_BIN=/tmp/wdttd \
	WDTT_LOCAL_REPO=/tmp/wdtt-repo \
	WDTT_KEEP_SECRETS=1 \
	WDTT_FRESH_CONFIG=1 \
	sh /tmp/wdtt-install.sh ${CLEAN_ARG}"

echo "=== Done ==="
echo "LuCI: Services → WDTT VPN → Правила → Домены (Save & Apply)"
