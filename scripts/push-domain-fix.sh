#!/bin/sh
# Быстрое обновление исправления сохранения доменов (v3.8.5) без полной переустановки.
# На ПК:
#   sh scripts/push-domain-fix.sh root@192.168.10.1

set -e

ROUTER="${1:-root@192.168.10.1}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="3.9.0"

wdtt_scp() {
	local src="$1" dest="$2"
	scp -O "$src" "$ROUTER:$dest" 2>/dev/null && return 0
	scp "$src" "$ROUTER:$dest"
}

echo "=== WDTT domain-fix v${VERSION} → ${ROUTER} ==="

wdtt_scp "$DIR/wdtt-client/files/wdtt-domain-lib.sh" \
	"/usr/libexec/wdtt/domain-lib.sh"
wdtt_scp "$DIR/luci-app-wdtt/htdocs/luci-static/resources/view/wdtt/overview.js" \
	"/www/luci-static/resources/view/wdtt/overview.js"
wdtt_scp "$DIR/luci-app-wdtt/root/usr/libexec/rpcd/wdtt" \
	"/usr/libexec/rpcd/wdtt"
wdtt_scp "$DIR/wdtt-client/files/wdtt-fix-config" \
	"/usr/libexec/wdtt/fix-config"
wdtt_scp "$DIR/wdtt-client/files/wdtt-routing" \
	"/usr/libexec/wdtt/routing"
wdtt_scp "$DIR/wdtt-client/files/wdtt-set-domains" \
	"/usr/libexec/wdtt/set-domains"

ssh "$ROUTER" "chmod 755 /usr/libexec/rpcd/wdtt /usr/libexec/wdtt/fix-config \
	/usr/libexec/wdtt/routing /usr/libexec/wdtt/set-domains /usr/libexec/wdtt/domain-lib.sh 2>/dev/null; \
	printf '%s\n' '${VERSION}' > /usr/share/wdtt/version; \
	/etc/init.d/rpcd restart; rm -rf /tmp/luci-*"

echo "=== OK. В браузере: Ctrl+F5 на странице WDTT ==="
echo "Проверка на роутере:"
echo "  uci -q batch <<'EOF'"
echo "  set wdtt.route1.domain_list='youtube.com,googlevideo.com'"
echo "  commit wdtt"
echo "  EOF"
echo "  /usr/libexec/wdtt/fix-config"
echo "  uci get wdtt.route1.domain_list"
echo "  /usr/libexec/wdtt/doctor"
