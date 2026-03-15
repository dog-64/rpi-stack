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

# Проверяем cmdline.txt - критически важный файл!
echo "[4/5] Проверяю cmdline.txt..."
CMDLINE_FILE="$MOUNT_POINT/cmdline.txt"

if [ ! -f "$CMDLINE_FILE" ]; then
    echo "      ВНИМАНИЕ: cmdline.txt не найден!"
    echo "      Это может означать проблему с boot разделом."
elif [ ! -s "$CMDLINE_FILE" ]; then
    echo "      ВНИМАНИЕ: cmdline.txt пустой!"
    echo "      Это критическая проблема - система не загрузится!"
else
    CMDLINE_CONTENT=$(cat "$CMDLINE_FILE")
    echo "      Текущий cmdline.txt:"
    echo "      $CMDLINE_CONTENT"

    # Проверяем наличие проблемных параметров
    if [[ "$CMDLINE_CONTENT" =~ cgroup_disable=memory ]]; then
        echo ""
        echo "      ========================================"
        echo "      ВНИМАНИЕ: Найден cgroup_disable=memory!"
        echo "      ========================================"
        echo "      Этот параметр БЛОКИРУЕТ k3s/Kubernetes!"
        echo "      Он будет автоматически удалён при исправлении."
        echo ""
    fi

    # Проверяем наличие root= параметра
    if [[ ! "$CMDLINE_CONTENT" =~ root= ]]; then
        echo ""
        echo "      ========================================"
        echo "      ОШИБКА: cmdline.txt НЕ содержит root=!"
        echo "      ========================================"
        echo ""
        echo "      Система НЕ ЗАГРУЗИТСЯ без этого параметра!"
        echo ""
        echo "      В current/cmdline.txt должна быть правильная строка."
        echo "      Скопируйте её и добавьте cfg80211 параметр:"
        echo ""
        # Стандартная cmdline для Ubuntu Raspberry Pi (fallback)
        DEFAULT_CMDLINE="console=serial0,115200 multipath=off dwc_otg.lpm_enable=0 console=tty1 root=LABEL=writable rootfstype=ext4 panic=10 rootwait fixrtc"

        if [ -f "$MOUNT_POINT/current/cmdline.txt" ]; then
            CURRENT_CMDLINE=$(cat "$MOUNT_POINT/current/cmdline.txt")

            # ПРОВЕРКА: current/cmdline.txt тоже может быть повреждён!
            if [[ ! "$CURRENT_CMDLINE" =~ root= ]]; then
                echo "      ВНИМАНИЕ: current/cmdline.txt ТОЖЕ повреждён (нет root=)!"
                echo "      Использую стандартную cmdline строку..."
                CURRENT_CMDLINE="$DEFAULT_CMDLINE"
            fi

            # ВАЖНО: Удаляем cgroup_disable=memory - этот параметр БЛОКИРУЕТ k3s!
            # k3s требует working memory cgroup для работы контейнеров
            CMDLINE_CLEANED=$(echo "$CURRENT_CMDLINE" | sed 's/cgroup_disable=[^ ]* //g')
            CMDLINE_FIXED="$CMDLINE_CLEANED cfg80211.ieee80211_regdom=RU"
            echo "      Рекомендуемая строка:"
            echo "      $CMDLINE_FIXED"
            echo ""
            echo "      Исправить автоматически? (y/n)"
            read -r answer
            if [[ "$answer" =~ ^[Yy]$ ]]; then
                # Исправляем ОБОИ cmdline.txt файла!
                echo "$CMDLINE_FIXED" > "$CMDLINE_FILE"
                echo "$CMDLINE_FIXED" > "$MOUNT_POINT/current/cmdline.txt"
                sync

                # ВЕРИФИКАЦИЯ: проверяем что запись прошла успешно
                if [ "$(cat "$CMDLINE_FILE")" != "$CMDLINE_FIXED" ]; then
                    echo ""
                    echo "      ========================================"
                    echo "      ОШИБКА: Запись в cmdline.txt не удалась!"
                    echo "      ========================================"
                    diskutil unmount "$BOOT_PARTITION" > /dev/null 2>&1
                    exit 1
                fi

                echo "      cmdline.txt ИСПРАВЛЕН и ПРОВЕРЕН (оба файла)!"
            fi
        else
            echo "      ОШИБКА: current/cmdline.txt не найден!"
            echo "      Восстановление невозможно без источника."
        fi
    else
        echo "      OK: cmdline.txt содержит root="
        # Проверяем что current/cmdline.txt тоже содержит cfg80211
        if [ -f "$MOUNT_POINT/current/cmdline.txt" ]; then
            CURRENT_CONTENT=$(cat "$MOUNT_POINT/current/cmdline.txt")
            if [[ ! "$CURRENT_CONTENT" =~ cfg80211.ieee80211_regdom ]]; then
                echo "      ВНИМАНИЕ: current/cmdline.txt НЕ содержит cfg80211!"
                echo "      Очищаю cmdline.txt от k3s-блокирующих параметров и копирую в current/..."
                # Очищаем от проблемных параметров перед копированием
                CMDLINE_CLEANED=$(cat "$CMDLINE_FILE" | sed 's/cgroup_disable=[^ ]* //g')
                echo "$CMDLINE_CLEANED" > "$MOUNT_POINT/current/cmdline.txt"
                sync
                echo "      current/cmdline.txt обновлён и очищен!"
            fi
        fi
    fi
fi

echo "[5/5] Проверка завершена"

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
