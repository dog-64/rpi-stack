# Changelog - SSD Migration Project

## 2026-03-07 23:00 - УСПЕШНАЯ миграция motya на SSD

**Результат:** ✅ Motya загружается с SSD (/dev/sda2)

**Правильная процедура (проверено на Ubuntu 25.10):**

1. Скопировать rootfs на SSD: `rsync -axHAWX`
2. Обновить fstab на SSD с **PARTUUID**
3. Проверить hostname, machine-id на SSD
4. Обновить **ОБА** cmdline.txt файла на microSD с **PARTUUID** SSD
5. Изменить LABEL на microSD на `writable-sd`
6. Пройти полный чеклист перед перезагрузкой
7. Перезагрузить

**Критичные параметры:**

| Параметр | Значение motya |
|----------|----------------|
| Root устройство | `/dev/sda2` (SSD) ✅ |
| Boot устройство | `/dev/mmcblk0p1` (microSD) ✅ |
| microSD LABEL | `writable-sd` ✅ |
| SSD LABEL | `writable` ✅ |
| cmdline.txt | `root=PARTUUID=cc15fd91-e0ce-4651-bcd1-d018d708bea8` ✅ |
| fstab | `PARTUUID=cc15fd91-e0ce-4651-bcd1-d018d708bea8` ✅ |
| hostname | `motya` ✅ |
| machine-id | `2bf129d7ad98480da64455a731feadd2` ✅ |

**Ограничение:** SSD скорость 34 MB/sec (USB 2.0) - нормально для Raspberry Pi 4

**Обновлено:**
- `ssd-migration-log.md` - правильная процедура миграции
- Playbook `ssd-migrate.yml` - проверен и работает
- Playbook `verify-ssd.yml` - подтверждает загрузку с SSD ✅

---

## 2026-03-06 13:00 - Обнаружена и задокументирована ДВОЙНАЯ КОНФИГУРАЦИЯ

**Проблема:** motya бесконечно перезагружался несмотря на все исправления

**Корневая причина:** cmdline.txt на microSD был исправлен, но на SSD остались старые значения!

| Файл | microSD | SSD | Проблема |
|------|---------|-----|----------|
| cmdline.txt | ✅ Исправлен | ❌ `console=serial0`, `root=LABEL=writable` | Конфликт! |

**Почему это произошло:**
- Ubuntu на Raspberry Pi имеет boot разделы на **ОБОИХ** носителях
- microSD cmdline.txt → используется при загрузке
- SSD cmdline.txt → используется системой ПОСЛЕ загрузки
- Я проверял и исправлял только microSD, забыл про SSD!

**Что добавлено в документацию:**

**`filesystem-health-check.md`:**
- Раздел про двойную конфигурацию (таблица файлов на ОБАИХ носителях)
- ШАГ 5.5: Обновление cmdline.txt на SSD
- Чеклист: проверка идентичности cmdline.txt на microSD и SSD

**`ssd-migration-checklist.md`:**
- Раздел "ДВОЙНАЯ КОНФИГУРАЦИЯ — microSD И SSD"
- Таблица: какие файлы на каком носителе находятся
- Команда проверки идентичности cmdline.txt

**Правило:**
```
ПРИ ИЗМЕНЕНИИ ЗАГРУЗОЧНЫХ ПАРАМЕТРОВ — обновлять на ОБАИХ носителях:

diff /boot/firmware/cmdline.txt /mnt/ssd/boot/firmware/cmdline.txt
# Должен быть пустой вывод = файлы идентичны
```

---

## 2026-03-06 12:00 - Добавлены проверки параметров ПЕРЕЗАГРУЗКИ

**Проблема:** motya бесконечно перезагружался из-за нескольких неочевидных проблем

**Обнаруженные проблемы:**
1. `console=serial0,115200` — UART не отвечал → "Порт UART не найден" → перезагрузка
2. `panic=10` — при любой ошибке перезагрузка через 10 сек → не видно ошибку
3. hostname=`sema` на motya — сетевой конфликт → k3s падал → перезагрузка
4. k3s сервисы от sema — неправильный конфиг → крах сервиса → перезагрузка

**Что добавлено в документацию:**

**`filesystem-health-check.md`:**
- Раздел "Проверки параметров вызывающих ПЕРЕЗАГРУЗКУ"
- Проверка console параметров (serial0 вызывает зависание!)
- Проверка panic параметра (10 скрывает ошибки!)
- Проверка hostname/machine-id (конфликты!)
- Проверка конфликтующих сервисов (k3s, docker)
- Единая команда проверки всех параметров

**`ssd-migration-checklist.md`:**
- Проверка #7: Console check
- Проверка #8: Hostname и machine-id
- Проверка #9: Конфликтующие сервисы
- Проверка #10: Единая команда ВСЕХ проверок

**Критичные правила:**
- ❌ НЕ использовать `console=serial0` (используйте `console=tty1`)
- ❌ НЕ использовать `panic=10` при отладке (используйте `panic=-1`)
- ❌ НЕ копировать hostname/machine-id с другого хоста
- ❌ НЕ оставлять k3s от другого хоста на SSD

---

## 2026-03-06 11:00 - Добавлена документация по СОГЛАСОВАННЫМ изменениям

**Причина:** Многократные циклы "изменить → перезагрузиться → FAIL" из-за проверки только одного файла

**Что добавлено в `filesystem-health-check.md`:**
- Раздел "СОГЛАСОВАННОЕ изменение конфигурационных файлов"
- Таблица взаимосвязанных файлов (cmdline.txt, fstab, LABELS, PARTUUID)
- Последовательность согласованного изменения (7 шагов)
- Чеклист проверки ВСЕХ файлов ПЕРЕД перезагрузкой

**Что добавлено в `ssd-migration-checklist.md`:**
- Единая команда проверки ВСЕХ 7 файлов одновременно
- Правило: НЕ изменять по одному файлу за раз
- Предупреждение про поэтапный "поиск" проблем

**Ключевой принцип:**
```
❌ НЕПРАВИЛЬНО: cmdline → перезагрузка → FAIL → fstab → перезагрузка → FAIL → LABEL → ...
✅ ПРАВИЛЬНО:    проверить ВСЕ → изменить ВСЕ → проверить ВСЕ → перезагрузка
```

---

## 2026-03-06 10:00 - Исправлен playbook update_cmdline.yml

**Проблема:** Playbook пропускал обновление cmdline.txt для Ubuntu ("LABEL auto-detection")

**Исправления в `roles/ssd_rootfs/tasks/update_cmdline.yml`:**
1. ✅ Удалён пропуск Ubuntu — ВСЕГДА обновляем cmdline.txt
2. ✅ Получаем PARTUUID SSD динамически через `blkid`
3. ✅ Изменяем LABEL на microSD на `writable-sd` (избегаем конфликт)
4. ✅ Обновляем ОБА cmdline.txt файла (Ubuntu tryboot: cmdline.txt + current/)
5. ✅ Используем явный `root=PARTUUID=` вместо LABEL
6. ✅ Добавлены CRITICAL assert проверки после каждого шага

**Исправления в `roles/ssd_rootfs/tasks/verify.yml`:**
1. ✅ Добавлена проверка cmdline.txt для Ubuntu
2. ✅ Добавлена проверка current/cmdline.txt для Ubuntu tryboot
3. ✅ Assert вызывает ошибку если PARTUUID не найден

**Теперь playbook НЕЛЬЗЯ запустить без верификации:**
- Если cmdline.txt не содержит root=PARTUUID=SSD → playbook FAIL
- Если current/cmdline.txt не содержит root=PARTUUID=SSD → playbook FAIL
- Если microSD LABEL = writable → playbook FAIL

---

## 2026-03-06 09:45 - Создан SSD Migration Checklist

**Причина:** Многократные проблемы с загрузкой после миграции из-за пропущенных проверок

**Что сделано:**
- Создан `docs/ssd-migration-checklist.md` — обязательные проверки ПЕРЕД перезагрузкой
- Добавлена ссылка в ssd-migration-manual.md

**Содержание чеклиста:**
1. ✅ Проверка cmdline.txt (ОБА файла!) содержит root=PARTUUID=SSD
2. ✅ Проверка PARTUUID соответствует SSD
3. ✅ Проверка LABEL: microSD ≠ writable, SSD = writable
4. ✅ Проверка fstab на SSD
5. ✅ Проверка что rootfs скопирован
6. ✅ Проверка initramfs

**Bug обнаружен:** `update_cmdline.yml` пропускает Ubuntu ("LABEL auto-detection")
→ Всегда обновлять cmdline.txt вручную!

---

## 2026-03-06 - Добавлена документация по проверке файловой системы

**Что сделано:**
1. Создан `docs/filesystem-health-check.md` — проверка состояния ФС
2. Добавлены ссылки между документами:
   - ssd-migration-manual.md → filesystem-health-check.md
   - ssd-precheck.md → filesystem-health-check.md
   - lessons-learned.md → filesystem-health-check.md

**Содержимое filesystem-health-check.md:**
- Проверка флага "clean" в ext4 superblock (`tune2fs`)
- Проверка через fsck без исправления (`fsck -n`)
- Проверка bad blocks (`badblocks`)
- Рекомендации перед извлечением карты

**Связь с другими документами:**
- SSD Migration Manual — проверка SSD перед/после миграции
- SSD Precheck — проверка перед началом работ
- Lessons Learned — случаи неправильного размонтирования

---

## 2026-03-05 21:00 - fix-sd-network.sh исправлен

**Проблема:** Скрипт не исправлял cmdline.txt если current/cmdline.txt тоже был повреждён

**Диагностика:**
- Скрипт брал `CURRENT_CMDLINE` из `current/cmdline.txt` как источник "правильной" строки
- Если оба файла содержали только `cfg80211`, то и "исправленная" версия была неправильной
- Не было верификации после записи

**Исправления:**
1. Добавлена проверка: если `current/cmdline.txt` не содержит `root=`, используется стандартная строка
2. Добавлена верификация после записи (проверка что файл действительно записан)
3. Сообщение об успехе изменено на "cmdline.txt ИСПРАВЛЕН и ПРОВЕРЕН"

**Стандартная cmdline:**
```bash
console=serial0,115200 multipath=off dwc_otg.lpm_enable=0 console=tty1 root=LABEL=writable rootfstype=ext4 panic=10 rootwait fixrtc
```

---

## 2026-03-05 20:00 - motya microSD исправлена (окончательно)

**Проблема:** motya не загружалась, сервисы падали

**Диагностика:**
- cmdline.txt исправлен (оба файла)
- fstab правильный
- Файловая система чистая
- **НО:** `/etc/machine-id` был ПУСТЫМ (0 bytes)

**Корневая причина:**
Systemd требует уникальный machine-id. Без него:
- Сервисы не стартуют
- Journal не пишется
- Systemd не работает

**Решение:**
```bash
# Сгенерирован новый machine-id
/etc/machine-id = dc79da840b6e4f728b9990236f5c671a
/var/lib/dbus/machine-id = dc79da840b6e4f728b9990236f5c671a
```

**Действия:** microSD готова для установки в motya

---

## 2026-03-05 19:00 - motya microSD исправлена

**Проблема:** motya не загружался

**Диагностика:**
- cmdline.txt на boot разделе содержал только `cfg80211.ieee80211_regdom=RU`
- Отсутствовал параметр `root=` — система не знала откуда грузить rootfs
- Это свежая установка Ubuntu (не мигрирована на SSD)

**Причина:** Скрипт `fix-sd-network.sh` перезаписал cmdline.txt, потеряв оригинальную конфигурацию

**Решение:** Восстановлен cmdline.txt:
```
console=serial0,115200 multipath=off dwc_otg.lpm_enable=0 console=tty1 root=LABEL=writable rootfstype=ext4 panic=10 rootwait fixrtc cfg80211.ieee80211_regdom=RU
```

**Действия:** microSD готова для установки в motya

---

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
