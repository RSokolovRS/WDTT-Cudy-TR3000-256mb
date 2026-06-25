#!/bin/sh
# Обёртка — перенаправляет на основной install.sh
exec sh <(wget -O - https://raw.githubusercontent.com/RSokolovRS/WDTT-Cudy-TR3000-256mb/main/install.sh)

set -e

echo "=== WDTT installer for OpenWrt 25.x (apk) ==="

if command -v apk >/dev/null 2>&1; then
	PKG="apk"
	apk update
	apk add wdtt-client luci-app-wdtt || {
		echo "Пакеты не найдены в репозитории."
		echo "Соберите feed или установите .apk вручную:"
		echo "  apk add /tmp/wdtt-client-*.apk /tmp/luci-app-wdtt-*.apk"
		exit 1
	}
elif command -v opkg >/dev/null 2>&1; then
	echo "Обнаружен opkg (OpenWrt < 25). Используйте:"
	echo "  opkg install wdtt-client luci-app-wdtt"
	exit 1
else
	echo "Менеджер пакетов не найден."
	exit 1
fi

/etc/init.d/rpcd restart 2>/dev/null || true
/etc/init.d/wdtt enable 2>/dev/null || true

echo ""
echo "Готово. Откройте LuCI → Сервисы → WDTT VPN"
echo "Профиль для TR3000: /etc/config/wdtt (см. profiles/cudy-tr3000.example)"
