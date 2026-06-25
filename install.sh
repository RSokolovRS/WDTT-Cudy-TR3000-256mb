#!/bin/sh
# WDTT installer for OpenWrt (apk / opkg) — Cudy TR3000 256MB and compatible
#
# Публичный репозиторий:
#   sh <(wget -O - https://raw.githubusercontent.com/RSokolovRS/WDTT-Cudy-TR3000-256mb/main/install.sh)
#
# Приватный репозиторий (нужен GitHub token с правом Contents: Read):
#   export GITHUB_TOKEN="github_pat_..."
#   sh <(wget --header="Authorization: Bearer $GITHUB_TOKEN" -O - \
#     https://raw.githubusercontent.com/RSokolovRS/WDTT-Cudy-TR3000-256mb/main/install.sh)
#
# Или скопировать скрипт на роутер:
#   scp install.sh root@192.168.1.1:/tmp/ && ssh root@192.168.1.1 'GITHUB_TOKEN=xxx sh /tmp/install.sh'

set -e

GITHUB_REPO="RSokolovRS/WDTT-Cudy-TR3000-256mb"
GITHUB_BRANCH="main"
RAW_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}"
RELEASE_API="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
DOWNLOAD_DIR="/tmp/wdtt-install"
COUNT=3

# Токен: переменная окружения или файл (chmod 600)
if [ -z "$GITHUB_TOKEN" ] && [ -f /etc/wdtt/github_token ]; then
	GITHUB_TOKEN="$(cat /etc/wdtt/github_token)"
fi

PKG_IS_APK=0
command -v apk >/dev/null 2>&1 && PKG_IS_APK=1

msg()  { printf "\033[32;1m%s\033[0m\n" "$1"; }
warn() { printf "\033[33;1m%s\033[0m\n" "$1"; }
err()  { printf "\033[31;1m%s\033[0m\n" "$1"; }

github_headers() {
	if [ -n "$GITHUB_TOKEN" ]; then
		printf '%s\n' "Authorization: Bearer $GITHUB_TOKEN"
	fi
}

# Скачивание с поддержкой приватного GitHub
download_file() {
	local url="$1" dest="$2"
	local attempt=0 hdr

	while [ "$attempt" -lt "$COUNT" ]; do
		msg "Download $(basename "$dest") (attempt $((attempt + 1)))..."

		if command -v curl >/dev/null 2>&1; then
			if [ -n "$GITHUB_TOKEN" ]; then
				if curl -fsSL \
					-H "Authorization: Bearer $GITHUB_TOKEN" \
					-H "Accept: application/octet-stream" \
					-L -o "$dest" "$url" 2>/dev/null; then
					[ -s "$dest" ] && return 0
				fi
			else
				if curl -fsSL -L -o "$dest" "$url" 2>/dev/null; then
					[ -s "$dest" ] && return 0
				fi
			fi
		fi

		if [ -n "$GITHUB_TOKEN" ]; then
			if wget -q -O "$dest" \
				--header="Authorization: Bearer $GITHUB_TOKEN" \
				--header="Accept: application/octet-stream" \
				"$url" 2>/dev/null; then
				[ -s "$dest" ] && return 0
			fi
		else
			if wget -q -O "$dest" "$url" 2>/dev/null; then
				[ -s "$dest" ] && return 0
			fi
		fi

		rm -f "$dest"
		attempt=$((attempt + 1))
	done
	return 1
}

github_api_get() {
	local url="$1" out="$2"

	if command -v curl >/dev/null 2>&1; then
		if [ -n "$GITHUB_TOKEN" ]; then
			curl -fsSL \
				-H "Authorization: Bearer $GITHUB_TOKEN" \
				-H "Accept: application/vnd.github+json" \
				-o "$out" "$url"
		else
			curl -fsSL -o "$out" "$url"
		fi
	else
		if [ -n "$GITHUB_TOKEN" ]; then
			wget -q -O "$out" \
				--header="Authorization: Bearer $GITHUB_TOKEN" \
				--header="Accept: application/vnd.github+json" \
				"$url"
		else
			wget -q -O "$out" "$url"
		fi
	fi
}

check_github_access() {
	local probe="$DOWNLOAD_DIR/probe.txt"

	if github_api_get "$RELEASE_API" "$DOWNLOAD_DIR/release_probe.json" 2>/dev/null; then
		return 0
	fi

	if [ -z "$GITHUB_TOKEN" ]; then
		err "Репозиторий приватный — нужен GITHUB_TOKEN."
		err ""
		err "1. GitHub → Settings → Developer settings → Fine-grained tokens"
		err "   Права: Repository access → WDTT-Cudy-TR3000-256mb, Contents: Read"
		err ""
		err "2. На роутере:"
		err "   export GITHUB_TOKEN='github_pat_...'"
		err "   sh <(wget --header=\"Authorization: Bearer \$GITHUB_TOKEN\" -O - \\"
		err "     https://raw.githubusercontent.com/${GITHUB_REPO}/main/install.sh)"
		err ""
		err "Или: scp install.sh root@ROUTER:/tmp/ && GITHUB_TOKEN=xxx sh /tmp/install.sh"
		exit 1
	fi

	err "GitHub API недоступен. Проверьте GITHUB_TOKEN и интернет."
	exit 1
}

pkg_list_update() {
	if [ "$PKG_IS_APK" -eq 1 ]; then
		apk update
	else
		opkg update
	fi
}

pkg_install() {
	if [ "$PKG_IS_APK" -eq 1 ]; then
		apk add "$@"
	else
		opkg install "$@"
	fi
}

pkg_install_file() {
	local f="$1"
	if [ "$PKG_IS_APK" -eq 1 ]; then
		apk add --allow-untrusted "$f"
	else
		opkg install "$f"
	fi
}

detect_arch() {
	local m
	m="$(uname -m)"
	case "$m" in
		aarch64|arm64) echo "aarch64" ;;
		armv7l|armv7)  echo "arm" ;;
		x86_64|amd64)  echo "x86_64" ;;
		*)             echo "$m" ;;
	esac
}

install_from_release() {
	local pattern filename filepath installed=0

	if [ "$PKG_IS_APK" -eq 1 ]; then
		pattern='\.apk'
	else
		pattern='\.ipk'
	fi

	if ! github_api_get "$RELEASE_API" "$DOWNLOAD_DIR/release.json"; then
		return 1
	fi

	# browser_download_url из JSON релиза
	grep -o 'https://[^"]*'"$pattern" "$DOWNLOAD_DIR/release.json" 2>/dev/null | \
		sort -u > "$DOWNLOAD_DIR/urls.txt" || true

	if [ ! -s "$DOWNLOAD_DIR/urls.txt" ]; then
		return 1
	fi

	while read -r url; do
		[ -z "$url" ] && continue
		filename="$(basename "$url")"
		case "$filename" in
			wdtt-client*|luci-app-wdtt*) ;;
			*) continue ;;
		esac
		filepath="$DOWNLOAD_DIR/$filename"
		if download_file "$url" "$filepath"; then
			msg "Installing $filename..."
			pkg_install_file "$filepath"
			installed=1
		fi
	done < "$DOWNLOAD_DIR/urls.txt"

	[ "$installed" -eq 1 ]
}

find_release_binary() {
	local goarch="$1" out="$2"

	if ! github_api_get "$RELEASE_API" "$DOWNLOAD_DIR/release.json"; then
		return 1
	fi

	# Ищем browser_download_url для wdttd-linux-ARCH
	grep -o "https://[^\"]*wdttd-linux-${goarch}[^\"]*" "$DOWNLOAD_DIR/release.json" 2>/dev/null | head -n1 > "$out"
	[ -s "$out" ]
}

install_from_source() {
	local arch goarch bin_url="" LUCI_VIEW

	arch="$(detect_arch)"
	case "$arch" in
		aarch64) goarch="arm64" ;;
		arm)     goarch="arm" ;;
		x86_64)  goarch="amd64" ;;
		*)
			err "Unsupported architecture: $arch"
			exit 1
			;;
	esac

	msg "Installing from repository files..."

	mkdir -p /usr/sbin /usr/libexec/wdtt /var/run/wdtt \
		/etc/init.d /etc/config /etc/hotplug.d/iface \
		/etc/uci-defaults /usr/share/luci/menu.d \
		/usr/share/rpcd/acl.d /usr/libexec/rpcd 2>/dev/null || true

	LUCI_VIEW="/www/luci-static/resources/view/wdtt"
	mkdir -p "$LUCI_VIEW"

	if find_release_binary "$goarch" "$DOWNLOAD_DIR/binurl.txt"; then
		bin_url="$(cat "$DOWNLOAD_DIR/binurl.txt")"
	fi

	if [ -n "$bin_url" ] && download_file "$bin_url" "$DOWNLOAD_DIR/wdttd"; then
		install -m 0755 "$DOWNLOAD_DIR/wdttd" /usr/sbin/wdttd
	else
		err "Binary wdttd-linux-${goarch} not found in releases."
		err "Создайте Release на GitHub (тег v1.0.0) с asset wdttd-linux-${goarch}"
		err "Или проверьте GITHUB_TOKEN для приватного репозитория."
		exit 1
	fi

	download_file "$RAW_URL/wdtt-client/files/wdtt-routing" /usr/libexec/wdtt/routing
	chmod 0755 /usr/libexec/wdtt/routing

	download_file "$RAW_URL/luci-app-wdtt/root/etc/init.d/wdtt" /etc/init.d/wdtt
	chmod 0755 /etc/init.d/wdtt

	download_file "$RAW_URL/luci-app-wdtt/root/etc/config/wdtt" /etc/config/wdtt
	download_file "$RAW_URL/luci-app-wdtt/root/etc/firewall.wdtt" /etc/firewall.wdtt
	chmod 0755 /etc/firewall.wdtt

	download_file "$RAW_URL/luci-app-wdtt/root/etc/uci-defaults/99-wdtt" /etc/uci-defaults/99-wdtt
	chmod 0755 /etc/uci-defaults/99-wdtt

	download_file "$RAW_URL/luci-app-wdtt/root/etc/hotplug.d/iface/99-wdtt" /etc/hotplug.d/iface/99-wdtt
	chmod 0755 /etc/hotplug.d/iface/99-wdtt

	download_file "$RAW_URL/luci-app-wdtt/root/usr/libexec/rpcd/wdtt" /usr/libexec/rpcd/wdtt
	chmod 0755 /usr/libexec/rpcd/wdtt

	download_file "$RAW_URL/luci-app-wdtt/root/usr/share/luci/menu.d/luci-app-wdtt.json" \
		/usr/share/luci/menu.d/luci-app-wdtt.json

	download_file "$RAW_URL/luci-app-wdtt/root/usr/share/rpcd/acl.d/luci-app-wdtt.json" \
		/usr/share/rpcd/acl.d/luci-app-wdtt.json

	download_file "$RAW_URL/luci-app-wdtt/htdocs/luci-static/resources/view/wdtt/overview.js" \
		"$LUCI_VIEW/overview.js"

	mkdir -p /tmp/dnsmasq.d
}

check_system() {
	local model openwrt_major space

	model="$(cat /tmp/sysinfo/model 2>/dev/null || echo unknown)"
	msg "Router model: $model"

	openwrt_major="$(grep DISTRIB_RELEASE /etc/openwrt_release 2>/dev/null | cut -d"'" -f2 | cut -d'.' -f1)"
	if [ -n "$openwrt_major" ] && [ "$openwrt_major" -lt 24 ] 2>/dev/null; then
		err "OpenWrt 24.10+ required (found: $(grep DISTRIB_RELEASE /etc/openwrt_release | cut -d"'" -f2))"
		exit 1
	fi

	space="$(df /overlay 2>/dev/null | awk 'NR==2 {print $4}')"
	if [ -n "$space" ] && [ "$space" -lt 20480 ] 2>/dev/null; then
		err "Need at least 20 MB free on /overlay (have: $((space / 1024)) MB)"
		exit 1
	fi

	if ! ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1 && ! ping -c 1 -W 3 77.88.8.8 >/dev/null 2>&1; then
		warn "No internet ping — continuing anyway..."
	fi

	case "$(detect_arch)" in
		aarch64) msg "Architecture: aarch64 (Cudy TR3000 OK)" ;;
		*)       warn "Architecture: $(detect_arch) — primary target is aarch64 (TR3000)" ;;
	esac

	if [ -n "$GITHUB_TOKEN" ]; then
		msg "GitHub token: detected (private repo OK)"
	fi
}

install_dependencies() {
	msg "Installing dependencies..."

	if [ "$PKG_IS_APK" -eq 1 ]; then
		apk add wireguard-tools-wg wireguard-tools-wg-quick \
			kmod-wireguard ca-bundle nftables kmod-nft-core \
			ipset dnsmasq curl wget 2>/dev/null || \
		apk add wireguard-tools kmod-wireguard ca-bundle \
			nftables kmod-nft-core ipset dnsmasq curl wget
	else
		opkg install wireguard-tools kmod-wireguard ca-bundle \
			nftables kmod-nft-core ipset dnsmasq curl wget
	fi
}

post_install() {
	if [ ! -f /etc/config/wdtt ]; then
		download_file "$RAW_URL/luci-app-wdtt/root/etc/config/wdtt" /etc/config/wdtt || true
	fi

	if ! uci -q get wdtt.globals.peer >/dev/null 2>&1; then
		warn "Configure WDTT: uci set wdtt.globals.peer / password / hashes"
		warn "Or LuCI → Services → WDTT VPN"
	fi

	[ -x /etc/uci-defaults/99-wdtt ] && /etc/uci-defaults/99-wdtt || true
	/etc/init.d/rpcd restart 2>/dev/null || true
	/etc/init.d/wdtt enable 2>/dev/null || true

	msg ""
	msg "============================================"
	msg " WDTT installed successfully!"
	msg " LuCI: Services → WDTT VPN"
	msg "============================================"
	msg ""
	msg "Quick start:"
	msg "  uci set wdtt.globals.peer='VPS:56000'"
	msg "  uci set wdtt.globals.password='password'"
	msg "  uci set wdtt.globals.hashes='vk_hash'"
	msg "  uci set wdtt.globals.enabled='1'"
	msg "  uci commit wdtt && /etc/init.d/wdtt start"
}

main() {
	if [ "$(id -u)" != "0" ]; then
		err "Run as root on the router"
		exit 1
	fi

	rm -rf "$DOWNLOAD_DIR"
	mkdir -p "$DOWNLOAD_DIR"

	check_system
	check_github_access

	if [ -f /etc/init.d/wdtt ]; then
		msg "WDTT already installed — upgrading..."
	else
		msg "Installing WDTT..."
	fi

	pkg_list_update || { err "Package list update failed"; exit 1; }

	install_dependencies

	if install_from_release; then
		msg "Installed from release packages"
	else
		warn "Release .apk/.ipk not found, installing from source..."
		install_from_source
	fi

	post_install
	rm -rf "$DOWNLOAD_DIR"
}

main "$@"
