#!/bin/sh
# Bootstrap: скачивает install.sh в /tmp и запускает (надёжнее чем sh <(...))
uclient-fetch -q -O /tmp/wdtt-install.sh \
  "https://raw.githubusercontent.com/RSokolovRS/WDTT-Cudy-TR3000-256mb/main/install.sh" \
  || wget -q -O /tmp/wdtt-install.sh \
  "https://raw.githubusercontent.com/RSokolovRS/WDTT-Cudy-TR3000-256mb/main/install.sh"

if [ ! -s /tmp/wdtt-install.sh ]; then
  echo "ERROR: cannot download install.sh"
  exit 1
fi

sh /tmp/wdtt-install.sh
