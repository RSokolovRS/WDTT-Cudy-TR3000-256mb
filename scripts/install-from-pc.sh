#!/bin/sh
# Установка WDTT с компьютера (jsDelivr/GitHub недоступны с роутера)
# Запуск на ПК:
#   sh scripts/install-from-pc.sh root@192.168.1.1
#   sh scripts/install-from-pc.sh root@192.168.1.1 --clean

set -e

ROUTER="${1:-root@192.168.1.1}"
CLEAN_ARG=""
[ "$2" = "--clean" ] && CLEAN_ARG="--clean"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="/tmp/wdtt-pc-install"
VERSION="3.8.3"
REPO="https://github.com/RSokolovRS/WDTT-Cudy-TR3000-256mb"
PIN="bbf03b3"

mkdir -p "$TMP"

echo "=== wdttd v${VERSION} on PC ==="
if [ -f "$DIR/bin/wdttd-linux-arm64" ]; then
	cp -f "$DIR/bin/wdttd-linux-arm64" "$TMP/wdttd"
	echo "  using local bin/wdttd-linux-arm64"
else
	curl -fsSL -L -o "$TMP/wdttd" \
		"https://cdn.jsdelivr.net/gh/RSokolovRS/WDTT-Cudy-TR3000-256mb@${PIN}/bin/wdttd-linux-arm64" || \
	curl -fsSL -L -o "$TMP/wdttd" \
		"${REPO}/releases/download/v${VERSION}/wdttd-linux-arm64" || \
	curl -fsSL -L -o "$TMP/wdttd" \
		"https://raw.githubusercontent.com/RSokolovRS/WDTT-Cudy-TR3000-256mb/${PIN}/bin/wdttd-linux-arm64"
fi
chmod +x "$TMP/wdttd"
ls -la "$TMP/wdttd"

echo "=== Bundle repo files (offline) ==="
tar czf "$TMP/wdtt-repo.tar.gz" -C "$DIR" \
	install.sh \
	bin/wdttd-linux-arm64 \
	wdtt-client/files/wdtt-routing \
	wdtt-client/files/wdtt-fix-config \
	wdtt-client/files/wdtt-doctor \
	wdtt-client/files/wdtt-full-tunnel \
	wdtt-client/files/wdtt-uplink \
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
echo "LuCI: Services → WDTT VPN → peer/password → Подключить"
echo "Проверка: ssh $ROUTER '/usr/libexec/wdtt/doctor'"
