# Проверка состояния файловой системы

Этот документ описывает как проверить что файловая система на microSD или SSD находится в **корректном состоянии** и не была повреждена в результате неправильного размонтирования.

---

## Почему это важно

Неправильное размонтирование (pull out card без shutdown, crash системы, ошибка USB) может привести к:
- Файловая система в "грязном" состоянии (dirty)
- Потерянные данные в кэше (не записаны на диск)
- I/O ошибки при следующей загрузке
- Необходимость fsck при загрузке

---

## Проверка состояния файловой системы

### Ext4 (rootfs раздел)

```bash
# Проверить состояние файловой системы:
sudo tune2fs -l /dev/sda2 | grep -i "Filesystem state"

# Вывод:
# Filesystem state:         clean        ✅ Всё OK
# Filesystem state:         not clean    ⚠️ Было неправильное размонтирование
```

### Полная проверка без исправления

```bash
# -n = только проверка, НЕ вносить изменения
sudo fsck -n /dev/sda2

# Ключевые слова в выводе:
# clean                    ✅ Файловая система в порядке
# recovering journal       ⚠️ Восстановление журнала (было неправильное отключение)
# modifying                ⚠️ Есть ошибки для исправления
# FILESYSTEM WAS MODIFIED  ❌ Файловая система была изменена
```

### FAT32 (boot раздел на microSD)

```bash
# Проверить boot раздел (FAT32):
sudo fsck.vfat -n /dev/mmcblk0p1

# Или через fsck с типом:
sudo fsck -t vfat -n /dev/mmcblk0p1
```

---

## ⚠️ СОГЛАСОВАННОЕ изменение конфигурационных файлов

**КРИТИЧЕСКИ ВАЖНО:** При миграции на SSD или изменении boot конфигурации, несколько файлов должны быть изменены **СОГЛАСОВАННО**. Изменение только одного файла без остальных приведёт к тому, что система НЕ загрузится!

> **КРИТИЧЕСКИ ВАЖНО — ДВОЙНАЯ КОНФИГУРАЦИЯ:**
> Ubuntu на Raspberry Pi имеет boot разделы на **ОБОИХ** носителях — microSD И SSD!
> Конфигурационные файлы существуют на **ОБОИХ** и должны быть **ИДЕНТИЧНЫМИ**!

### Какие файлы взаимосвязаны (SSD migration)

| Файл | Назначение | Влияет на |
|------|------------|-----------|
| `/boot/firmware/cmdline.txt` | Параметры загрузки ядра | Какой rootfs монтируется |
| `/boot/firmware/current/cmdline.txt` | Backup для tryboot | Откат при сбое загрузки |
| `/etc/fstab` (microSD) | Монтирование при загрузке с microSD | Что монтирует systemd |
| `/etc/fstab` (SSD) | Монтирование при загрузке с SSD | Что монтирует systemd |
| **LABEL на microSD** | Идентификатор раздела | Как initramfs ищет rootfs |
| **LABEL на SSD** | Идентификатор раздела | Как initramfs ищет rootfs |
| **PARTUUID** | Уникальный ID раздела | Явное указание rootfs |

### ⚠️ ДВОЙНАЯ КОНФИГУРАЦИЯ — файлы на ОБАИХ носителях!

| Файл | На microSD | На SSD | Должны быть |
|------|-----------|-------|------------|
| `cmdline.txt` | `/boot/firmware/` | `/boot/firmware/` | **ИДЕНТИЧНЫ** |
| `current/cmdline.txt` | `/boot/firmware/` | `/boot/firmware/` | **ИДЕНТИЧНЫ** |
| `config.txt` | `/boot/firmware/` | `/boot/firmware/` | Синхронизированы |
| `fstab` | `/etc/` | `/etc/` | **РАЗНЫЕ** (указывают на свои разделы) |
| `hostname` | `/etc/` | `/etc/` | **ОДИНАКОВЫ** |
| `machine-id` | `/etc/` | `/etc/` | **ОДИНАКОВЫ** |

**Почему ОБА cmdline.txt должны быть ИДЕНТИЧНЫ:**
- microSD cmdline.txt → используется при загрузке, указывает где искать rootfs
- SSD cmdline.txt → используется системой ПОСЛЕ загрузки
- Если различаются → путаница, ошибки, перезагрузка!

**Проверка идентичности cmdline.txt:**
```bash
# При миграции (SSD смонтирован в /mnt/ssd):
diff /boot/firmware/cmdline.txt /mnt/ssd/boot/firmware/cmdline.txt
# Должен быть пустой вывод = файлы идентичны
```

### Последовательность согласованного изменения

```bash
# ШАГ 1: Получить актуальные идентификаторы
SSD_PARTUUID=$(blkid -s PARTUUID -o value /dev/sda2)
SD_PARTUUID=$(blkid -s PARTUUID -o value /dev/mmcblk0p2)
echo "SSD PARTUUID: $SSD_PARTUUID"
echo "SD PARTUUID:  $SD_PARTUUID"

# ШАГ 2: Изменить LABEL на microSD (избегаем конфликта)
sudo tune2fs -L writable-sd /dev/mmcblk0p2

# ШАГ 3: Проверить что LABEL изменился
blkid /dev/mmcblk0p2 | grep LABEL
# Должно быть: LABEL="writable-sd"

# ШАГ 4: Обновить fstab на microSD (используем PARTUUID)
cat << 'EOF' | sudo tee /etc/fstab
PARTUUID=${SD_PARTUUID}	/	ext4	errors=remount-ro	0	1
PARTUUID=$(blkid -s PARTUUID -o value /dev/mmcblk0p1)	/boot/firmware	vfat	defaults	0	2
EOF

# ШАГ 5: Обновить cmdline.txt на microSD (ОБА файла!)
# ВАЖНО: console=serial0 может вызывать зависание если UART не отвечает!
# ВАЖНО: panic=10 вызывает перезагрузку при ошибке - используем panic=-1 для отладки
CMDLINE="console=tty1 multipath=off dwc_otg.lpm_enable=0 root=PARTUUID=${SSD_PARTUUID} rootfstype=ext4 panic=-1 rootwait fixrtc cfg80211.ieee80211_regdom=RU cgroup_memory=1 cgroup_enable=memory"
echo "$CMDLINE" | sudo tee /boot/firmware/cmdline.txt > /dev/null
echo "$CMDLINE" | sudo tee /boot/firmware/current/cmdline.txt > /dev/null
sync

# ШАГ 5.5: Обновить cmdline.txt на SSD (ОБА файла!)
# КРИТИЧНО: SSD тоже имеет boot раздел со своими cmdline.txt!
echo "$CMDLINE" | sudo tee /mnt/ssd/boot/firmware/cmdline.txt > /dev/null
echo "$CMDLINE" | sudo tee /mnt/ssd/boot/firmware/current/cmdline.txt > /dev/null
sync

# ШАГ 6: Финальная проверка ВСЕХ файлов
echo "=== Проверка cmdline.txt ==="
grep "root=PARTUUID=" /boot/firmware/cmdline.txt
grep "root=PARTUUID=" /boot/firmware/current/cmdline.txt

echo "=== Проверка fstab ==="
cat /etc/fstab

echo "=== Проверка LABELS ==="
blkid /dev/mmcblk0p2 | grep LABEL
blkid /dev/sda2 | grep LABEL

echo "=== Проверка PARTUUID ==="
echo "cmdline: $(grep -o 'root=PARTUUID=[^ ]*' /boot/firmware/cmdline.txt)"
echo "SSD:     $(blkid /dev/sda2 | grep -o 'PARTUUID=\"[^\"]*\"')"
```

### Чеклист согласованного изменения

**ПЕРЕД перезагрузкой - проверить ВСЕ:**

- [ ] **cmdline.txt (microSD)** содержит `root=PARTUUID=<SSD_PARTUUID>`
- [ ] **cmdline.txt (SSD)** содержит `root=PARTUUID=<SSD_PARTUUID>`
- [ ] **cmdline.txt (microSD) = cmdline.txt (SSD)** — ИДЕНТИЧНЫ!
- [ ] **current/cmdline.txt (microSD)** содержит `root=PARTUUID=<SSD_PARTUUID>`
- [ ] **current/cmdline.txt (SSD)** содержит `root=PARTUUID=<SSD_PARTUUID>`
- [ ] **cmdline.txt** НЕ содержит `console=serial0` (может вызывать зависание!)
- [ ] **cmdline.txt** содержит `panic=-1` или нет panic (НЕ panic=10 - перезагрузка!)
- [ ] **fstab (microSD)** использует PARTUUID microSD, не LABEL
- [ ] **fstab (SSD)** использует PARTUUID SSD, не LABEL
- [ ] **LABEL microSD** = writable-sd (НЕ writable!)
- [ ] **LABEL SSD** = writable
- [ ] **PARTUUID в cmdline** совпадает с PARTUUID SSD
- [ ] **hostname на SSD** совпадает с именем хоста
- [ ] **machine-id на SSD** уникален (не копируется с другого хоста!)
- [ ] **Нет конфликтующих сервисов** (k3s, docker от другого хоста)

**Если ХОТЯ БЫ ОДИН пункт не выполнен — НЕ ПЕРЕЗАГРУЖАТЬ!**

### Почему происходит поэтапный "поиск" проблем

**Неправильный подход (постепенный поиск):**
```
1. Изменить cmdline.txt → перезагрузка → FAIL
2. Исправить LABEL → перезагрузка → FAIL
3. Исправить fstab → перезагрузка → SUCCESS
```

**Правильный подход (согласованное изменение):**
```
1. Проверить ВСЕ файлы
2. Изменить ВСЕ файлы СОГЛАСОВАННО
3. Проверить ВСЕ файлы
4. ТОЛЬКО ПОТОМ перезагрузка
```

---

## ⚠️ Проверки параметров вызывающих ПЕРЕЗАГРУЗКУ

**КРИТИЧЕСКИ ВАЖНО:** Некоторые параметры в cmdline.txt и конфигурационных файлах могут вызывать **бесконечную перезагрузку**. Эти проверки обязательны ПЕРЕД первой загрузкой после миграции!

### 1. Проверка console параметров

```bash
# Проверить console параметры в cmdline.txt:
cat /boot/firmware/cmdline.txt | grep -o 'console=[^ ]*'

# ❌ ПЛОХО: console=serial0,115200
# Если UART не отвечает или не сконфигурирован → система зависает → перезагрузка

# ✅ ХОРОШО: console=tty1
# Видео консоль всегда работает
```

**Почему serial console вызывает проблему:**
- Raspberry Pi 5 может не иметь подключённого UART
- Ошибка "Порт UART не найден" → system d ждёт ответа → timeout → перезагрузка
- Особенно критично если serial0 указан ПЕРЕД tty1

### 2. Проверка panic параметра

```bash
# Проверить panic параметр:
cat /boot/firmware/cmdline.txt | grep -o 'panic=[^ ]*'

# ❌ ПЛОХО: panic=10
# При любой kernel panic → перезагрузка через 10 секунд
# Не видно сообщение об ошибке!

# ✅ ХОРОШО: panic=-1 или нет panic
# При kernel panic → система остановится и покажет ошибку
```

**Рекомендация для отладки:**
```
Во время тестирования миграции: panic=-1 (остановиться при ошибке)
После успешной миграции:       убрать panic или panic=5 (для production)
```

### 3. Проверка hostname и machine-id

```bash
# Если SSD скопирован с другого хоста — проверить identity:
cat /mnt/ssd/etc/hostname      # Должен быть motya, НЕ sema!
cat /mnt/ssd/etc/machine-id    # Должен быть уникальным!

# Если hostname/machine-id скопированы:
echo "motya" > /mnt/ssd/etc/hostname
uuidgen | tr -d '-' > /mnt/ssd/etc/machine-id
```

**Почему это важно:**
- hostname=sema на motya → сетевой конфликт
- k3s/docker с чужим конфигом → сервис падает → перезагрузка
- Одинаковый machine-id → systemd путается

### 4. Проверка конфликтующих сервисов

```bash
# Проверить есть ли k3s на SSD:
ls /mnt/ssd/etc/rancher/k3s/
ls /mnt/ssd/etc/systemd/system/k3s.service

# Если есть и это другой хост — удалить:
rm -rf /mnt/ssd/etc/rancher/k3s/*
rm -f /mnt/ssd/etc/systemd/system/k3s.service
rm -f /mnt/ssd/etc/systemd/system/multi-user.target.wants/k3s.service

# Проверить docker контейнеры от другого хоста:
docker ps -a  # Если есть контейнеры с sema → docker rm -f ...
```

### Единая команда проверки ПЕРЕЗАГРУЗКИ

```bash
# Проверить ВСЕ параметры которые могут вызвать перезагрузку:
echo "=== Console check ===" && \
grep -o 'console=[^ ]*' /boot/firmware/cmdline.txt && \
echo "" && echo "=== Panic check ===" && \
grep -o 'panic=[^ ]*' /boot/firmware/cmdline.txt && \
echo "" && echo "=== Hostname ===" && \
cat /mnt/ssd/etc/hostname && \
echo "" && echo "=== Machine-id ===" && \
cat /mnt/ssd/etc/machine-id && \
echo "" && echo "=== Conflicting services ===" && \
(ls /mnt/ssd/etc/systemd/system/k3s* 2>/dev/null | wc -l) && \
echo "k3s files found (should be 0)"
```

**Ожидаемый результат:**
```
=== Console check ===
console=tty1                        ✅ НЕ serial0!

=== Panic check ===
panic=-1                           ✅ НЕ 10!

=== Hostname ===
motya                               ✅ Правильный хост!

=== Machine-id ===
abc123...                           ✅ Уникальный!

=== Conflicting services ===
0                                   ✅ Нет k3s!
```

---

## Быстрая проверка карты в card reader

При проверке microSD карты на другом хосте (например, через USB card reader):

```bash
# 1. Найти устройство:
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT

# 2. Проверить ext4 раздел (rootfs):
sudo tune2fs -l /dev/sdX2 | grep -i "Filesystem state"

# 3. Проверить FAT32 раздел (boot):
sudo fsck.vfat -n /dev/sdX1

# 4. Если "not clean" - запустить исправление:
sudo fsck -y /dev/sdX2
```

---

## Связанные документы

- **[SSD Migration Manual](ssd-migration-manual.md)** — полное руководство по миграции на SSD
- **[SSD Migration Checklist](ssd-migration-checklist.md)** — чеклист ПЕРЕД перезагрузкой
- **[SSD Precheck](ssd-precheck.md)** — проверка SSD перед миграцией
- **[Lessons Learned](lessons-learned.md)** — ошибки и их решения
- **[Ubuntu Network Fix](ubuntu-network-fix.md)** — исправление сети на Ubuntu для Raspberry Pi

---

## I/O ошибки vs Dirty filesystem

| Симптом | Причина | Решение |
|---------|---------|---------|
| **Filesystem state: not clean** | Неправильное размонтирование | `sudo fsck -y /dev/sdX` |
| **Input/output error** | Физические ошибки на диске | Проверить диск на bad blocks |
| **Buffer I/O error** в dmesg | Умирающий диск/SD карта | Замена носителя |

---

## Проверка bad blocks (физических дефектов)

Если fsck находит ошибки повторно или есть I/O errors:

```bash
# Проверка на bad blocks (только чтение, безопасно):
sudo badblocks -s -v -o badblocks.txt /dev/sdX

# -s = показывать прогресс
# -v = verbose
# -o = записать найденные bad blocks в файл

# Если найдены bad blocks → диск/карта под замену
```

---

## Рекомендации перед извлечением

**ПЕРЕД извлечением microSD или отключением SSD:**

```bash
# 1. Синхронизировать кэш:
sync

# 2. Размонтировать все разделы:
sudo umount /boot/firmware
sudo umount /

# 3. Для SSH подключения использовать:
sudo systemctl poweroff
# или
sudo shutdown -h now
```

**НЕ извлекать** пока мигает LED активности на диске/карте!

---

## Автоматическая проверка при загрузке

Ubuntu на Raspberry Pi **автоматически** запускает `fsck` при загрузке если:

1. Файловая система помечена как "not clean"
2. Прошло определённое количество монтирований (проверить: `sudo tune2fs -l /dev/sda2 | grep Maxmount`)
3. Прошло определённое время с последней проверки

Если загрузка останавливается на fsck:
- Дождитесь завершения
- Если asked for repair — введите `y`
- Если critical errors — может потребоваться загрузка с другого носителя

---

## После миграции на SSD

После миграции rootfs на SSD (через ssd-migrate.yml):

```bash
# Проверить что SSD размонтирован правильно:
sudo tune2fs -l /dev/sda2 | grep "Filesystem state"

# Проверить на bad blocks (NEW SSD):
sudo badblocks -s -v /dev/sda

# Проверить скорость I/O:
sudo hdparm -tT /dev/sda
# Должно быть > 100 MB/sec для SSD
```
