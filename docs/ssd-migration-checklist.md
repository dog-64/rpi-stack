# SSD Migration Checklist - Чеклист перед перезагрузкой

**ВАЖНО:** Этот чеклист должен быть выполнен ПОЛНОСТЬЮ перед каждой перезагрузкой при миграции на SSD.

> **КРИТИЧЕСКОЕ ПРАВИЛО:**
> Проверяйте ВСЕ файлы ОДНОВРЕМЕННО. Изменение только одного файла без остальных приведёт к тому, что система НЕ загрузится!
>
> **НЕ** делайте: "изменю cmdline.txt → перезагружусь → проверю"
> **ДЕЛАЙТЕ**: "проверю ВСЕ → изменю ВСЕ → проверю ВСЕ → перезагружусь"

---

## ⚠️ ПРАВИЛО СОГЛАСОВАННОЙ ПРОВЕРКИ

**ВСЕ 7 файлов должны быть проверены ОДНОВРЕМЕННО:**

```bash
# Единая команда проверки ВСЕХ конфигурационных файлов:
echo "=== 1. cmdline.txt ===" && cat /boot/firmware/cmdline.txt && \
echo "" && echo "=== 2. current/cmdline.txt ===" && cat /boot/firmware/current/cmdline.txt && \
echo "" && echo "=== 3. fstab (microSD) ===" && cat /etc/fstab && \
echo "" && echo "=== 4. fstab (SSD) ===" && cat /mnt/ssd/etc/fstab && \
echo "" && echo "=== 5. LABELS ===" && blkid | grep -E '(mmcblk0p2|sda2).*LABEL' && \
echo "" && echo "=== 6. PARTUUID match ===" && \
echo "cmdline: $(grep -o 'root=PARTUUID=[^ ]*' /boot/firmware/cmdline.txt)" && \
echo "SSD:     $(blkid /dev/sda2 | grep -o 'PARTUUID=\"[^\"]*\"')"
```

**Если ХОТЯ БЫ ОДИН пункт неверный — НЕ ПЕРЕЗАГРУЖАТЬ!**

---

## ПЕРЕД ПЕРЕЗАГРУЗКОЙ — обязательные проверки

### 1. Проверка cmdline.txt на microSD (boot раздел)

```bash
# ОБА файла должны содержать root=PARTUUID=SSD:
cat /boot/firmware/cmdline.txt | grep "root=PARTUUID="
cat /boot/firmware/current/cmdline.txt | grep "root=PARTUUID="
```

**Ожидается:** `root=PARTUUID=<SSD_PARTUUID>` (НЕ LABEL=writable!)

❌ **Если `root=LABEL=writable`** → система загрузится с microSD, не SSD!

---

### 2. Проверка PARTUUID соответствует SSD

```bash
# PARTUUID в cmdline.txt должен совпадать с PARTUUID SSD:
blkid /dev/sda2 | grep PARTUUID
cat /boot/firmware/cmdline.txt | grep root=PARTUUID
```

**Ожидается:** PARTUUID совпадают!

---

### 3. Проверка LABEL на разделах

```bash
# microSD rootfs ДОЛЖЕН иметь другой LABEL:
blkid /dev/mmcblk0p2 | grep LABEL

# SSD rootfs ДОЛЖЕН иметь LABEL=writable:
blkid /dev/sda2 | grep LABEL
```

**Ожидается:**
- microSD: `LABEL="writable-sd"` или любой ДРУГОЙ (не writable!)
- SSD: `LABEL="writable"`

❌ **Если ОБА LABEL="writable"** → initramfs найдёт microSD первым!

**Исправление:**
```bash
sudo tune2fs -L writable-sd /dev/mmcblk0p2
```

---

### 4. Проверка fstab на SSD

```bash
# Если SSD смонтирован в /mnt/ssd:
cat /mnt/ssd/etc/fstab
```

**Ожидается:**
```
PARTUUID=<SSD_PARTUUID>    /    ext4    defaults,noatime    0 1
PARTUUID=<SD_BOOT_PARTUUID>    /boot/firmware    vfat    defaults    0 2
```

❌ **Если /boot/firmware указывает на SSD** → boot раздел будет на SSD, но firmware ищет на microSD!

---

### 5. Проверка что rootfs скопирован на SSD

```bash
# Проверить наличие ключевых файлов:
ls -la /mnt/ssd/etc/passwd
ls -la /mnt/ssd/etc/fstab
ls -la /mnt/ssd/bin/sh
```

**Ожидается:** Все файлы существуют.

---

### 6. Проверка initramfs (для Ubuntu)

```bash
# Ubuntu на Raspberry Pi использует initramfs для монтирования rootfs
# Проверить что initramfs существует:
ls -la /boot/firmware/initrd.img*

# Если initramfs обновлялся, пересоздать:
sudo update-initramfs -u
```

---

### 7. ⚠️ КРИТИЧНО: Проверка параметров ПЕРЕЗАГРУЗКИ

**Эти проверки ОБЯЗАТЕЛЬНЫ! Любая проблема здесь → бесконечная перезагрузка!**

```bash
# Проверка console параметра:
grep -o 'console=[^ ]*' /boot/firmware/cmdline.txt
# ✅ ОК: console=tty1
# ❌ ПЛОХО: console=serial0,115200 (вызывает зависание если UART не отвечает!)

# Проверка panic параметра:
grep -o 'panic=[^ ]*' /boot/firmware/cmdline.txt
# ✅ ОК: panic=-1 (остановиться при ошибке) или нет panic
# ❌ ПЛОХО: panic=10 (перезагрузка через 10 сек при любой ошибке!)
```

❌ **Если `console=serial0`** → UART может не отвечать → зависание → перезагрузка
❌ **Если `panic=10`** → Не увидите сообщение об ошибке → бесконечная перезагрузка

**Исправление:**
```bash
# Убрать console=serial0, изменить panic:
sed -i 's/console=serial0,[0-9]* //' /boot/firmware/cmdline.txt
sed -i 's/panic=10 /panic=-1 /' /boot/firmware/cmdline.txt
# Скопировать в current/cmdline.txt тоже!
```

---

### 8. ⚠️ КРИТИЧНО: Проверка hostname и machine-id

```bash
# Если SSD скопирован с другого хоста — проверить identity:
cat /mnt/ssd/etc/hostname      # Должен быть motya, НЕ sema!
cat /mnt/ssd/etc/machine-id    # Должен быть уникальным!
```

❌ **Если hostname=sema на motya** → сетевой конфликт → сервисы падают → перезагрузка
❌ **Если machine-id скопирован** → systemd путается → сервисы не стартуют

**Исправление:**
```bash
echo "motya" > /mnt/ssd/etc/hostname
uuidgen | tr -d '-' > /mnt/ssd/etc/machine-id
cp /mnt/ssd/etc/machine-id /mnt/ssd/var/lib/dbus/machine-id
```

---

### 9. ⚠️ КРИТИЧНО: Проверка конфликтующих сервисов

```bash
# Проверить есть ли k3s на SSD (от другого хоста):
ls /mnt/ssd/etc/rancher/k3s/
ls /mnt/ssd/etc/systemd/system/k3s.service

# Подсчёт конфликтующих файлов:
find /mnt/ssd/etc/systemd -name '*k3s*' | wc -l
# Должно быть: 0
```

❌ **Если k3s от другого хоста** → k3s пытается запуститься с чужим конфигом → падает → перезагрузка

**Исправление:**
```bash
rm -rf /mnt/ssd/etc/rancher/k3s/*
rm -f /mnt/ssd/etc/systemd/system/k3s.service
rm -f /mnt/ssd/etc/systemd/system/multi-user.target.wants/k3s.service
rm -f /mnt/ssd/etc/systemd/system/k3s.service.env
```

---

### 10. Единая команда ВСЕХ проверок

```bash
# Выполнить ПЕРЕД перезагрузкой - проверить всё сразу:
echo "=== 1. cmdline.txt ===" && grep root= /boot/firmware/cmdline.txt && \
echo "" && echo "=== 2. current/cmdline.txt ===" && grep root= /boot/firmware/current/cmdline.txt && \
echo "" && echo "=== 3. Console check (NO serial0!) ===" && grep console= /boot/firmware/cmdline.txt && \
echo "" && echo "=== 4. Panic check (should be -1 or missing) ===" && grep -o 'panic=[^ ]*' /boot/firmware/cmdline.txt || echo "no panic - OK"; \
echo "" && echo "=== 5. fstab (SSD) ===" && cat /mnt/ssd/etc/fstab | grep -v '^#' && \
echo "" && echo "=== 6. Hostname ===" && cat /mnt/ssd/etc/hostname && \
echo "" && echo "=== 7. Machine-id ===" && cat /mnt/ssd/etc/machine-id && \
echo "" && echo "=== 8. LABELS ===" && blkid | grep -E '(mmcblk0p2|sda2).*LABEL' && \
echo "" && echo "=== 9. k3s conflicts (should be 0) ===" && find /mnt/ssd/etc/systemd -name '*k3s*' 2>/dev/null | wc -l
```

---

## ПОСЛЕ ПЕРЕЗАГРУЗКИ — проверка успешности

### 1. Проверить что rootfs на SSD

```bash
df -h | grep '$$/\s'
# Ожидается: /dev/sda2 или другая sda
```

❌ **Если /dev/mmcblk0p2** → загрузка произошла с microSD!

---

### 2. Проверить скорость диска

```bash
sudo hdparm -t /dev/sda2
# Ожидается: > 100 MB/sec
```

---

### 3. Проверить логи на ошибки

```bash
sudo dmesg | grep -E '(I/O|error|offline)' | tail -20
# Ожидается: пусто или только старые ошибки
```

---

## Критичные ошибки ПЛЕЙБУКА

### Bug: update_cmdline.yml пропускает Ubuntu

**Проблема:** Таска пропускает обновление cmdline.txt для Ubuntu:
```
"Ubuntu использует LABEL auto-detection. Изменение не требуется."
```

**Решение:** Всегда обновлять cmdline.txt вручную для Ubuntu:
```bash
# 1. Изменить LABEL на microSD:
sudo tune2fs -L writable-sd /dev/mmcblk0p2

# 2. Обновить ОБА cmdline.txt файла:
PARTUUID=$(blkid -s PARTUUID -o value /dev/sda2)
echo "console=serial0,115200 multipath=off dwc_otg.lpm_enable=0 console=tty1 root=PARTUUID=$PARTUUID rootfstype=ext4 panic=10 rootwait fixrtc cfg80211.ieee80211_regdom=RU cgroup_memory=1 cgroup_enable=memory" | sudo tee /boot/firmware/cmdline.txt
sudo cp /boot/firmware/cmdline.txt /boot/firmware/current/cmdline.txt
sync
```

---

## Исправление playbook'а

**TODO:** Обновить `roles/ssd_rootfs/tasks/update_cmdline.yml`:
1. НЕ пропускать обновление для Ubuntu
2. Изменять LABEL на microSD на writable-sd
3. Обновлять ОБА cmdline.txt файла
4. Использовать PARTUUID вместо LABEL

---

## Связанные документы

- [→ SSD Migration Manual](ssd-migration-manual.md)
- [→ Lessons Learned](lessons-learned.md)
- [→ Filesystem Health Check](filesystem-health-check.md)

---

## ⚠️ КРИТИЧНО: Двойная конфигурация — microSD И SSD

**ВАЖНО:** Ubuntu на Raspberry Pi имеет boot разделы на **ОБОИХ** носителях!

### Где находятся конфигурационные файлы:

| Файл | microSD | SSD | Обновлять? |
|------|---------|-----|------------|
| `cmdline.txt` | `/boot/firmware/` | `/boot/firmware/` | ✅ **ОБА** |
| `current/cmdline.txt` | `/boot/firmware/` | `/boot/firmware/` | ✅ **ОБА** |
| `config.txt` | `/boot/firmware/` | `/boot/firmware/` | ✅ **ОБА** |
| `fstab` | `/etc/` | `/etc/` | ✅ **ОБА** |
| `hostname` | `/etc/` | `/etc/` | ✅ **ОБА** |
| `machine-id` | `/etc/` | `/etc/` | ✅ **ОБА** |

### Почему это важно:

1. **cmdline.txt на microSD** — указывает какой rootfs монтировать при загрузке
2. **cmdline.txt на SSD** — используется системой ПОСЛЕ загрузки
3. Если они различаются → путаница, ошибки, перезагрузка!

### Единая команда проверки ОБЕИХ сторон:

```bash
# При вставленной microSD и смонтированном SSD (/mnt/ssd):
echo "=== microSD cmdline ===" && cat /boot/firmware/cmdline.txt
echo "" && echo "=== SSD cmdline ===" && cat /mnt/ssd/boot/firmware/cmdline.txt
echo "" && echo "=== ДОЛЖНЫ БЫТЬ ОДИНАКОВЫ ===" && \
diff /boot/firmware/cmdline.txt /mnt/ssd/boot/firmware/cmdline.txt && \
echo "✅ Идентичны" || echo "❌ РАЗЛИЧАЮТСЯ - исправить!"
```

### Правило:

**ПРИ ИЗМЕНЕНИИ ЗАГРУЗОЧНЫХ ПАРАМЕТРОВ — обновлять на ОБАИХ носителях:**
