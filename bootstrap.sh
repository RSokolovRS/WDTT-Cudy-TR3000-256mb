#!/bin/sh
# Bootstrap с зеркалами (если raw.githubusercontent.com недоступен)
OUT="/tmp/wdtt-install.sh"

try_download() {
	url="$1"
	echo "Try: $url"
	if [ -x /bin/uclient-fetch ]; then
		uclient-fetch -t 30 -q -O "$OUT" "$url" && [ -s "$OUT" ] && return 0
	fi
	wget -T 30 -q -O "$OUT" "$url" 2>/dev/null && [ -s "$OUT" ] && return 0
	curl -fsSL --connect-timeout 30 -o "$OUT" "$url" 2>/dev/null && [ -s "$OUT" ] && return 0
	return 1
}

REPO_REF="a15c5e9"

for url in \
	"https://cdn.jsdelivr.net/gh/RSokolovRS/WDTT-Cudy-TR3000-256mb@${REPO_REF}/install.sh" \
	"https://cdn.jsdelivr.net/gh/RSokolovRS/WDTT-Cudy-TR3000-256mb@main/install.sh" \
	"https://raw.githubusercontent.com/RSokolovRS/WDTT-Cudy-TR3000-256mb/main/install.sh"
do
	try_download "$url" && sh "$OUT" && exit 0
done

echo "ERROR: GitHub CDN недоступен с роутера."
echo ""
echo "Установите с компьютера:"
echo "  git clone https://github.com/RSokolovRS/WDTT-Cudy-TR3000-256mb.git"
echo "  cd WDTT-Cudy-TR3000-256mb"
echo "  scp install.sh root@192.168.1.1:/tmp/"
echo "  # скачайте wdttd-linux-arm64 с Releases на ПК"
echo "  scp wdttd-linux-arm64 root@192.168.1.1:/tmp/wdttd"
echo "  ssh root@192.168.1.1 'WDTT_LOCAL_BIN=/tmp/wdttd sh /tmp/install.sh'"
exit 1
