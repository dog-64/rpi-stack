# Lessons Learned — Ошибки и решения

Этот документ содержит извлеченные уроки из работы с Raspberry Pi кластером.
**Цель:** не повторять одни и те же ошибки.

---

## 2026-03-04: osya не загружается после USB quirks

### Контекст:
- **Хост:** osya (Raspberry Pi 4, 10.0.1.75)
- **SSD:** 119GB Apacer, через VIA VL817 адаптер (2109:0715)
- **Проблема:** скорость SSD 8.5 MB/sec вместо ожидаемых 100+
- **Система:** Ubuntu, загружена с SSD (/dev/sda2)

> **Решение:** Замена адаптера на ASMedia (174c:235c) дала 197 MB/sec.
> Подробности о протестированных адаптерах: [→ usb-adapters-tested.md](usb-adapters-tested.md)

### Что сделал:
1. Создал `/etc/modprobe.d/disable-uas-vl817.conf` с `options usb_storage quirks=2109:0715:u`
2. Обновил initramfs
3. Перезагрузил
4. **Не проверил решение перед применением**
5. **Не использовал rp-search агента**
6. **Не спросил подтверждение**

### Результат:
- osya не загрузился
- SSD с UAS quirks стал недоступен после перезагрузки
- quirks отключили UAS, но система уже загружалась через UAS

### Что должен был сделать:
1. **rp-search агент:** "USB quirks 2109:0715:u Raspberry Pi 4 safe breaks boot"
2. **Предложить альтернативы:**
   - Другой USB-SATA адаптер (JMS578 на sema/leha работает)
   - Тест на motya (не в продакшене)
3. **Спросить подтверждение** для изменения modprobe.d

### Правило на будущее:
```
ПЕРЕД изменением modprobe.d, cmdline.txt, fstab:
1. rp-search — что говорят про решение?
2. Альтернативы — есть ли другой способ?
3. Тест — на нерабочей системе
4. Подтверждение — пользователя
```

---

## 2026-03-05: motya не загружается — cmdline.txt перезаписан

### Контекст:
- **Хост:** motya (Raspberry Pi 4, Ubuntu)
- **Проблема:** Свежая установка Ubuntu с microSD не загружается
- **Действия:** Запускался fix-sd-network.sh на Mac для настройки сети

### Диагностика:
- `/boot/firmware/cmdline.txt` содержал только `cfg80211.ieee80211_regdom=RU`
- **Отсутствовал параметр `root=`** — система не знала откуда грузить rootfs
- В `current/cmdline.txt` была правильная строка с `root=LABEL=writable`

### Причина:
Фактическая причина неизвестна. Скрипт `fix-sd-network.sh` **НЕ трогает** cmdline.txt
(проверен код — пишет только meta-data и network-config).

Возможно:
- Ручное редактирование cmdline.txt для добавления cfg80211 параметра
- Использование другого скрипта/инструкции
- Ошибка при копировании/восстановлении

### Решение:
Восстановил cmdline.txt из current/:
```bash
console=serial0,115200 multipath=off dwc_otg.lpm_enable=0 console=tty1 root=LABEL=writable rootfstype=ext4 panic=10 rootwait fixrtc cfg80211.ieee80211_regdom=RU
```

### Правило на будущее:
```
НЕ ПЕРЕЗАПИСЫВАТЬ cmdline.txt!

Для добавления cfg80211.ieee80211_regdom=RU:
1. Прочитать текущий cmdline.txt
2. Добавить cfg80211.ieee80211_regdom=RU в КОНЕЦ строки
3. НЕ удалять существующие параметры (особенно root=)
```

### Правильный способ добавить cfg80211:
```bash
# Прочитать текущую строку
CURRENT=$(cat /boot/firmware/cmdline.txt)

# Добавить cfg80211 если его нет
if [[ ! "$CURRENT" =~ cfg80211.ieee80211_regdom ]]; then
    echo "$CURRENT cfg80211.ieee80211_regdom=RU" > /boot/firmware/cmdline.txt
fi
```

### После fix-sd-network.sh ВСЕГДА проверять:
```bash
cat /boot/firmware/cmdline.txt
# Должен содержать: root=LABEL=writable или root=PARTUUID=...
```

---

## 2026-03-05: motya не загружается — пустой machine-id

### Контекст:
- **Хост:** motya (Raspberry Pi 4, Ubuntu)
- **Проблема:** Сервисы не стартуют, система зависает на чёрном экране
- **Действия:** После исправления cmdline.txt система всё равно не грузилась

### Диагностика:
- cmdline.txt — ✅ исправлен (оба файла)
- fstab — ✅ правильный
- Файловая система — ✅ чистая после fsck
- Bad blocks — ✅ 0
- Journal — ❌ пустой (система никогда не грузилась)
- **`/etc/machine-id`** — ❌ **ПУСТОЙ ФАЙЛ (0 bytes)**

### Корневая причина:
**Systemd требует уникальный machine-id для работы!**

Без machine-id:
- Сервисы не стартуют
- Journal не пишется
- Systemd не работает правильно
- Система не может завершить загрузку

### Решение:
```bash
# Сгенерировать новый machine-id
uuidgen | tr -d '-' > /etc/machine-id

# Скопировать для dbus
cp /etc/machine-id /var/lib/dbus/machine-id

# Или на загруженной системе:
# systemd-machine-id-setup
```

### Правило на будущее:
```
ПРИ ПРОВЕРКЕ microSD ВСЕГДА проверять:
1. cmdline.txt — содержит root=?
2. fstab — правильный?
3. /etc/machine-id — НЕ ПУСТОЙ?

cat /etc/machine-id
# Должен быть 32 символа hex (не пустой)
```

### Как проверить machine-id:
```bash
# Размер должен быть > 0
ls -la /etc/machine-id

# Содержимое должно быть 32 символа hex
cat /etc/machine-id
# Пустой файл = система не загрузится!
```

---

### ВАЖНО: Ubuntu tryboot механизм

**Ubuntu на Raspberry Pi использует ДВА cmdline.txt файла:**
- `/boot/firmware/cmdline.txt` — основной
- `/boot/firmware/current/cmdline.txt` — резервный (backup)

**При boot система может откатывать из `current/` в основной!**

**При редактировании ОБЯЗАТЕЛЬНО обновить ОБА файла:**
```bash
# Обновить основной
echo "params" > /boot/firmware/cmdline.txt
# Обновить резервный
echo "params" > /boot/firmware/current/cmdline.txt
# Sync на диск
sync
```

**Иначе изменения будут потеряны при следующей загрузке!**

---

## Общие правила

### Критичные конфигурационные файлы (осторожно!):
- `/etc/modprobe.d/*` — модули ядра
- `/boot/firmware/cmdline.txt` — параметры загрузки
- `/etc/fstab` — монтирование файловых систем
- `tune2fs -L` — изменение меток разделов

### Перед изменением:
1. **rp-search** — что говорят про это решение?
2. **Альтернативы** — есть ли другой способ?
3. **Тест** — проверить на системе которая не в продакшене
4. **Откат** — как откатить если что-то пойдет не так?

### После изменения:
- Записать в `docs/changelog.md`

---

## 2026-03-05: osya не загружается после миграции SSD

### Контекст:
- **Хост:** osya (Raspberry Pi 4, Ubuntu)
- **SSD:** ASMedia адаптер (174c:235c), 197 MB/sec ✅
- **Проблема:** После миграции система не загрузилась (SSH connection refused)

### Что сделал:
1. Запустил плейбук ssd-migrate.yml
2. Плейбук завершился успешно
3. **НЕ ПРОВЕРИЛ cmdline.txt на microSD ПЕРЕД завершением**
4. **НЕ добавил задачу проверки cmdline.txt в плейбук**

### В чём проблема:
**Ubuntu на Raspberry Pi использует `/boot/firmware/cmdline.txt`, а не `/boot/cmdline.txt`**

Если в cmdline.txt нет `root=PARTUUID=SSD_PARTUUID`, система не найдёт rootfs на SSD.

### Что должно быть в cmdline.txt на microSD:
```
root=PARTUUID=<SSD_PARTUUID> rootfstype=ext4 rootwait ...
```

### Правило на будущее:
```
ПЕРЕД завершением миграции SSD (ОБЯЗАТЕЛЬНО):
1. Проверить /boot/firmware/cmdline.txt на microSD содержит root=PARTUUID=SSD
2. Если нет — добавить/исправить
3. ТОЛЬКО ПОСЛЕ этого завершать миграцию
```

### В плейбук ssd-migrate.yml добавить:
```yaml
# ПЕРЕД задачей "Display completion message" добавить:
- name: CRITICAL - Verify cmdline.txt has root=PARTUUID for SSD
  ansible.builtin.shell: "grep 'root=PARTUUID={{ ssd_root_partuuid }}' /boot/firmware/cmdline.txt"
  register: cmdline_check
  failed_when: cmdline_check.rc != 0
```

---
