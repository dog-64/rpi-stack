# SSD Migration Log — motya (10.0.1.56)

**Дата успешной миграции:** 2026-03-07

## Правильная последовательность (проверено на Ubuntu 25.10)

1. Скопировать rootfs на SSD через `rsync -axHAWX`
2. Написать правильный fstab на SSD с **PARTUUID**
3. Проверить hostname, machine-id на SSD
4. Обновить **ОБА** cmdline.txt файла на microSD с **PARTUUID** SSD
5. Переименовать метку microSD в `writable-sd`
6. Проверить весь чеклист перед перезагрузкой
7. Перезагрузить

---

## Исходное состояние (перед успешной миграцией)

- **Хост:** motya (10.0.1.56), Raspberry Pi 4, 8GB
- **ОС:** Ubuntu 25.10
- **Root:** `/dev/mmcblk0p2` (microSD)
- **SSD:** `/dev/sda` (119.2G), два раздела `sda1` (boot), `sda2` (root)
- **SSD PARTUUID:** `cc15fd91-e0ce-4651-bcd1-d018d708bea8`
- **Скорость SSD:** 34 MB/sec (USB 2.0, ограничение Raspberry Pi 4)

---

## Успешная миграция

### Шаг 1: Копирование rootfs на SSD
```bash
sudo mkdir -p /mnt/ssd && sudo mount /dev/sda2 /mnt/ssd
sudo rsync -axHAWX --info=progress2 / /mnt/ssd/ \
  --exclude='/mnt/**' --exclude='/tmp/**' --exclude='/proc/**' \
  --exclude='/sys/**' --exclude='/dev/**' --exclude='/run/**'
```

### Шаг 2: fstab на SSD с PARTUUID
```bash
cat << 'EOF' | sudo tee /mnt/ssd/etc/fstab
# /etc/fstab: static file system information.
# Ubuntu uses PARTUUID for deterministic mounting (not LABEL)
PARTUUID=cc15fd91-e0ce-4651-bcd1-d018d708bea8	/	ext4	defaults,noatime	0	1
PARTUUID=6d3d7424-01	/boot/firmware	vfat	defaults	0	2
EOF
```

### Шаг 3: Проверка identity на SSD
```bash
cat /mnt/ssd/etc/hostname      # Должно быть motya
cat /mnt/ssd/etc/machine-id    # Должен быть НЕ пустой
```

### Шаг 4: cmdline.txt на microSD с PARTUUID SSD
```bash
# ОБА файла должны быть обновлены (Ubuntu tryback)
cat << 'EOF' | sudo tee /boot/firmware/cmdline.txt
cfg80211.ieee80211_regdom=RU console=serial0,115200 console=tty1 root=PARTUUID=cc15fd91-e0ce-4651-bcd1-d018d708bea8 rootfstype=ext4 fsck.repair=yes rootwait quiet plymouth.ignore-serial-consoles
EOF

cat << 'EOF' | sudo tee /boot/firmware/current/cmdline.txt
cfg80211.ieee80211_regdom=RU console=serial0,115200 console=tty1 root=PARTUUID=cc15fd91-e0ce-4651-bcd1-d018d708bea8 rootfstype=ext4 fsck.repair=yes rootwait quiet plymouth.ignore-serial-consoles
EOF
```

### Шаг 5: Изменить LABEL на microSD
```bash
sudo tune2fs -L writable-sd /dev/mmcblk0p2
```

### Шаг 6: Чеклист перед перезагрузкой
```bash
# Все три PARTUUID должны совпадать:
grep -o 'root=PARTUUID=[^ ]*' /boot/firmware/cmdline.txt
sudo blkid -s PARTUUID -o value /dev/sda2
grep 'PARTUUID.*\/' /mnt/ssd/etc/fstab

# LABEL должны отличаться:
sudo blkid -s LABEL -o value /dev/mmcblk0p2  # writable-sd
sudo blkid -s LABEL -o value /dev/sda2        # writable
```

### Шаг 7: Перезагрузка
```bash
sudo umount /mnt/ssd
sudo reboot
```

---

## Результат успешной миграции

| Параметр | Значение |
|----------|----------|
| Root устройство | `/dev/sda2` (SSD) ✅ |
| Boot устройство | `/dev/mmcblk0p1` (microSD) ✅ |
| microSD LABEL | `writable-sd` ✅ |
| SSD LABEL | `writable` ✅ |
| fstab | `PARTUUID=cc15fd91-e0ce-4651-bcd1-d018d708bea8` ✅ |
| cmdline.txt | `root=PARTUUID=cc15fd91-e0ce-4651-bcd1-d018d708bea8` ✅ |
| hostname | `motya` ✅ |
| machine-id | `2bf129d7ad98480da64455a731feadd2` ✅ |
| I/O ошибки | Нет ✅ |
| Скорость SSD | 34 MB/sec (USB 2.0) |

---

## Критичные отличия от предыдущих неудач

1. **Использование PARTUUID вместо LABEL** — детерминированное поведение
2. **Изменение LABEL на microSD на writable-sd** — избегаем конфликта
3. **Обновление ОБОИХ cmdline.txt файлов** — Ubuntu tryback механизм
4. **Проверка hostname/machine-id** — нет конфликтов с другими хостами
5. **Чеклист ПЕРЕД перезагрузкой** — все файлы проверены одновременно

---

## Примечания

- **Ubuntu на Raspberry Pi использует ДВА cmdline.txt файла:** основной и current/
- **Boot partition остаётся на microSD** — только rootfs на SSD
- **PARTUUID формата XXXXXXXX-YY** для MBR (8 символов + номер раздела)
- **USB 2.0 ограничение:** 34 MB/sec — нормально для Raspberry Pi 4
