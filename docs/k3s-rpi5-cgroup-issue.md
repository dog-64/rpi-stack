# K3s на Raspberry Pi 5: Проблема cgroup_disable=memory

**Дата**: 2026-02-15
**Хост**: leha (10.0.1.104), sema (10.0.1.33)
**ОС**: Raspberry Pi OS (generated using pi-gen, 2025-10-01)
**Ядро**: 6.12.62+rpt-rpi-2712

## Проблема

K3s не запускается на Raspberry Pi 5 с ошибкой:
```
time="2026-02-15T13:32:03Z" level=fatal msg="Error: failed to find memory cgroup (v2)"
```

### Симптомы

```bash
# memory cgroup недоступен
$ cat /proc/cgroups
# (нет строки с memory)

# Параметр отключения в cmdline
$ cat /proc/cmdline | grep cgroup
cgroup_disable=memory

# cgroup v2 без memory controller
$ mount | grep cgroup
cgroup2 on /sys/fs/cgroup type cgroup2 (rw,nosuid,nodev,noexec,relatime,nsdelegate,memory_recursiveprot)
```

## Почему это происходит

### Источник проблемы: два слоя

Проблема состоит из **двух независимых слоёв**, оба должны быть решены:

**Слой 1: Device Tree Binary (DTB)**
Параметр `cgroup_disable=memory` прописан в файле `/boot/firmware/bcm2712-rpi-5-b.dtb` (Device Tree Binary) в секции bootargs. DTB загружается firmware **до** чтения `cmdline.txt`. Это объясняет, почему `/proc/cmdline` показывает совершенно другое содержимое, чем `cmdline.txt` — firmware подставляет bootargs из DTB, а не из cmdline.txt.

**Слой 2: Ядро 6.12+ отключило cgroup v1 memory**
В ядре 6.12 Raspberry Pi отключена опция `CONFIG_MEMCG_V1` (cgroup v1 memory controller). Это означает, что параметры `systemd.unified_cgroup_hierarchy=0` и `cgroup_memory=1` **бесполезны** — они относятся к cgroup v1, который больше не поддерживается ядром. Работать будет **только** cgroup v2 с параметром `cgroup_enable=memory`.

### Почему попытки через cmdline.txt не работают

Содержимое `/proc/cmdline` полностью расходится с содержимым `cmdline.txt`:

```
cmdline.txt:    console=serial0,115200 console=tty1 root=PARTUUID=... cgroup_enable=memory
/proc/cmdline:  reboot=w coherent_pool=1M 8250.nr_uarts=1 ... cgroup_disable=memory
```

Это значит одно из двух:
1. Firmware не читает `cmdline.txt` вообще (проблема конфигурации `config.txt`)
2. DTB bootargs полностью перезаписывают cmdline.txt (а не дополняют)

### Почему проблема не "всеобщая"

Большинство успешных установок K3s на Raspberry Pi используют:

1. **Raspberry Pi 4** — где нет этой оптимизации
2. **Ubuntu Server** на RPi5 — где другая конфигурация firmware
3. **Более старые образы Raspberry Pi OS** — до добавления этой "оптимизации"
4. **Вручную собранные системы** — где firmware настроен иначе

### Текущая конфигурация

```bash
# ОС
PRETTY_NAME="Debian GNU/Linux 13 (trixie)"
Raspberry Pi reference 2025-10-01
Generated using pi-gen

# Пакеты
raspberrypi-sys-mods    1:20251028+1
raspi-firmware          1:1.20250915-1
raspi-utils             20251120-1

# cmdline.txt (наши изменения)
console=serial0,115200 console=tty1 root=PARTUUID=...
  systemd.unified_cgroup_hierarchy=0 cgroup_memory=1 cgroup_enable=memory

# Но /proc/cmdline показывает
reboot=w coherent_pool=1M 8250.nr_uarts=1 pci=pcie_bus_safe
  cgroup_disable=memory numa_policy=interleave ...
```

**Ключевой момент**: изменения в `cmdline.txt` игнорируются, firmware подставляет `cgroup_disable=memory`.

## Что было попробовано

### 1. Параметры в cmdline.txt

```bash
# Попытка 1: cgroup v1 parameters
systemd.unified_cgroup_hierarchy=0 cgroup_memory=1 cgroup_enable=memory
# Результат: Не работает. Причина: cgroup v1 memory ОТКЛЮЧЁН в ядре 6.12 (CONFIG_MEMCG_V1 is not set).
# Параметры cgroup_memory=1 и systemd.unified_cgroup_hierarchy=0 — бесполезны.

# Попытка 2: config.txt
cmdline=cgroup_enable=memory cgroup_memory=1
# Результат: Игнорируется firmware

# Попытка 3: Обновление ядра
apt upgrade (установлены модули для 6.12.62+rpt-rpi-2712)
# Результат: Модули доступны, но cgroup всё равно отключён
```

**Анализ попыток**: Все три попытки обречены на провал, потому что:
- cmdline.txt не читается firmware (или перезаписывается DTB bootargs)
- Использовались параметры cgroup v1, а ядро 6.12 поддерживает только cgroup v2
- Правильный параметр — только `cgroup_enable=memory` (без `cgroup_memory=1`)

### 2. Обновление системы

```bash
# После apt upgrade появились модули для текущего ядра
/lib/modules/6.12.62+rpt-rpi-2712/kernel/fs/overlayfs/overlay.ko.xz
/lib/modules/6.12.62+rpt-rpi-2712/kernel/net/bridge/br_netfilter.ko.xz

# Но memory cgroup не появился
cat /proc/cgroups | grep memory
# (пусто)
```

### 3. Перезагрузки

Несколько перезагрузок с разными параметрами — результат одинаковый.

## Исследовательские ресурсы

### Ключевые источники (с подтверждёнными решениями)

1. [raspberrypi/linux#6980](https://github.com/raspberrypi/linux/issues/6980) — **Самый важный**
   — Подтверждает: DTB содержит `cgroup_disable=memory`; `cgroup_enable=memory` в cmdline.txt должен переопределять DTB; `cgroup_memory=1` — нераспознанный параметр, генерирует warnings

2. [raspberrypi/linux#5933](https://github.com/raspberrypi/linux/issues/5933)
   — Fails to Enable Memory cgroup despite correct kernel parameters (подтверждает что изменения cmdline.txt "на лету" не работают)

3. [Raspberry Pi Forums - Cgroups memory on RPI5 & Bookworm](https://forums.raspberrypi.com/viewtopic.php?t=389843)
   — Июль 2025: подтверждает CONFIG_MEMCG_V1 отключён в ядре 6.12, нужен cgroup v2

### Форумы и обсуждения

4. [Raspberry Pi Forums - Memory cgroup configuration issue](https://forums.raspberrypi.com/viewtopic.php?t=365198)
   — SOLVED discussion (февраль 2024)

5. [pxvirt#213](https://github.com/jiangcuo/pxvirt/issues/213)
   — cgroup_disable=memory is forced on RPi5, breaking K3s and container RAM stats

### K3s Issues

6. [K3s Issue #9524](https://github.com/k3s-io/k3s/issues/9524)
   — Raspberry Pi OS Bookworm fails to enable memory cgroup (февраль 2024)

7. [K3s Issue #10755](https://github.com/k3s-io/k3s/issues/10755)
   — k3s.service fails due to memory cgroup v2 issue (август 2024)

### Руководства

8. [Installing K3s on Raspberry Pi 5 - Step-by-step guide](https://www.picocluster.com/blogs/picocluster-software-engineering/installing-k3s-on-the-raspberry-pi5-a-step-by-step-guide)
   — Практическое руководство с настройкой cgroup

9. [Kubernetes on Raspberry Pi 5 — Part 3](https://ionutbanu.medium.com/kubernetes-on-raspberry-pi-5-part-3-install-k3s-on-master-node-f95ea35a8b1c)
   — Medium статья (июнь 2024)

10. [Deploy Korifi on K3s with Ubuntu Raspberry Pi 5](https://dashaun.com/posts/korifi-on-raspberry-pi/)
    — Ubuntu-specific solution (январь 2025)

## Варианты решений

### Решение 1: Патч Device Tree Binary (DTB) — РЕКОМЕНДУЕТСЯ

Удалить `cgroup_disable=memory` прямо из DTB файла. Это устраняет корень проблемы.

**Применять на**: всех узлах кластера (и server, и agent — kubelet работает на каждом узле).

```bash
# 1. Установить компилятор Device Tree
sudo apt install device-tree-compiler

# 2. Декомпилировать DTB в текстовый формат
sudo cp /boot/firmware/bcm2712-rpi-5-b.dtb /boot/firmware/bcm2712-rpi-5-b.dtb.backup
sudo dtc -I dtb -O dts -o /tmp/rpi5.dts /boot/firmware/bcm2712-rpi-5-b.dtb

# 3. Найти cgroup_disable в bootargs
grep -n "cgroup_disable" /tmp/rpi5.dts

# 4. Отредактировать — удалить cgroup_disable=memory из строки bootargs
sudo nano /tmp/rpi5.dts

# 5. Перекомпилировать обратно в бинарный формат
sudo dtc -I dts -O dtb -o /boot/firmware/bcm2712-rpi-5-b.dtb /tmp/rpi5.dts

# 6. Перезагрузить
sudo reboot
```

**Верификация после перезагрузки:**
```bash
# Должно содержать "memory"
cat /sys/fs/cgroup/cgroup.controllers

# НЕ должно содержать cgroup_disable=memory
cat /proc/cmdline | grep cgroup

# Если всё ок — K3s должен запуститься
```

**Риски**: Минимальные при наличии backup. Если DTB повреждён — Pi не загрузится, но можно восстановить backup с другого компьютера через SD-карту.

**Важно**: После обновления `raspi-firmware` через apt DTB может быть перезаписан, и патч потребуется повторить.

### Решение 2: Диагностика и исправление cmdline.txt

Сначала выяснить **почему cmdline.txt не читается**, затем исправить его содержимое.

**Шаг 1: Диагностика**
```bash
# Проверить путь к файлу
ls -la /boot/firmware/cmdline.txt

# Проверить что файл — ОДНА строка (критично!)
wc -l /boot/firmware/cmdline.txt   # Должно быть 1

# Проверить нет ли переопределения в config.txt
grep -i cmdline /boot/firmware/config.txt

# Проверить что boot partition смонтирован
mount | grep /boot
```

**Шаг 2: Исправить содержимое cmdline.txt**

Использовать **только** параметры cgroup v2 (v1 отключён в ядре 6.12):
```bash
# ПРАВИЛЬНО (cgroup v2):
cgroup_enable=memory

# НЕПРАВИЛЬНО (cgroup v1, не работает на ядре 6.12):
# systemd.unified_cgroup_hierarchy=0   ← бесполезен
# cgroup_memory=1                      ← нераспознанный параметр, вызывает warnings
```

Согласно [raspberrypi/linux#6980](https://github.com/raspberrypi/linux/issues/6980), параметры cmdline.txt должны применяться **после** DTB и переопределять `cgroup_disable=memory`. Если это не происходит — нужен патч DTB (Решение 1).

### Решение 3: Переключиться на Ubuntu Server

Ubuntu Server на Raspberry Pi 5 не имеет этой проблемы — стандартная Linux конфигурация firmware без `cgroup_disable=memory` в DTB.

```bash
# Скачать Ubuntu Server 24.04 LTS for Raspberry Pi 5
# Установить заново
```

**Преимущества**: Работает из коробки, широкое сообщество, хорошо поддерживается для K3s.
**Недостатки**: Требует полной переустановки ОС, потеря текущей конфигурации.

### Решение 4: Использовать Raspberry Pi 4 (motya, osya)

Raspberry Pi 4 не имеет этой "оптимизации" в DTB. Проверить:

```bash
ssh dog@10.0.1.75 "cat /proc/cmdline | grep cgroup"
ssh dog@10.0.1.75 "cat /sys/fs/cgroup/cgroup.controllers"
```

Если memory cgroup работает на Pi 4 — можно начать кластер на них, а Pi 5 добавить после решения проблемы.

### Решение 5: Ждать обновления firmware

Raspberry Pi Foundation может исправить это в будущих обновлениях raspi-firmware. Проблема задокументирована в нескольких issues.

### Решение 6: Альтернативы K3s (крайний случай)

- **k3d** (K3s in Docker) — требует Docker, дополнительный overhead
- **microk8s** — от Canonical, может работать без memory cgroup? Нет, тоже требует
- **kind** (Kubernetes in Docker) — требует Docker

**Примечание**: Любой Kubernetes-дистрибутив требует memory cgroup. Альтернативные дистрибутивы не решают эту проблему.

### ~EEPROM bootloader config~ (Не поможет)

~~Изменить конфигурацию EEPROM bootloader'а.~~

**Анализ**: `cgroup_disable=memory` находится **не в EEPROM**, а в Device Tree Binary (DTB). EEPROM хранит конфигурацию загрузчика (BOOT_ORDER, HDMI, и т.д.), а не параметры ядра. Редактирование EEPROM не решит проблему.

### ~Патчить cmdline через initramfs~ (Не поможет)

~~Создать кастомный initramfs который patch'ит cmdline на ранней стадии.~~

**Анализ**: К моменту загрузки initramfs параметры ядра уже обработаны. Изменение `/proc/cmdline` из initramfs невозможно — параметры ядра read-only после парсинга.

## Текущий статус

| Хост | Модель | OS | cgroup memory | Статус |
|------|--------|-----|---------------|--------|
| leha | Pi 5 | Raspberry Pi OS (2025-10-01) | ❌ Отключён | Блокирован |
| sema | Pi 5 | Raspberry Pi OS (2025-10-01) | ❌ Отключён | Блокирован |
| motya | Pi 4 | ? | 🔍 Не проверен | Недоступен по сети |
| osya | Pi 4 | Raspberry Pi OS | 🔍 Не проверен | Доступен |

## Рекомендуемые действия

1. **Проверить osya (Raspberry Pi 4)** — возможно там нет этой проблемы
2. **Если на Pi 4 тоже есть проблема** — переключиться на Ubuntu Server
3. **Если на Pi 4 проблемы нет** — использовать Pi 4 как K3s server

## Дополнительная информация

### Почему memory cgroup нужен K3s

Memory cgroup нужен **kubelet**, который работает на **каждом узле** (и server, и agent). Без него невозможно:
- Ограничивать потребление RAM подами (resource limits/requests)
- Обрабатывать OOM (out of memory) на уровне подов
- Планировать поды (scheduling decisions based на доступной памяти)
- Обеспечивать Quality of Service для памяти
- Собирать метрики потребления RAM

K3s откажется запускаться на **любом** хосте без memory cgroup — неважно, server или agent.

### cgroup v1 vs v2 на ядре 6.12

| Характеристика | cgroup v1 | cgroup v2 |
|----------------|-----------|-----------|
| CONFIG_MEMCG_V1 | **Отключён** в ядре 6.12 RPi | N/A |
| Параметры cmdline | `cgroup_memory=1` (не работает) | `cgroup_enable=memory` |
| systemd hierarchy | `unified_cgroup_hierarchy=0` (не работает) | Используется по умолчанию |
| Проверка | `cat /proc/cgroups` | `cat /sys/fs/cgroup/cgroup.controllers` |
| Поддержка K3s | Да (старые версии) | Да (все актуальные версии) |

### Raspberry Pi OS vs Ubuntu на RPi5

| Характеристика | Raspberry Pi OS | Ubuntu Server |
|----------------|-----------------|---------------|
| DTB bootargs | `cgroup_disable=memory` включён | Стандартные Linux |
| Firmware оптимизации | Активные | Минимальные |
| Поддержка K3s | Требует патча DTB | Работает из коробки |
| Производительность | Оптимизирована для Pi | Стандартная |
| Сообщество | RPi специфичное | Широкое Linux сообщество |

### Порядок загрузки параметров ядра на RPi5

```
1. EEPROM bootloader
   └── Загружает firmware, config.txt
        └── Читает DTB (bcm2712-rpi-5-b.dtb)
             └── bootargs: "... cgroup_disable=memory ..."    ← ПРОБЛЕМА
                  └── Читает cmdline.txt
                       └── cgroup_enable=memory               ← ДОЛЖЕН переопределить
                            └── Ядро парсит финальный cmdline
                                 └── /proc/cmdline
```

Согласно документации, cmdline.txt должен переопределять DTB bootargs. Если это не происходит — нужен прямой патч DTB.

## Рекомендуемый порядок действий

1. **Быстрая проверка (5 мин)**: Проверить osya (Pi 4) — есть ли проблема
2. **Патч DTB на leha (15 мин)**: Решение 1 — удалить `cgroup_disable=memory` из DTB
3. **Если DTB не помогло**: Диагностировать cmdline.txt (Решение 2) — почему не читается
4. **Если ничего не помогло**: Ubuntu Server (Решение 3)
5. **Патч применить на ВСЕХ узлах** — и server, и agent

## Обновления

Буду обновлять этот документ по мере появления новой информации.

---

**Created**: 2026-02-15
**Last Updated**: 2026-02-15
**Status**: 🔍 Investigating — рекомендуется патч DTB (Решение 1)
