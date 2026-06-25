#!/bin/sh
# Bootstrap: скачивает install.sh в /tmp и запускает
INSTALL_URL="https://raw.githubusercontent.com/RSokolovRS/WDTT-Cudy-TR3000-256mb/main/install.sh"
OUT="/tmp/wdtt-install.sh"

wget_is_ssl_ok() {
	local target
	target="$(readlink -f /usr/bin/wget 2>/dev/null || echo "")"
	case "$target" in
		*uclient-fetch*) return 0 ;;
		*wget-ssl*) return 0 ;;
		*wget-nossl*|*nossl*) return 1 ;;
	esac
	# Проверка HTTPS тестом
	wget -q -O /dev/null "https://github.com" 2>/dev/null
}

download_installer() {
	if [ -x /bin/uclient-fetch ]; then
		uclient-fetch -q -O "$OUT" "$INSTALL_URL" && [ -s "$OUT" ] && return 0
	fi

	if command -v wget >/dev/null 2>&1 && wget_is_ssl_ok; then
		wget -q -O "$OUT" "$INSTALL_URL" && [ -s "$OUT" ] && return 0
	fi

	if command -v curl >/dev/null 2>&1; then
		curl -fsSL -o "$OUT" "$INSTALL_URL" && [ -s "$OUT" ] && return 0
	fi

	return 1
}

if ! download_installer; then
	echo "ERROR: cannot download install.sh"
	echo ""
	echo "Если wget-nossl ломает HTTPS, выполните:"
	echo "  ln -sf /bin/uclient-fetch /usr/bin/wget"
	echo "  apk del wget-nossl"
	echo ""
	echo "Затем:"
	echo "  wget -O $OUT $INSTALL_URL"
	echo "  sh $OUT"
	exit 1
fi

sh "$OUT"
