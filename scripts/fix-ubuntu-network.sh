#!/bin/bash
# Скрипт для фикса сети Ubuntu 24.04 на Raspberry Pi сразу после записи образа
# Использование: sudo ./fix-ubuntu-network.sh /dev/disk6

set -e

DISK="$1"

if [ -z "$DISK" ]; then
    echo "Использование: $0 /dev/diskX"
    echo "Найдите SD команду: diskutil list"
    exit 1
fi

# Проверка что диск существует
if [ ! -b "$DISK" ]; then
    echo "Ошибка: Диск $DISK не найден"
    exit 1
fi

# Монтируем boot раздел (обычно s1)
BOOT_PARTITION="${DISK}s1"

echo "Монтирую boot раздел $BOOT_PARTITION..."
diskutil mount "$BOOT_PARTITION"

# Ждём монтирования
sleep 2

# Ищем точку монтирования
MOUNT_POINT=$(diskutil info "$BOOT_PARTITION" | grep "Mount Point" | awk '{print $3}')

if [ -z "$MOUNT_POINT" ]; then
    echo "Ошибка: Не удалось смонтировать boot раздел"
    exit 1
fi

echo "Boot раздел смонтирован в: $MOUNT_POINT"

# Проверяем наличие network-config
if [ -f "$MOUNT_POINT/network-config" ]; then
    echo "Найден существующий network-config, создаю бэкап..."
    cp "$MOUNT_POINT/network-config" "$MOUNT_POINT/network-config.backup"
fi

# Создаём правильный network-config с match для надёжности
echo "Создаю network-config с настройкой DHCP..."
cat > "$MOUNT_POINT/network-config" << 'EOF'
network:
  version: 2
  ethernets:
    ethernet:
      match:
        name: "e*"
      dhcp4: true
      optional: true
EOF

# Восстанавливаем cmdline.txt если он был испорчен предыдущей версией скрипта
if [ -f "$MOUNT_POINT/cmdline.txt" ]; then
    CMDLINE=$(cat "$MOUNT_POINT/cmdline.txt")

    if [[ "$CMDLINE" =~ "network-config=" ]]; then
        echo "Обнаружен повреждённый cmdline.txt, восстанавливаю..."
        cp "$MOUNT_POINT/cmdline.txt" "$MOUNT_POINT/cmdline.txt.broken"
        FIXED_CMDLINE=$(echo "$CMDLINE" | sed -E 's/[[:space:]]*network-config=\{config:[[:space:]]*disabled\}//g; s/[[:space:]]*network-config=[^[:space:]]*//g; s/[[:space:]]*disabled\}//g' | sed 's/  */ /g; s/^ *//; s/ *$//')
        echo "$FIXED_CMDLINE" > "$MOUNT_POINT/cmdline.txt"
        echo "cmdline.txt восстановлен"
    else
        echo "cmdline.txt в порядке"
    fi
fi

echo ""
echo "Готово! SD карта подготовлена для загрузки с рабочей сетью."
echo "Извлеките SD карту: diskutil eject $DISK"
