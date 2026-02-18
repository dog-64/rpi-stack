# Миграция rootfs на SSD (ручной режим)

**Цель:** Перенос корневой файловой системы с microSD на SSD для Raspberry Pi 5 под Ubuntu 25.10.

**Принцип:** Boot остаётся на microSD, rootfs переносится на SSD. Загрузчик Ubuntu ищет `LABEL=writable` — именно это
определяет выбор rootfs.

---

## Предварительная проверка

```bash
# Подключиться по SSH
ssh dog@<HOST_IP>

# Проверить текущее состояние
cat /etc/os-release | head -5          # Ubuntu 25.10
df /                                    # Текущий root (mmcblk0p2 = microSD)
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT
```

**Ожидаемый вывод:**

```
NAME          SIZE TYPE FSTYPE   LABEL
mmcblk0       58G  disk
├─mmcblk0p1   512M part vfat     system-boot  ← Boot остаётся тут
└─mmcblk0p2   57G  part ext4     writable      ← Root сейчас тут
sda           112G disk
├─sda1        512M part vfat     bootfs
└─sda2        111G part ext4     writable      ← Цель миграции
```

---

## Шаг 1: Подключение SSD

```bash
# Создать точку монтирования
sudo mkdir -p /mnt/ssd

# Смонтировать SSD rootfs
sudo mount /dev/sda2 /mnt/ssd

# Проверить
df -h /mnt/ssd
```

**Критерий успеха:** SSD смонтирован в /mnt/ssd

**Откат:** Ничего не требуется — просто отмонтировать:

```bash
sudo umount /mnt/ssd
```

---

## Шаг 2: Синхронизация rootfs

> **Важно:** Эта операция занимает 5-15 минут в зависимости от объёма данных.

```bash
# Проверить свободное место на SSD
df -h /mnt/ssd
df -h /

# Создать резервную копию fstab на SSD
sudo cp /mnt/ssd/etc/fstab /mnt/ssd/etc/fstab.backup-$(date +%Y%m%d-%H%M%S)

# Синхронизация (ключи: -a архив, -x одна ФС, -H ссылки, -A ACL, -W целые файлы, -X attrs)
sudo rsync -axHAWX --info=progress2 \
  --exclude=/mnt/** \
  --exclude=/tmp/** \
  --exclude=/proc/** \
  --exclude=/sys/** \
  --exclude=/dev/** \
  --exclude=/run/** \
  / /mnt/ssd/

# Проверить результат
echo "RSYNC exit code: $?"
```

**Критерий успеха:** `RSYNC exit code: 0`

**Проверка:**

```bash
# Сравнить размеры
sudo du -shx /
sudo du -shx /mnt/ssd

# Проверить критические файлы
ls -la /mnt/ssd/etc/passwd /mnt/ssd/etc/shadow /mnt/ssd/etc/hostname
cat /mnt/ssd/etc/hostname
```

**Откат:** SSD остаётся нетронутым, система продолжает работать с microSD.

---

## Шаг 3: Изменение LABEL microSD

> **КРИТИЧЕСКИ ВАЖНО:** И microSD, и SSD имеют LABEL="writable". Загрузчик выберет тот, который найдёт первым. Нужно
> переименовать microSD!

```bash
# Проверить текущие LABEL
sudo blkid | grep -E 'mmcblk0p2|sda2'

# Изменить LABEL microSD (использовать tune2fs, НЕ e2label!)
sudo tune2fs -L writable-sd /dev/mmcblk0p2

# Проверить результат
sudo blkid | grep mmcblk0p2
```

**Ожидаемый вывод:**

```
/dev/mmcblk0p2: LABEL="writable-sd" ...
/dev/sda2: LABEL="writable" ...
```

**Критерий успеха:**

- microSD: LABEL="writable-sd"
- SSD: LABEL="writable"

**Откат (если что-то пошло не так):**

```bash
sudo tune2fs -L writable /dev/mmcblk0p2
```

---

## Шаг 4: Обновление fstab на SSD

```bash
# Проверить текущий fstab на SSD
cat /mnt/ssd/etc/fstab

# Должен содержать:
# LABEL=writable     /           ext4    defaults,noatime    0 1
# LABEL=system-boot  /boot/firmware  vfat    defaults        0 1
```

**Если fstab некорректный:**

```bash
# Создать резервную копию
sudo cp /mnt/ssd/etc/fstab /mnt/ssd/etc/fstab.pre-migration

# Записать корректный fstab
cat << 'EOF' | sudo tee /mnt/ssd/etc/fstab
LABEL=writable	/	ext4	defaults,noatime	0	1
LABEL=system-boot	/boot/firmware	vfat	defaults	0	1
EOF
```

**Проверка:**

```bash
cat /mnt/ssd/etc/fstab
```

**Откат:**

```bash
sudo cp /mnt/ssd/etc/fstab.backup-* /mnt/ssd/etc/fstab
```

---

## Шаг 5: Финальная верификация

```bash
echo "========================================"
echo "       VERIFICATION SUMMARY"
echo "========================================"

echo "1. SSD LABEL (должен быть 'writable'):"
sudo blkid -s LABEL -o value /dev/sda2

echo "2. microSD LABEL (должен быть 'writable-sd'):"
sudo blkid -s LABEL -o value /dev/mmcblk0p2

echo "3. SSD fstab root entry:"
grep '^LABEL=writable' /mnt/ssd/etc/fstab

echo "4. SSD fstab boot entry:"
grep 'system-boot' /mnt/ssd/etc/fstab

echo "5. Boot partition mounted:"
mount | grep '/boot/firmware'

echo "========================================"
```

**Критерии успеха:**

- ✓ SSD LABEL = writable
- ✓ microSD LABEL = writable-sd
- ✓ fstab содержит `LABEL=writable / ext4`
- ✓ fstab содержит `LABEL=system-boot /boot/firmware vfat`

---

## Шаг 6: Перезагрузка

```bash
# Отмонтировать SSD
sudo umount /mnt/ssd

# Проверить отсутствие процессов на SSD
lsof /mnt/ssd 2>/dev/null || echo "OK - no processes"

# Перезагрузка
sudo reboot
```

---

## Шаг 7: После перезагрузки

Подключиться через 60-90 секунд:

```bash
ssh dog@<HOST_IP>

echo "========================================"
echo "    POST-MIGRATION VERIFICATION"
echo "========================================"

echo "Root device:"
df /

echo "Block devices:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT

echo "Root is on:"
lsblk -no NAME,LABEL,MOUNTPOINT | grep '/$'
```

**Критерий успеха:**

```
NAME    LABEL      MOUNTPOINT
sda2    writable   /          ← ROOT НА SSD!
```

---

## Расширение файловой системы (если требуется)

Если SSD был предварительно размечен, но раздел меньше диска:

```bash
# Проверить размер раздела vs диска
lsblk /dev/sda

# Установить growpart если нет
sudo apt install cloud-guest-utils

# Расширить раздел (sda2 -> номер раздела = 2)
sudo growpart /dev/sda 2

# Расширить файловую систему
sudo resize2fs /dev/sda2

# Проверить новый размер
df -h /
```

---

## Процедура отката (экстренная)

Если после перезагрузки система не загружается с SSD:

### Вариант 1: Физическое отключение SSD

1. Выключить Pi
2. Отключить SSD от USB
3. Включить Pi → загрузится с microSD

### Вариант 2: Через Live USB / другой Linux

1. Подключить microSD к другому компьютеру
2. Найти раздел rootfs: `lsblk` (обычно mmcblk0p2 или sdX2)
3. Изменить LABEL обратно:
   ```bash
   sudo tune2fs -L writable /dev/sdX2
   ```
4. Вставить microSD в Pi → загрузится

---

## Краткий справочник команд

| Действие         | Команда                                                                                                                                                        |
|------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Монтировать SSD  | `sudo mount /dev/sda2 /mnt/ssd`                                                                                                                                |
| Синхронизировать | `sudo rsync -axHAWX --info=progress2 --exclude=/mnt/** --exclude=/tmp/** --exclude=/proc/** --exclude=/sys/** --exclude=/dev/** --exclude=/run/** / /mnt/ssd/` |
| Изменить LABEL   | `sudo tune2fs -L writable-sd /dev/mmcblk0p2`                                                                                                                   |
| Проверить LABEL  | `sudo blkid \| grep mmcblk0p2`                                                                                                                                 |
| Отмонтировать    | `sudo umount /mnt/ssd`                                                                                                                                         |
| Расширить ФС     | `sudo resize2fs /dev/sda2`                                                                                                                                     |

---

## Типичные проблемы

### Проблема: e2label не меняет LABEL

**Решение:** Использовать `tune2fs -L` вместо `e2label`

### Проблема: После перезагрузки всё ещё на microSD

**Причины:**

1. LABEL microSD не изменён → загрузчик выбирает microSD первым
2. fstab на SSD некорректный

**Диагностика:**

```bash
sudo blkid | grep -E 'mmcblk0p2|sda2'
cat /etc/fstab
```

### Проблема: Система не загружается вообще

**Решение:** См. "Процедура отката" выше

---

## Примечания для Ubuntu 25.10

Ubuntu 25.10 использует **tryboot** механизм:

- `/boot/firmware/current/` — текущая конфигурация
- `/boot/firmware/new/` — новая конфигурация (после обновлений)
- Автоматический откат при неудачной загрузке

Boot partition остаётся на microSD (`LABEL=system-boot`), что обеспечивает:

- Возможность отката через изменение LABEL
- Совместимость с tryboot механизмом
- Загрузка даже если SSD отключён
