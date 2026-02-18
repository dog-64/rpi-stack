#!/bin/bash
# Скрипт для фикса сети Ubuntu на Raspberry Pi — пишет netplan конфиг на boot раздел SD карты
# Использование: sudo ./fix-sd-network.sh /dev/diskX

set -e

DISK="$1"

if [ -z "$DISK" ]; then
    echo "Использование: $0 /dev/diskX"
    echo ""
    echo "Найдите SD карту:"
    echo "  diskutil list"
    echo ""
    echo "Пример:"
    echo "  sudo $0 /dev/disk6"
    exit 1
fi

# Проверка что диск существует
if [ ! -b "$DISK" ]; then
    echo "Ошибка: Диск $DISK не найден"
    echo "Проверьте список дисков: diskutil list"
    exit 1
fi

# Проверка root
if [ "$EUID" -ne 0 ]; then
    echo "Ошибка: Скрипт требует root прав. Используйте sudo."
    exit 1
fi

# Boot раздел — s1 (FAT32, macOS монтирует нативно)
BOOT_PARTITION="${DISK}s1"

if [ ! -b "$BOOT_PARTITION" ]; then
    echo "Ошибка: Boot раздел $BOOT_PARTITION не найден"
    echo "Проверьте разделы: diskutil list ${DISK}"
    exit 1
fi

echo "=========================================="
echo "Fix Ubuntu Network on Raspberry Pi SD Card"
echo "=========================================="
echo "SD Card: $DISK"
echo "Boot partition: $BOOT_PARTITION"
echo ""

# Монтируем boot раздел (FAT32)
echo "[1/4] Монтирую boot раздел..."
diskutil mount "$BOOT_PARTITION" > /dev/null 2>&1
sleep 2

MOUNT_POINT=$(diskutil info "$BOOT_PARTITION" | grep "Mount Point" | awk -F: '{print $2}' | xargs)

if [ -z "$MOUNT_POINT" ]; then
    echo "Ошибка: Не удалось смонтировать boot раздел"
    exit 1
fi

echo "      Смонтирован в: $MOUNT_POINT"

# Проверяем и обновляем meta-data (требуется instance-id для cloud-init)
echo "[2/4] Проверяю meta-data..."
META_DATA="$MOUNT_POINT/meta-data"

if [ -f "$META_DATA" ]; then
    cp "$META_DATA" "$MOUNT_POINT/meta-data.backup"
    echo "      Бэкап: meta-data.backup"
    
    if ! grep -q "instance-id" "$META_DATA"; then
        echo "      Добавляю instance-id в meta-data..."
        echo "instance-id: iid-rpi-$(date +%s)" >> "$META_DATA"
    fi
else
    echo "      Создаю meta-data с instance-id..."
    cat > "$META_DATA" << 'METAEOF'
instance-id: iid-rpi-default
local-hostname: rpi
METAEOF
fi

# Записываем network-config — cloud-init прочитает его при загрузке
echo "[3/4] Записываю network-config..."

if [ -f "$MOUNT_POINT/network-config" ]; then
    cp "$MOUNT_POINT/network-config" "$MOUNT_POINT/network-config.backup"
    echo "      Бэкап: network-config.backup"
fi

# Используем несколько паттернов для максимальной совместимости:
# - en* : современный systemd naming (enp0s25, eno1, enx...)
# - eth*: классический naming (eth0, eth1...)
# - end*: используется на некоторых ARM системах (end0)
# renderer: networkd обязателен для Ubuntu Server
cat > "$MOUNT_POINT/network-config" << 'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    id0:
      match:
        name: "en*"
      dhcp4: true
      optional: true
    id1:
      match:
        name: "eth*"
      dhcp4: true
      optional: true
    id2:
      match:
        name: "end*"
      dhcp4: true
      optional: true
EOF

echo "      network-config записан:"
cat "$MOUNT_POINT/network-config"

# Восстанавливаем cmdline.txt если он был испорчен предыдущей версией скрипта
echo "[4/4] Проверяю cmdline.txt..."
if [ -f "$MOUNT_POINT/cmdline.txt" ]; then
    CMDLINE=$(cat "$MOUNT_POINT/cmdline.txt")

    if [[ "$CMDLINE" =~ "network-config=" ]]; then
        echo "      Обнаружен повреждённый cmdline.txt, восстанавливаю..."
        cp "$MOUNT_POINT/cmdline.txt" "$MOUNT_POINT/cmdline.txt.broken"
        FIXED_CMDLINE=$(echo "$CMDLINE" | sed -E 's/[[:space:]]*network-config=\{config:[[:space:]]*disabled\}//g; s/[[:space:]]*network-config=[^[:space:]]*//g; s/[[:space:]]*disabled\}//g' | sed 's/  */ /g; s/^ *//; s/ *$//')
        echo "$FIXED_CMDLINE" > "$MOUNT_POINT/cmdline.txt"
        echo "      cmdline.txt восстановлен"
    fi
fi

# Размонтировать
echo ""
echo "Размонтирую boot раздел..."
diskutil unmount "$BOOT_PARTITION" > /dev/null 2>&1

echo ""
echo "=========================================="
echo "ГОТОВО!"
echo ""
echo "Теперь:"
echo "  1. Извлечь SD карту: diskutil eject $DISK"
echo "  2. Вставить в Raspberry Pi и загрузить"
echo "  3. Ethernet интерфейс получит IP по DHCP автоматически"
echo ""
echo "Конфигурация сети:"
echo "  - Паттерны: en*, eth*, end* (покрывает все варианты)"
echo "  - Renderer: networkd (Ubuntu Server)"
echo "  - DHCP: включён"
echo ""
echo "Если сеть не работает, проверьте логи на Pi:"
echo "  cat /var/log/cloud-init-output.log"
echo "  cat /run/netplan/50-cloud-init.yaml"
echo "=========================================="
