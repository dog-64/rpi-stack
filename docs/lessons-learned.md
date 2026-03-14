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

## 2026-03-07: motya k3s-agent — Node password rejected

### Контекст:
- **Хост:** motya (Raspberry Pi 4, k3s agent)
- **Проблема:** Узел в статусе `NotReady`, kubelet не отправляет статус
- **Последствия:** Pod'ы не могут запускаться на motya

> **Подробности:** [→ k3s-node-password-rejected.md](k3s-node-password-rejected.md)
> **Связано с:** [→ Time Synchronization Problem](k3s-node-time-sync-problem.md) — аналогичная проблема но с причиной в времени

### Симптомы:
```bash
ssh sema "sudo k3s kubectl get nodes"
# motya   NotReady   ...

ssh sema "sudo k3s kubectl describe node motya"
# Kubelet stopped posting node status
```

### Диагностика:
```bash
ssh motya "sudo systemctl status k3s-agent"
# Node password rejected, duplicate hostname or contents of
# '/etc/rancher/node/password' may not match server node-passwd entry
```

### Причина:
**После миграции SSD система была переустановлена → новый node-password → сервер не знает его.**

K3s хранит связь "узел-пароль" для безопасности. При переустановке системы password меняется, но на сервере остаётся старый.

### Решение:
```bash
# 1. Удалить узел с сервера
ssh sema "sudo k3s kubectl delete node motya"

# 2. Очистить данные агента
ssh motya "sudo systemctl stop k3s-agent"
ssh motya "sudo rm -rf /var/lib/rancher/k3s/agent/*"

# 3. Перезапустить (авторегистрация с новым паролем)
ssh motya "sudo systemctl start k3s-agent"
```

### Правило на будущее:
```
ПОСЛЕ миграции SSD на узле с k3s-agent ОБЯЗАТЕЛЬНО проверить:

1. ssh <hostname> "sudo systemctl status k3s-agent"
2. ssh sema "sudo k3s kubectl get nodes"

Если NotReady + "Node password rejected" → выполнить решение выше.
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

## 2026-03-05: fix-sd-network.sh не исправил cmdline.txt

### Контекст:
- **Действия:** Свежий образ Ubuntu записан через Raspberry Pi Imager
- **Скрипт:** fix-sd-network.sh запущен для настройки сети
- **Результат:** cmdline.txt всё равно содержал только `cfg80211.ieee80211_regdom=RU`
- **Проблема:** Система не загрузилась (нет root=)

### Диагностика:
Скрипт обнаружил что cmdline.txt не содержит root=, предложил исправить.
Пользователь выбрал "y" для авто-исправления.

**НО:** Скрипт брал `CURRENT_CMDLINE` из `current/cmdline.txt` как источник "правильной" строки.
Если `current/cmdline.txt` **тоже** повреждён (только `cfg80211`), то и "исправленная" версия неправильная!

### Решение:
**Исправлен скрипт fix-sd-network.sh:**
1. Добавлена проверка: если `current/cmdline.txt` не содержит `root=`, используется стандартная строка
2. Добавлена верификация после записи (проверка что файл действительно записан)

### Стандартная cmdline для Ubuntu Raspberry Pi:
```bash
console=serial0,115200 multipath=off dwc_otg.lpm_enable=0 console=tty1 root=LABEL=writable rootfstype=ext4 panic=10 rootwait fixrtc
```

### Правило на будущее:
```
ПРИ ИСПОЛЬЗОВАНИИ fix-sd-network.sh ВСЕГДА проверять:

После выбора "y" для авто-исправления:
1. Скрипт ДОЛЖЕН вывести "cmdline.txt ИСПРАВЛЕН и ПРОВЕРЕН"
2. Если выводится "ОШИБКА: Запись не удалась" — карта неисправна
3. После извлечения карты: перемонтировать и проверить cmdline.txt содержит root=
```

### Как проверить fix-sd-network.sh отработал правильно:
```bash
# После работы скрипта:
cat /Volumes/boot/cmdline.txt | grep root=
# Должен вывести: root=LABEL=writable или root=PARTUUID=...

# Если grep ничего не вывел — cmdline.txt повреждён!
```

---

## 2026-03-06: motya microSD — "Input/output error" но карта исправна

### Контекст:
- **Проблема:** При попытке прочитать `/tmp/motya_sd/etc/machine-id` — `Input/output error`
- **Предварительный диагноз:** Карта умерла (физические дефекты)
- **Проверка:** `dd if=/dev/rdisk11 of=/dev/null` — 63GB прочитано без ошибок!

### Диагностика:
Карта физически исправна. Проблема была в **неправильном размонтировании**:
- Файловая система осталась в "грязном" состоянии
- При попытке монтирования ядро выдавало I/O error как защитную меру
- После проверки через `dd` (который перемонтировал карту) — всё работает

### Как проверить состояние файловой системы:
```bash
# Проверить флаг "clean" в ext4 superblock:
sudo tune2fs -l /dev/sdX2 | grep "Filesystem state"
# clean         ✅ Всё OK
# not clean     ⚠️ Было неправильное размонтирование

# Полная проверка:
sudo fsck -n /dev/sdX2  # только проверка, не исправлять
```

### Правило на будущее:
```
ПЕРЕД извлечением microSD:
1. sync                      # Сбросить кэш на диск
2. sudo systemctl poweroff   # Правильное выключение
3. НЕ извлекать пока мигает LED активности

ПРИ I/O errors на карте:
1. Проверить состояние ФС: tune2fs -l | grep "Filesystem state"
2. Если "not clean" → sudo fsck -y /dev/sdX
3. Если есть bad blocks → карта под замену
```

### Документация:
Подробнее: [→ Filesystem Health Check](filesystem-health-check.md)

---

## 2026-03-06: motya НЕ загрузился после миграции — playbook пропустил Ubuntu

### Контекст:
- **Хост:** motya (Raspberry Pi 4, Ubuntu)
- **Действия:** Запущен `ssd-migrate.yml` для миграции на SSD
- **Результат:** После перезагрузки — Connection refused

### Диагностика:
**Playbook `update_cmdline.yml` пропустил обновление для Ubuntu:**
```yaml
# Строка 8-14 — ОШИБКА!
- name: Skip cmdline update for Ubuntu (uses LABEL auto-detection)
  msg: "Ubuntu использует LABEL auto-detection. Изменение не требуется."
```

**Почему это НЕПРАВДА:**
1. Ubuntu на Raspberry Pi использует **initramfs** для монтирования rootfs
2. initramfs ищет `root=` параметр в cmdline.txt
3. Если `root=` не указан → initramfs использует первый найденный LABEL=writable
4. **microSD имеет LABEL=writable, SSD тоже имеет LABEL=writable**
5. initramfs находит **microSD первым** → загрузка с microSD!

### Дополнительные проблемы:
1. **PARTUUID mismatch:**
   - cmdline.txt содержал старый PARTUUID (до форматирования SSD)
   - SSD был переформатирован → PARTUUID изменился
   - Playbook не получал актуальный PARTUUID!

2. **LABEL конфликт:**
   - microSD: LABEL=writable
   - SSD: LABEL=writable
   - initramfs выбрал microSD

### Решение:
**1. Исправлен playbook `update_cmdline.yml`:**
- Удалён пропуск Ubuntu — ВСЕГДА обновляем cmdline.txt
- Получаем PARTUUID SSD динамически через `blkid`
- Изменяем LABEL на microSD на `writable-sd`
- Обновляем ОБА cmdline.txt файла (Ubuntu tryboot)
- Добавлены CRITICAL assert проверки

**2. Добавлена проверка в `verify.yml`:**
- Проверка cmdline.txt содержит root=PARTUUID=SSD
- Проверка current/cmdline.txt содержит root=PARTUUID=SSD

### Правило на будущее:
```
ПРИ ИСПРАВЛЕНИИ PLAYBOOK'А — НЕ ПРОПУСКАТЬ критические шаги!

Никаких "Ubuntu auto-detection" — ВСЕГДА явная конфигурация:

1. Получить PARTUUID SSD (blkid)
2. Проверить что cmdline.txt содержит root=PARTUUID=SSD
3. Проверить что current/cmdline.txt содержит root=PARTUUID=SSD
4. Изменить LABEL на microSD на writable-sd
5. НЕ перезагружаться пока verify не пройден!
```

### Почему нужно всегда проверять:
- Playbook может завершиться с "ok=2 changed=0" но ничего не сделать!
- Assert проверки ОСТАНАВЛИВАЮТ выполнение если что-то не так
- Без проверки → перезагрузка → система не грузится

---

## 2026-03-06: motya НЕ загрузился — поэтапная проверка файлов

### Контекст:
- **Проблема:** После исправления cmdline.txt → перезагрузка → виснет на fsck
- **Исправление:** Исправил fstab на microSD → снова проверяю cmdline.txt
- **Результат:** Пользователь спросил: "ты проверил ВСЕ файлы или будем перегружаться бесконечно?"

### Диагностика:
**Я проверял файлы ПО ОДНОМУ за раз:**
1. Шаг 1: Исправил cmdline.txt → забыл про fstab
2. Шаг 2: Исправил fstab → не проверил cmdline.txt ещё раз
3. Шаг 3: Проверял снова, но уже не был уверен что всё исправлено

**Проблема в подходе:**
- Файлы взаимосвязаны — изменение одного влияет на другие
- Проверка по одному файлу = бесконечный цикл "поправил → перезагрузил → FAIL"
- Каждая перезагрузка = 5+ минут потерянного времени

### Какие файлы взаимосвязаны при SSD миграции:

| Файл | Если неправильно | Последствие |
|------|------------------|-------------|
| cmdline.txt (microSD) | `root=LABEL=writable` | Загрузится с microSD |
| current/cmdline.txt (microSD) | Не обновлён | Tryboot откатит изменения |
| fstab (SSD) | Неправильный PARTUUID | Rootfs не смонтируется |
| LABEL (microSD) | `writable` | Конфликт с SSD |
| LABEL (SSD) | Не `writable` | Initramfs не найдёт |
| PARTUUID | Не совпадает | Загрузится со старого диска |
| hostname (SSD) | Чужой hostname | Сетевой конфликт |
| machine-id (SSD) | Пустой/чужой | Systemd не работает |

### Решение:
**Добавлена проверка ВСЕХ файлов ОДНОВРЕМЕННО:**

```bash
# Единая команда проверки всех критичных файлов:
echo "=== 1. cmdline.txt ===" && cat /boot/firmware/cmdline.txt && \
echo "" && echo "=== 2. current/cmdline.txt ===" && cat /boot/firmware/current/cmdline.txt && \
echo "" && echo "=== 3. fstab (SSD) ===" && cat /mnt/ssd/etc/fstab && \
echo "" && echo "=== 4. LABELS ===" && blkid | grep -E '(mmcblk0p2|sda2)' && \
echo "" && echo "=== 5. PARTUUID match ===" && \
echo "cmdline: $(grep -o 'root=PARTUUID=[^ ]*' /boot/firmware/cmdline.txt)" && \
echo "SSD:     $(sudo blkid -s PARTUUID -o value /dev/sda2)" && \
echo "" && echo "=== 6. hostname ===" && cat /mnt/ssd/etc/hostname && \
echo "" && echo "=== 7. machine-id ===" && cat /mnt/ssd/etc/machine-id
```

### Правило на будущее:
```
ПРИ ИЗМЕНЕНИИ КОНФИГУРАЦИИ ЗАГРУЗКИ:

❌ НЕПРАВИЛЬНЫЙ ПОДХОД (поэтапный):
1. Исправить cmdline.txt
2. Перезагрузиться
3. FAIL
4. Исправить fstab
5. Перезагрузиться
6. FAIL
7. Исправить LABEL
8. ... (бесконечно)

✅ ПРАВИЛЬНЫЙ ПОДХОД (согласованный):
1. ПРОВЕРИТЬ ВСЕ 7 файлов одновременно
2. Исправить ВСЕ файлы одновременно
3. ПРОВЕРИТЬ ВСЕ 7 файлов одновременно
4. ТОЛЬКО ПОТОМ перезагрузка

5+ минут на каждую перезагрузку × 5 раз = 25+ минут потерянного времени!
```

### Документация:
- [→ Filesystem Health Check](filesystem-health-check.md) — раздел "СОГЛАСОВАННОЕ изменение"
- [→ SSD Migration Checklist](ssd-migration-checklist.md) — единая команда проверки

---

## 2026-03-06: motya бесконечная перезагрузка — panic=10, hostname, k3s

### Контекст:
- **Проблема:** После исправления cmdline.txt, fstab, LABEL — motya бесконечно перезагружается
- **Причина:** Несколько НЕОЧЕВИДНЫХ проблем вызывающих перезагрузку

### Диагностика:

**1. panic=10**
- При любой kernel panic → перезагрузка через 10 секунд
- Нельзя увидеть сообщение об ошибке!
- Бесконечный цикл: ошибка → panic → перезагрузка → ошибка ...

**2. hostname=sema на motya**
- SSD был скопирован с sema
- hostname=sema создаёт сетевой конфликт
- k3s сервис пытается запуститься с чужим конфигом → крах → перезагрузка

**3. k3s сервисы от sema**
- `/etc/rancher/k3s/k3s.yaml` настроен для sema
- `k3s.service` запускается → неправильный конфиг → крах → перезагрузка

### ПРИМЕЧАНИЕ: console=serial0

**console=serial0,115200 НЕ является проблемой** на Raspberry Pi 4:
- motya (RPi 4) работает с console=serial0,115200 ✅
- osya (RPi 4) работает с console=serial0,115200 ✅
- Стандартная Ubuntu конфигурация включает оба консольных вывода

### Решение:

**1. Изменить panic на -1 (для отладки):**
```bash
# БЫЛО:
panic=10  # Перезагрузка через 10 сек
# СТАЛО:
panic=-1  # Остановиться при ошибке (показать diagnostic)
# ИЛИ убрать panic параметр вообще
```

**2. Исправить hostname и machine-id:**
```bash
echo "motya" > /mnt/ssd/etc/hostname
uuidgen | tr -d '-' > /mnt/ssd/etc/machine-id
```

**3. Удалить k3s от другого хоста:**
```bash
rm -rf /mnt/ssd/etc/rancher/k3s/*
rm -f /mnt/ssd/etc/systemd/system/k3s.service
rm -f /mnt/ssd/etc/systemd/system/multi-user.target.wants/k3s.service
```

### Правило на будущее:

```
ПРИ ПЕРЕВОЙ ЗАГРУЗКЕ ПОСЛЕ МИГРАЦИИ — проверить параметры ПЕРЕЗАГРУЗКИ:

1. ❌ НЕ panic=10           → использовать panic=-1 или убрать для отладки
2. ❌ НЕ чужой hostname     → проверить /etc/hostname
3. ❌ НЕ чужой machine-id   → проверить /etc/machine-id
4. ❌ НЕ чужие сервисы     → проверить k3s, docker
5. ✅ console=serial0      → работает нормально, НЕ трогать
```

### Почему эти проблемы НЕ были найдены раньше:

Они не связаны с миграцией SSD напрямую:
- `panic=10` — "безопасное" значение для production
- hostname/machine-id/k3s — проблема копирования SSD с другого хоста

Но при миграции на **другой** хост они становятся критичными!

### Единая команда проверки:

```bash
# Выполнить ПЕРЕД первой загрузкой:
echo "Panic: $(grep -o 'panic=[^ ]*' /boot/firmware/cmdline.txt || echo 'no panic - OK')" && \
echo "Hostname: $(cat /mnt/ssd/etc/hostname)" && \
echo "Machine-id: $(cat /mnt/ssd/etc/machine-id)" && \
echo "k3s files: $(find /mnt/ssd/etc/systemd -name '*k3s*' 2>/dev/null | wc -l)"
```

### Документация:
- [→ Filesystem Health Check](filesystem-health-check.md) — раздел "Проверки параметров ПЕРЕЗАГРУЗКИ"
- [→ SSD Migration Checklist](ssd-migration-checklist.md) — проверки #7-9

---

## 2026-03-06: motya бесконечная перезагрузка — ДВОЙНАЯ КОНФИГУРАЦИЯ (УСТАРЕЛО)

### ПРИМЕЧАНИЕ: Этот раздел УСТАРЕЛ

**Первоначальная диагностика была НЕВЕРНОЙ.**

**Что думалось:**
- Boot раздел есть на ОБАИХ носителях (microSD и SSD)
- cmdline.txt нужно обновлять на ОБАИХ носителях

**На самом деле (проверено на motya и osya):**
- **Boot раздел ТОЛЬКО на microSD** (`/dev/mmcblk0p1` → `/boot/firmware`)
- **cmdline.txt ТОЛЬКО на microSD**
- На SSD НЕТ boot раздела и cmdline.txt

### Правильная архитектура Ubuntu на Raspberry Pi:

| Раздел | microSD | SSD | Назначение |
|--------|---------|-----|------------|
| Boot partition | ✅ Есть | ❌ Нет | cmdline.txt, config.txt, ядро |
| Rootfs | Есть (старый) | ✅ Основной | Файловая система |

### Правило на будущее:

```
ПРИ МИГРАЦИИ НА SSD:

1. ✅ cmdline.txt обновляется ТОЛЬКО на microSD (boot раздел)
2. ✅ fstab обновляется на SSD (rootfs)
3. ✅ Boot partition ВСЕГДА остаётся на microSD
4. ✅ Rootfs переносится на SSD

❌ НЕ ИЩИТЕ cmdline.txt на SSD - его там нет!
```

### Что на самом деле вызывало перезагрузку:

Проблема была в **ДРУГИХ параметрах**:
- panic=10 → перезагрузка при любой ошибке
- hostname=sema → k3s конфликт
- k3s от другого хоста → неправильный конфиг

Смотри раздел "motya бесконечная перезагрузка — panic=10, hostname, k3s"

---
