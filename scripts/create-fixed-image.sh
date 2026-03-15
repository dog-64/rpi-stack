#!/bin/bash
# Скрипт для создания исправленного образа Ubuntu для Raspberry Pi
# Использование: sudo ./create-fixed-image.sh /path/to/ubuntu-original.img ubuntu-fixed.img

set -e

SOURCE_IMAGE="$1"
OUTPUT_IMAGE="$2"

if [ -z "$SOURCE_IMAGE" ] || [ -z "$OUTPUT_IMAGE" ]; then
    echo "Использование: $0 <исходный_образ> <выходной_образ>"
    echo ""
    echo "Пример:"
    echo "  sudo $0 ~/Downloads/ubuntu-24.04.4-preinstalled-server-arm64+raspi.img ubuntu-24.04-fixed.img"
    exit 1
fi

# Проверка существования исходного файла
if [ ! -f "$SOURCE_IMAGE" ]; then
    echo "Ошибка: Исходный образ не найден: $SOURCE_IMAGE"
    exit 1
fi

# Проверка root
if [ "$EUID" -ne 0 ]; then
    echo "Ошибка: Скрипт требует root прав для монтирования образа. Используйте sudo."
    exit 1
fi

echo "=========================================="
echo "Create Fixed Ubuntu Image for Raspberry Pi"
echo "=========================================="
echo "Исходный образ: $SOURCE_IMAGE"
echo "Выходной образ: $OUTPUT_IMAGE"
echo ""

# Копируем образ
SIZE=$(stat -f%z "$SOURCE_IMAGE" 2>/dev/null || stat -c%s "$SOURCE_IMAGE" 2>/dev/null)
echo "[1/5] Копирую образ (~$((SIZE / 1024 / 1024 / 1024))GB)..."
cp "$SOURCE_IMAGE" "$OUTPUT_IMAGE"
echo "      Копирование завершено"

# Находим boot раздел в образе
echo "[2/5] Анализирую разделы образа..."

# Создаём temporary loop device
LOOP_DEV=$(hdiutil attach -nomount "$OUTPUT_IMAGE" | grep -o '/dev/loop[0-9]*' | head -1)

if [ -z "$LOOP_DEV" ]; then
    # Альтернативный способ для macOS
    echo "      Используя kpartx для монтирования разделов..."
    # Для macOS используем другой подход
    ATTACH_OUTPUT=$(hdiutil attach -readonly -nomount "$OUTPUT_IMAGE")
    echo "      Устройство: $ATTACH_OUTPUT"

    # Находим boot раздел (обычно первый, FAT)
    # Образ Ubuntu для RPi имеет два раздела: boot (FAT) и root (ext4)
    BOOT_DEV=$(echo "$ATTACH_OUTPUT" | grep -o '/dev/disk[0-9]*s1' | head -1)

    if [ -z "$BOOT_DEV" ]; then
        echo "Ошибка: Не удалось найти boot раздел"
        hdiutil detach "$ATTACH_OUTPUT" > /dev/null 2>&1 || true
        exit 1
    fi
else
    BOOT_DEV="${LOOP_DEV}p1"
fi

# Смонтируем boot раздел через kpartx на Linux или через hdiutil на macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    echo "[3/5] Монтирую boot раздел (macOS)..."

    # Используем losetup через coreutils если доступен, или hdiutil
    # Более простой способ: использовать fdisk для получения смещения

    # Получаем информацию о разделах
    SECTOR_SIZE=$(fdisk -l "$OUTPUT_IMAGE" 2>/dev/null | grep "Sector size" | awk '{print $4}' || echo "512")

    # Получаем стартовый сектор первого раздела
    START_SECTOR=$(fdisk -l "$OUTPUT_IMAGE" 2>/dev/null | grep "^${OUTPUT_IMAGE}1" | awk '{print $2}' || \
                    fdisk -l "$OUTPUT_IMAGE" 2>/dev/null | grep "EFI System" | awk '{print $2}')

    if [ -z "$START_SECTOR" ]; then
        # Пробуем через blkid если доступен
        START_SECTOR=$(blkid -o offset "$OUTPUT_IMAGE" 2>/dev/null | head -1)
        START_BYTES=$START_SECTOR
    else
        START_BYTES=$((START_SECTOR * SECTOR_SIZE))
    fi

    if [ -z "$START_BYTES" ]; then
        echo "Ошибка: Не удалось определить смещение boot раздела"
        echo "Попробуйте использовать Linux-машину для этого скрипта"
        exit 1
    fi

    echo "      Boot раздел смещение: $START_BYTES байт"

    # Создаём точку монтирования
    MOUNT_DIR=$(mktemp -d)

    # Монтируем с указанием смещения
    mount -t vfat -o loop,offset=$START_BYTES "$OUTPUT_IMAGE" "$MOUNT_DIR" 2>/dev/null || {
        echo "Ошибка монтирования. Установите fuse-ext2 или используйте Linux"
        rm -rf "$MOUNT_DIR"
        exit 1
    }

    echo "      Смонтировано в: $MOUNT_DIR"
else
    # Linux
    echo "[3/5] Монтирую boot раздел (Linux)..."

    # Подключаем образ как loop device
    LOOP_DEV=$(losetup --show -f "$OUTPUT_IMAGE")

    # Активируем разделы
    kpartx -a "$LOOP_DEV"

    # Ждём создания устройств
    sleep 1

    BOOT_DEV="/dev/mapper/$(basename "$LOOP_DEV")p1"
    MOUNT_DIR=$(mktemp -d)

    mount "$BOOT_DEV" "$MOUNT_DIR"
fi

# Применяем исправления
echo "[4/5] Применяю исправления сети..."

# Создаём network-config
if [ -f "$MOUNT_DIR/network-config" ]; then
    echo "      Создаю бэкап network-config..."
    cp "$MOUNT_DIR/network-config" "$MOUNT_DIR/network-config.backup"
fi

cat > "$MOUNT_DIR/network-config" << 'EOF'
network:
  version: 2
  ethernets:
    ethernet:
      match:
        name: "e*"
      dhcp4: true
      optional: true
EOF

echo "      network-config создан"

# Проверяем cmdline.txt — НЕ добавляем network-config= параметр,
# т.к. cloud-init должен обработать network-config файл
if [ -f "$MOUNT_DIR/cmdline.txt" ]; then
    CMDLINE=$(cat "$MOUNT_DIR/cmdline.txt")

    if [[ "$CMDLINE" =~ "network-config=" ]]; then
        echo "      Обнаружен повреждённый cmdline.txt, восстанавливаю..."
        cp "$MOUNT_DIR/cmdline.txt" "$MOUNT_DIR/cmdline.txt.broken"
        FIXED_CMDLINE=$(echo "$CMDLINE" | sed -E 's/[[:space:]]*network-config=\{config:[[:space:]]*disabled\}//g; s/[[:space:]]*network-config=[^[:space:]]*//g; s/[[:space:]]*disabled\}//g' | sed 's/  */ /g; s/^ *//; s/ *$//')
        echo "$FIXED_CMDLINE" > "$MOUNT_DIR/cmdline.txt"
        echo "      cmdline.txt восстановлен"
    else
        echo "      cmdline.txt в порядке"
    fi
fi

# Ждём записи
sync
sleep 2

# Размонтируем
echo "[5/5] Размонтирую образ..."
umount "$MOUNT_DIR"
rm -rf "$MOUNT_DIR"

if [[ "$OSTYPE" != "darwin"* ]]; then
    kpartx -d "$LOOP_DEV"
    losetup -d "$LOOP_DEV"
fi

echo ""
echo "=========================================="
echo "ГОТОВО!"
echo ""
echo "Создан исправленный образ: $OUTPUT_IMAGE"
echo ""
echo "Для записи на SD карту:"
echo "  sudo dd if=$OUTPUT_IMAGE of=/dev/sdX bs=4M status=progress"
echo ""
echo "Или используйте BalenaEtcher / Raspberry Pi Imager"
echo "=========================================="
