# WDTT OpenWRT — Cudy TR3000 256MB

OpenWRT-клиент WDTT (WireGuard over VK TURN) с выборочной маршрутизацией как в [Podkop](https://github.com/itdoginfo/podkop).

## Быстрая установка на роутер

```bash
sh <(uclient-fetch -q -O - https://raw.githubusercontent.com/RSokolovRS/WDTT-Cudy-TR3000-256mb/main/install.sh)
```

Должно появиться `WDTT installer v3.0`.

### apk сломан (`unexpected end of file` на всех зеркалах)

Старый установщик поставил **wget-nossl** — он ломает HTTPS для apk. Починка:

```bash
ln -sf /bin/uclient-fetch /usr/bin/wget
apk del wget-nossl
apk update
apk add wireguard-tools kmod-wireguard
```

Или:

```bash
sh <(uclient-fetch -q -O - https://raw.githubusercontent.com/RSokolovRS/WDTT-Cudy-TR3000-256mb/main/scripts/fix-apk.sh)
```

Затем снова установщик WDTT (команда выше).

### Приватный репозиторий (опционально)

```bash
export GITHUB_TOKEN="github_pat_..."
sh <(uclient-fetch --header="Authorization: Bearer $GITHUB_TOKEN" -q -O - \
  https://raw.githubusercontent.com/RSokolovRS/WDTT-Cudy-TR3000-256mb/main/install.sh)
```

Требуется OpenWrt **24.10+** / **25.x** (apk), интернет, ~20 МБ свободного места.

## Целевое устройство

**Cudy TR3000 256MB** (и совместимые):

| Параметр | Значение |
|----------|----------|
| SoC | MediaTek MT7981 (Filogic 820) |
| CPU | 2× Cortex-A53 @ 1.3 GHz |
| RAM | 512 МБ |
| Flash | 256 МБ NAND |
| Архитектура | `aarch64_cortex-a53` |
| OpenWrt target | `mediatek/filogic` |

Прошивка: `openwrt-25.12.4-mediatek-filogic-cudy_tr3000-256mb-v1-...`

## Состав

| Пакет | Описание |
|-------|----------|
| `wdtt-client` | Go-демон `wdttd` + selective routing |
| `luci-app-wdtt` | LuCI: туннель, правила, статус, логи |

## Маршрутизация (как Podkop)

По умолчанию режим **selective** — в туннель идут только выбранные ресурсы:

1. **Правила `route`** — домены (через dnsmasq ipset), подсети, URL-списки
2. **Правила `exclusion`** — трафик напрямую
3. **`routing_excluded_ip`** — устройства, которые всегда мимо туннеля (высший приоритет)
4. **`source_ip`** в правиле — весь трафик устройства через WDTT (`fully_routed_ips` в Podkop)

Режим **full** — весь трафик роутера через WDTT.

```
Приоритет: routing_excluded_ip > source_ip (full device) > domain/subnet lists
```

## OpenWrt 25.12 — пакетный менеджер APK

В 25.x вместо `opkg` используется **apk** (Alpine Package Keeper).

| opkg | apk |
|------|-----|
| `opkg update` | `apk update` |
| `opkg install pkg` | `apk add pkg` |
| `opkg remove pkg` | `apk del pkg` |
| `opkg list-installed` | `apk info` |
| `opkg upgrade` | `apk upgrade` |

[Официальный cheatsheet opkg → apk](https://openwrt.org/docs/guide-user/additional-software/opkg-to-apk-cheatsheet)

### Установка на роутер (готовые .apk)

```bash
apk update
apk add wdtt-client luci-app-wdtt
/etc/init.d/rpcd restart
/etc/init.d/wdtt enable
```

## Сборка из исходников

```bash
cd openwrt

echo 'src-link wdtt /path/to/WDTT_OpenWRT' >> feeds.conf.default
./scripts/feeds update wdtt
./scripts/feeds install wdtt-client luci-app-wdtt

# Target: MediaTek Ralink ARM → Filogic 8x0 (MT798x)
# Subtarget: filogic
# Target Profile: Cudy TR3000 256MB v1
make menuconfig

make package/wdtt-client/compile V=s
make package/luci-app-wdtt/compile V=s
```

Готовые пакеты: `bin/packages/aarch64_cortex-a53/wdtt/`

## Настройка

### LuCI

**Сервисы → WDTT VPN**:
1. VPS (`IP:56000`), пароль, VK-хеши
2. Режим маршрутизации: **Выборочная**
3. Добавьте правила (YouTube, geoblock и т.д.)
4. **Подключить**

### UCI

```bash
uci set wdtt.globals.enabled='1'
uci set wdtt.globals.peer='203.0.113.10:56000'
uci set wdtt.globals.password='your-password'
uci set wdtt.globals.hashes='abc123'
uci set wdtt.globals.routing_mode='selective'
uci set wdtt.globals.workers='12'

uci set wdtt.youtube=rule
uci set wdtt.youtube.enabled='1'
uci set wdtt.youtube.type='route'
uci add_list wdtt.youtube.domain='youtube.com'
uci add_list wdtt.youtube.domain='googlevideo.com'

uci commit wdtt
/etc/init.d/wdtt restart
```

## Рекомендации для TR3000

| Параметр | Значение |
|----------|----------|
| Потоки (`workers`) | 12 (макс. 24) |
| MTU | 1380 |
| Режим | selective |
| Место на flash | ~15 МБ (бинарник + зависимости) |

512 МБ RAM достаточно для WDTT + dnsmasq ipset + LuCI.

## Архитектура

```
LuCI → UCI → procd → wdttd
                      ├── core (VK TURN / DTLS)
                      ├── wg-wdtt
                      └── /usr/libexec/wdtt/routing
                            ├── dnsmasq ipset (домены)
                            ├── nftables fwmark 0x777474
                            └── ip rule → table 100 → wg-wdtt
```

## Совместимость с Podkop

WDTT и Podkop можно использовать **вместе**:
- WDTT поднимает `wg-wdtt`
- В Podkop создайте секцию типа **VPN** с интерфейсом `wg-wdtt`

Либо используйте встроенные правила WDTT без Podkop.

## Капча

```bash
wdttd -captcha 'token'
# или через LuCI → вкладка VK Smart Captcha
```

## Лицензия

GPL-3.0

## Связанные проекты

- [proxy-turn-vk-android](https://github.com/amurcanov/proxy-turn-vk-android)
- [PWDTT](https://github.com/luminescq/PWDTT)
- [Podkop](https://github.com/itdoginfo/podkop)
