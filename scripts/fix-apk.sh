#!/bin/sh
# Восстановление apk после установки wget-nossl
# Запуск: sh <(uclient-fetch -q -O - https://raw.githubusercontent.com/RSokolovRS/WDTT-Cudy-TR3000-256mb/main/scripts/fix-apk.sh)

echo "=== Fix apk / wget on OpenWrt ==="

if [ -x /bin/uclient-fetch ]; then
	echo "Restore /usr/bin/wget -> uclient-fetch"
	ln -sf /bin/uclient-fetch /usr/bin/wget
fi

if apk info -e wget-nossl >/dev/null 2>&1; then
	echo "Remove wget-nossl..."
	apk del wget-nossl
fi

echo "apk update..."
apk update

echo "Done. Test: apk add wireguard-tools kmod-wireguard"
