# Миграция rootfs на SSD (ручной режим)

**Цель:** Перенос корневой файловой системы с microSD на SSD для Raspberry Pi 5 под Ubuntu 25.10.

**Принцип:**
- Boot partition остаётся на microSD (`LABEL=system-boot`)
- Rootfs переносится на SSD, монтируется через **PARTUUID** (уникальный идентификатор раздела)
- Загрузчик Ubuntu ищет `LABEL=writable` для initramfs, но fstab использует PARTUUID для надёжности

> **Почему PARTUUID, а не LABEL?**
> - LABEL="writable" может быть на нескольких дисках → конфликт
> - PARTUUID уникален для каждого раздела → deterministic behaviour
> - При загрузке с SSD systemd использует fstab, где указан PARTUUID

---

## ⚠️ Проверка SSD перед миграцией

> **КРИТИЧЕСКИ ВАЖНО:** Прочитай [→ Lessons Learned](lessons-learned.md) перед миграцией!
> Там описаны ошибки которые уже были сделаны — не повторяй их.
>
> Проверь SSD, адаптер и кабель:
> - [→ Lessons Learned (ошибки)](lessons-learned.md)
> - [→ SSD Pre-check Guide](ssd-precheck.md)
> - [→ USB Adapters Tested](usb-adapters-tested.md)
>
> **Краткая проверка:**
> ```bash
> # 1. SSD виден?
> lsblk | grep sd
> # 2. Скорость > 100 MB/sec?
> sudo hdparm -t /dev/sda2
> # 3. Нет I/O ошибок?
> sudo dmesg -T | grep -E '(I/O|error)' | tail -10
> ```

**Основная документация по проверке:** [→ SSD Pre-check Guide](ssd-precheck.md)

Ниже приведена краткая справочная информация для быстрой проверки.

### 1. Проверка скорости чтения

```bash
sudo hdparm -t /dev/sda2
```

**Ожидаемый результат:** 100-400 MB/sec (зависит от USB/SATA адаптера)

**Если < 30 MB/sec:** Проблема с адаптером или кабелем!

### 2. Проверка кабеля на ошибки

```bash
sudo dmesg -T | grep -E '(sda|SATA|error|abort)' | tail -20
```

**Ищем:**
- `uas_eh_abort_handler` - USB адаптер умирает
- `I/O error, dev sda` - ошибки чтения/записи
- `Synchronize Cache failed` - кеш не синхронизируется

**Если есть МНОГО ошибок за последние минуты:** Проблема с кабелем/адаптером!

### 3. Проверка на bad blocks

```bash
sudo badblocks -sv /dev/sda2 | tee badblocks.log
```

**Ожидаемый результат:** `Pass completed, 0 bad blocks found`

**Если > 0 bad blocks:** SSD умирает, заменить!

### 4. Форматирование SSD

```bash
sudo mkfs.ext4 -L writable /dev/sda2
```

**Зачем:**
- Уничтожает старые данные (предотвращает конфликты)
- Проверяет файловую систему
- Готовит чистый SSD для миграции

> **ВАЖНО:** Не пропускайте этот шаг! Старые данные на SSD вызовут I/O errors при загрузке.

---

## Предварительная проверка

```bash
# Подключиться по SSH
ssh dog@<HOST_IP>

# Проверить текущее состояние
cat /etc/os-release | head -5          # Ubuntu 25.10
df /                                    # Текущий root (mmcblk0p2 = microSD)
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT

# Найти SSD устройство (обычно sda, но может отличаться!)
lsblk -d -o NAME,SIZE,TYPE,MODEL | grep -E 'sd[^a]|ATA'
```

**Ожидаемый вывод:**

```
NAME          SIZE TYPE FSTYPE   LABEL
mmcblk0       58G  disk
├─mmcblk0p1   512M part vfat     system-boot  ← Boot остаётся тут
└─mmcblk0p2   57G  part ext4     writable      ← Root сейчас тут
sda           112G disk                      ← Это SSD!
├─sda1        512M part vfat     bootfs
└─sda2        111G part ext4     writable      ← Цель миграции
```

### Важно: определить ваш SSD раздел

```bash
# Показать все блочные устройства с PARTUUID
sudo blkid | grep -v 'loop'

# Найти PARTUUID SSD rootfs раздела (замените sda2 на ваш раздел!)
sudo blkid -s PARTUUID -o value /dev/sda2
# Сохраните этот вывод - он понадобится для fstab!
```

> **Внимание:** Если ваш SSD не `/dev/sda2`, замените все вхождения `sda2` в этом руководстве
> на ваш фактический раздел (например, `/dev/sdb2`, `/dev/sdc2`, и т.д.)

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

> **КРИТИЧЕСКИ ВАЖНО:** fstab должен использовать **PARTUUID**, а не LABEL!
> PARTUUID — это уникальный идентификатор раздела (Partition UUID), который не меняется
> при переформатировании и гарантирует монтирование именно нужного раздела.

### 4.1 Получить PARTUUID разделов

```bash
# Получить PARTUUID SSD rootfs раздела (sda2)
sudo blkid -s PARTUUID -o value /dev/sda2
# Вывод: ffc763c1-02 (пример)

# Получить PARTUUID microSD boot раздела (mmcblk0p1)
sudo blkid -s PARTUUID -o value /dev/mmcblk0p1
# Вывод: 6d3d7424-01 (пример)

# Сохранить в переменные для удобства
SSD_PARTUUID=$(sudo blkid -s PARTUUID -o value /dev/sda2)
SD_BOOT_PARTUUID=$(sudo blkid -s PARTUUID -o value /dev/mmcblk0p1)

echo "SSD PARTUUID: $SSD_PARTUUID"
echo "SD boot PARTUUID: $SD_BOOT_PARTUUID"
```

### 4.2 Проверить текущий fstab на SSD

```bash
cat /mnt/ssd/etc/fstab
```

**Ожидается увидеть (ПОСЛЕ миграции):**
```
PARTUUID=<SSD_PARTUUID>    /           ext4    defaults,noatime    0 1
PARTUUID=<SD_BOOT_PARTUUID> /boot/firmware  vfat    defaults        0 1
```

### 4.3 Обновить fstab (если некорректный)

```bash
# Создать резервную копию
sudo cp /mnt/ssd/etc/fstab /mnt/ssd/etc/fstab.pre-migration

# Подставить реальные PARTUUID вместо <SSD_PARTUUID> и <SD_BOOT_PARTUUID>
cat << EOF | sudo tee /mnt/ssd/etc/fstab
PARTUUID=$SSD_PARTUUID	/	ext4	defaults,noatime	0	1
PARTUUID=$SD_BOOT_PARTUUID	/boot/firmware	vfat	defaults	0	1
EOF
```

**Или вручную (замените значения на ваши PARTUUID):**
```bash
cat << 'EOF' | sudo tee /mnt/ssd/etc/fstab
PARTUUID=ffc763c1-02	/	ext4	defaults,noatime	0	1
PARTUUID=6d3d7424-01	/boot/firmware	vfat	defaults	0	1
EOF
```

### 4.4 Проверка

```bash
# Должен содержать PARTUUID
cat /mnt/ssd/etc/fstab | grep PARTUUID
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

# Получаем PARTUUID для проверки
SSD_PARTUUID=$(sudo blkid -s PARTUUID -o value /dev/sda2)
SD_BOOT_PARTUUID=$(sudo blkid -s PARTUUID -o value /dev/mmcblk0p1)

echo "1. SSD LABEL (должен быть 'writable'):"
sudo blkid -s LABEL -o value /dev/sda2

echo "2. microSD LABEL (должен быть 'writable-sd' или 'writable'):"
sudo blkid -s LABEL -o value /dev/mmcblk0p2

echo "3. SSD PARTUUID:"
echo "$SSD_PARTUUID"

echo "4. microSD boot PARTUUID:"
echo "$SD_BOOT_PARTUUID"

echo "5. SSD fstab root entry (должен содержать SSD PARTUUID):"
grep "^PARTUUID=$SSD_PARTUUID" /mnt/ssd/etc/fstab || grep 'PARTUUID=' /mnt/ssd/etc/fstab | head -1

echo "6. SSD fstab boot entry (должен содержать SD boot PARTUUID):"
grep "^PARTUUID=$SD_BOOT_PARTUUID" /mnt/ssd/etc/fstab || grep '/boot/firmware' /mnt/ssd/etc/fstab

echo "7. Boot partition mounted:"
mount | grep '/boot/firmware'

echo "========================================"
```

**Критерии успеха:**

- ✓ SSD LABEL = writable
- ✓ microSD LABEL = writable-sd (рекомендуется) или writable
- ✓ fstab содержит `PARTUUID=<SSD_PARTUUID> / ext4`
- ✓ fstab содержит `PARTUUID=<SD_BOOT_PARTUUID> /boot/firmware vfat`
- ✓ Boot partition смонтирован с microSD

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

echo "1. Root device (должен быть /dev/sda2):"
df /

echo "2. Block devices:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT

echo "3. Root partition details:"
lsblk -no NAME,LABEL,PARTUUID,MOUNTPOINT | grep '/$'

echo "4. fstab uses PARTUUID:"
cat /etc/fstab
```

**Критерий успеха:**

```
NAME    LABEL      PARTUUID         MOUNTPOINT
sda2    writable   ffc763c1-02      /          ← ROOT НА SSD!
```

**В fstab должно быть:**
```
PARTUUID=<ваш_ssd_partuuid>	/	ext4	defaults,noatime	0	1
PARTUUID=<ваш_sd_boot_partuuid>	/boot/firmware	vfat	defaults	0	1
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

| Действие            | Команда                                                                                                                                                        |
|---------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Монтировать SSD     | `sudo mount /dev/sda2 /mnt/ssd`                                                                                                                                |
| Синхронизировать    | `sudo rsync -axHAWX --info=progress2 --exclude=/mnt/** --exclude=/tmp/** --exclude=/proc/** --exclude=/sys/** --exclude=/dev/** --exclude=/run/** / /mnt/ssd/` |
| Получить PARTUUID   | `sudo blkid -s PARTUUID -o value /dev/sda2` (SSD) <br> `sudo blkid -s PARTUUID -o value /dev/mmcblk0p1` (SD boot)                                              |
| Изменить LABEL      | `sudo tune2fs -L writable-sd /dev/mmcblk0p2`                                                                                                                   |
| Проверить LABEL     | `sudo blkid \| grep mmcblk0p2`                                                                                                                                 |
| Отмонтировать       | `sudo umount /mnt/ssd`                                                                                                                                         |
| Расширить раздел    | `sudo growpart /dev/sda 2` <br> `sudo resize2fs /dev/sda2`                                                                                                    |

---

## Типичные проблемы

### Проблема: e2label не меняет LABEL

**Решение:** Использовать `tune2fs -L` вместо `e2label`

### Проблема: После перезагрузки всё ещё на microSD

**Причины:**

1. **fstab на SSD использует LABEL вместо PARTUUID** → systemd может смонтировать microSD первым
2. **LABEL microSD не изменён** → и microSD, и SSD имеют LABEL="writable"
3. **PARTUUID в fstab не соответствует SSD разделу**

**Диагностика:**

```bash
# Проверить какой device смонтирован как root
df /

# Проверить LABEL и PARTUUID
sudo blkid | grep -E 'mmcblk0p2|sda2'

# Проверить fstab - должен использовать PARTUUID!
cat /etc/fstab

# Если в fstab LABEL=writable - это проблема!
# Должен быть PARTUUID=<ваш_ssd_partuuid>
```

**Решение:**

1. Перемонтировать SSD и исправить fstab:
```bash
sudo mount /dev/sda2 /mnt/ssd
SSD_PARTUUID=$(sudo blkid -s PARTUUID -o value /dev/sda2)
SD_BOOT_PARTUUID=$(sudo blkid -s PARTUUID -o value /dev/mmcblk0p1)

sudo tee /mnt/ssd/etc/fstab << EOF
PARTUUID=$SSD_PARTUUID	/	ext4	defaults,noatime	0	1
PARTUUID=$SD_BOOT_PARTUUID	/boot/firmware	vfat	defaults	0	1
EOF
```

### Проблема: Система не загружается вообще

**Решение:** См. "Процедура отката" выше

### Проблема: Не могу найти PARTUUID

**Диагностика:**

```bash
# Показать все разделы с их PARTUUID
sudo blkid -o list

# Или для конкретного раздела
sudo blkid -s PARTUUID -o value /dev/sda2
sudo blkid -s PARTUUID -o value /dev/mmcblk0p1
```

---

## Примечания для Ubuntu 25.10

Ubuntu 25.10 использует **tryboot** механизм:

- `/boot/firmware/current/` — текущая конфигурация
- `/boot/firmware/new/` — новая конфигурация (после обновлений)
- Автоматический откат при неудачной загрузке

### Как работает загрузка с SSD:

1. **Boot partition** остаётся на microSD (`LABEL=system-boot`, `PARTUUID=6d3d7424-01`)
   - Содержит ядро, initramfs, и конфигурацию загрузчика
   - Всегда смонтирован в `/boot/firmware`

2. **Rootfs** находится на SSD (`LABEL=writable`, `PARTUUID=<уникальный>`)
   - Загрузчик ищет `LABEL=writable` для initramfs (emergency boot)
   - **systemd использует fstab с PARTUUID** для основного монтирования

3. **Почему fstab использует PARTUUID:**
   - Если оба раздела (SD и SSD) имеют `LABEL=writable`, systemd может выбрать неправильный
   - PARTUUID уникален → deterministic behaviour
   - При отключенном SSD система не загрузится (что правильно — rootfs недоступен)

### Преимущества текущей схемы:

- ✅ Возможность отката через изменение LABEL на microSD
- ✅ Совместимость с tryboot механизмом
- ✅ Надёжность: PARTUUID гарантирует монтирование правильного раздела
- ⚠️ Загрузка невозможна если SSD отключён (rootfs на нём)
