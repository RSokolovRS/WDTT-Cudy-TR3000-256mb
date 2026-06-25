#!/bin/sh
# WDTT installer for OpenWrt (apk / opkg) — Cudy TR3000 256MB and compatible
# Usage: sh <(wget -O - https://raw.githubusercontent.com/RSokolovRS/WDTT-Cudy-TR3000-256mb/main/install.sh)

set -e

GITHUB_REPO="RSokolovRS/WDTT-Cudy-TR3000-256mb"
GITHUB_BRANCH="main"
RAW_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}"
RELEASE_API="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
DOWNLOAD_DIR="/tmp/wdtt-install"
COUNT=3

PKG_IS_APK=0
command -v apk >/dev/null 2>&1 && PKG_IS_APK=1

msg()  { printf "\033[32;1m%s\033[0m\n" "$1"; }
warn() { printf "\033[33;1m%s\033[0m\n" "$1"; }
err()  { printf "\033[31;1m%s\033[0m\n" "$1"; }

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

download_file() {
	local url="$1" dest="$2"
	local attempt=0
	while [ "$attempt" -lt "$COUNT" ]; do
		msg "Download $(basename "$dest") (attempt $((attempt + 1)))..."
		if wget -q -O "$dest" "$url"; then
			if [ -s "$dest" ]; then
				return 0
			fi
		fi
		rm -f "$dest"
		attempt=$((attempt + 1))
	done
	return 1
}

install_from_release() {
	local arch pattern url filename filepath

	arch="$(detect_arch)"
	if [ "$PKG_IS_APK" -eq 1 ]; then
		pattern='https://[^"[:space:]]*\.apk'
	else
		pattern='https://[^"[:space:]]*\.ipk'
	fi

	if ! wget -qO- "$RELEASE_API" | grep -o "$pattern" > "$DOWNLOAD_DIR/urls.txt" 2>/dev/null; then
		return 1
	fi

	if [ ! -s "$DOWNLOAD_DIR/urls.txt" ]; then
		return 1
	fi

	local installed=0
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

install_from_source() {
	local arch goarch dest

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

	msg "Installing from source (no release packages found)..."

	# wdttd binary from latest release asset or GitHub Actions artifact name
	local bin_url=""
	if wget -qO- "$RELEASE_API" 2>/dev/null | grep -o "https://[^\"[:space:]]*wdttd-linux-${goarch}[^\"[:space:]]*" > "$DOWNLOAD_DIR/binurl.txt"; then
		bin_url="$(head -n1 "$DOWNLOAD_DIR/binurl.txt" 2>/dev/null)"
	fi

	mkdir -p /usr/sbin /usr/libexec/wdtt /var/run/wdtt \
		/etc/init.d /etc/config /etc/hotplug.d/iface \
		/etc/uci-defaults /usr/share/luci/menu.d \
		/usr/share/rpcd/acl.d /usr/libexec/rpcd \
		/htdocs/luci-static/resources/view/wdtt 2>/dev/null || true

	# LuCI path on OpenWrt
	LUCI_VIEW="/www/luci-static/resources/view/wdtt"
	mkdir -p "$LUCI_VIEW"

	if [ -n "$bin_url" ] && download_file "$bin_url" "$DOWNLOAD_DIR/wdttd"; then
		install -m 0755 "$DOWNLOAD_DIR/wdttd" /usr/sbin/wdttd
	else
		err "Binary wdttd-linux-${goarch} not found in releases."
		err "Create a GitHub Release with asset wdttd-linux-${goarch}"
		err "Or build feed manually: see README.md"
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
		aarch64)
			msg "Architecture: aarch64 (Cudy TR3000 OK)"
			;;
		*)
			warn "Architecture: $(detect_arch) — primary target is aarch64 (TR3000)"
			;;
	esac
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

	# Профиль TR3000 — только если конфиг пустой
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
	msg " Docs: https://github.com/${GITHUB_REPO}"
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
		warn "Release packages not found, trying source install..."
		install_from_source
	fi

	post_install
	rm -rf "$DOWNLOAD_DIR"
}

main "$@"
