# Changelog - SSD Migration Project

## 2026-03-05 - osya успешно мигрирован на SSD

**Что сделано:**
1. Заменён VIA VL817 адаптер на ASMedia (174c:235c) — скорость 8→178 MB/sec
2. Исправлен cmdline.txt на microSD (добавлен root=PARTUUID)
3. Запущена миграция через ssd-migrate.yml
4. Проверка: 178 MB/sec, USB 3.0, нет I/O ошибок

**Проблемы которые были:**
- VIA VL817 адаптер: 8 MB/sec (заменён на ASMedia)
- cmdline.txt на microSD содержал только cfg80211.ieee80211_regdom=RU (нет root=)
- fix-sd-network.sh не проверяет cmdline.txt

**Записи в lessons-learned.md:**
- VIA VL817 проблемный на Pi 4 → ASMedia работает
- Проверять cmdline.txt содержит root= перед завершением миграции

---

## 2026-03-03 19:30 - Создана документация по проверке SSD

**Что сделано:**
1. Создан `docs/ssd-precheck.md` - подробная инструкция по проверке SSD перед миграцией
2. Добавлены ссылки в README.md и ssd-migration-manual.md
3. Создан `playbooks/ssd-precheck.yml` - автоматическая проверка SSD

**Проверка включает:**
- SSD обнаружен и имеет разделы
- Скорость чтения > 100 MB/sec
- Отсутствие I/O ошибок
- USB 3.0 подключение (5000M)
- Драйвер uas

**Использование:**
```bash
ansible-playbook playbooks/ssd-precheck.yml -l <HOST>
```

## 2026-03-03 18:57 - osya успешно мигрирован на SSD

**Что было сделано:**
1. Форматирован свежий microSD с fix-sd-network.sh
2. Подключён другой SSD (Apacer 128GB)
3. Исправлены конфиги вручную (плейбук не работает для уже загруженных систем):
   - `cmdline.txt`: добавлен `root=PARTUUID=08492e25-02`
   - `microSD LABEL`: изменён на `writable-sd` (tune2fs)
   - `fstab`: очищен от дубликатов, только PARTUUID
4. Перезагружен - загрузка с SSD прошла успешно

**BUG в плейбуке:** `update_cmdline.yml` пропускает обновление для Ubuntu, думая что initramfs сам найдёт LABEL
**BUG в плейбуке:** `detect_ssd.yml` останавливает выполнение через `meta: end_host` если уже на SSD

## 2026-03-03

### Проблема: cmdline.txt не содержит root= параметр
**Причина:** `update_cmdline.yml` пропускает обновление для Ubuntu, думая что initramfs сам найдет LABEL=writable.
Но если cmdline.txt был перезаписан (например fix-sd-network.sh), параметр root= теряется.

**Решение:** Исправил вручную: добавил `root=PARTUUID=cc15fd91-e0ce-4651-bcd1-d018d708bea8`
**Нужно:** Исправить плейбук, чтобы он ВСЕГДА проверял наличие root= в cmdline.txt

### Проблема: USB card reader не работает стабильно
**Симптом:** sdc постоянно появляется/исчезает, I/O ошибки
**Причина:** Дешёвые USB card readers на Raspberry Pi работают через UAS, который нестабилен
**Решение:** Проверять microSD на Mac, не на Pi

### Проблема: microSD LABEL=writable-sd но fstab на microSD имеет PARTUUID microSD
**Это правильно!** systemd использует fstab с PARTUUID, initramfs использует cmdline с root=

---

## Архитектура загрузки Ubuntu на Raspberry Pi

1. **Boot partition** (/boot/firmware на microSD) - всегда на microSD
   - cmdline.txt - параметр root= указывает где искать rootfs
   - config.txt - конфигурация Raspberry Pi

2. **initramfs** - загружается из boot partition
   - Читает cmdline.txt, ищет root= (LABEL=writable или PARTUUID)
   - Монтирует root filesystem
   - Передаёт управление systemd

3. **systemd** - загружается из root filesystem
   - Читает /etc/fstab на rootfs
   - Перемонтирует согласно fstab (использует PARTUUID)

---

## Критичные конфиги для миграции

### cmdline.txt (на microSD /boot/firmware)
```
cfg80211.ieee80211_regdom=RU console=serial0,115200 multipath=off dwc_otg.lpm_enable=0 console=tty1 root=PARTUUID=SSD_PARTUUID rootfstype=ext4 panic=10 rootwait fixrtc
```
**Критично:** параметр root= должен указывать на SSD PARTUUID

### fstab на SSD (rootfs)
```
PARTUUID=SSD_PARTUUID    /    ext4    defaults,noatime    0 1
PARTUUID=SD_PARTUUID     /boot/firmware    vfat    defaults    0 2
```
**Критично:** / должен указывать на SSD, /boot/firmware на microSD

### Метки (LABEL)
- **microSD rootfs:** LABEL=writable-sd (чтобы initramfs его не использовал)
- **SSD rootfs:** LABEL=writable (чтобы initramfs нашёл root, если cmdline использует LABEL)

---

## Ошибки которые НЕ нужно повторять

1. ❌ **Не менять** microSD LABEL на writable-sd в fstab на microSD - это не используется для boot!
2. ❌ **Не полагаться** только на LABEL=writable для initramfs - cmdline.txt должен иметь root=
3. ❌ **Не проверять** microSD на Pi через USB card reader - использовать Mac
4. ❌ **Не форматировать** SSD без badblocks проверки
5. ❌ **Не забывать** fsck после извлечения microSD без proper shutdown
