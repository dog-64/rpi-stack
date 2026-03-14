# Ansible для Raspberry Pi кластера

## Ограничения и особенности

> **Важно:** Работа с Kubernetes кластером на Raspberry Pi ведётся исключительно под **Ubuntu 25.10**.
>
> Это связано с тем, что официальная поддержка Kubernetes в Raspberry Pi OS ограничена, а Ubuntu 25.10 предоставляет актуальные версии контейнерного раннера (containerd) и других компонентов, необходимых для полноценной работы K8s на архитектуре ARM64.
>
> Если вы планируете использовать K8s на Raspberry Pi — устанавливайте Ubuntu 25.10.

## Структура кластера

### Активные хосты

| Имя   | IP         | Hostname | Модель         | Память |
|-------|------------|----------|----------------|--------|
| leha  | 10.0.1.104 | p104     | Raspberry Pi 5 | 8GB    |
| sema  | 10.0.1.33  | p33      | Raspberry Pi 5 | 8GB    |
| motya | 10.0.1.56  | p56      | Raspberry Pi 4 | 8GB    |
| osya  | 10.0.1.75  | p75      | Raspberry Pi 4 | 8GB    |

### Неактивные хосты

| Имя  | Модель         | Память | Статус                                |
|------|----------------|--------|---------------------------------------|
| vitl | Raspberry Pi 4 | 4GB    | Ожидает корпус, нет порта на eth хабе |

## Группы хостов

- `active` - все активные хосты в сети
- `inactive` - хосты, которые пока не подключены
- `pi5` - Raspberry Pi 5 (leha, sema)
- `pi4_8gb` - Raspberry Pi 4 с 8GB (motya, osya)
- `pi4_4gb` - Raspberry Pi 4 с 4GB (vitl)
- `high_memory` - хосты с 8GB памяти
- `low_memory` - хосты с 4GB памяти
- `k3s_server` - control-plane нода (sema)
- `k3s_agent` - worker ноды (leha, motya, osya)
- `k3s_cluster` - все ноды k3s

## Быстрый старт

### Установка

- записываем образ на Raspberry Pi Imager - Ubuntu 25.10 Server

- запускаем скрипт фикса сети - видимо это актуально только для Raspberry Pie 5
```shell
  sudo ./scripts/fix-sd-network.sh /dev/disk11
```

- загружаемся с micro SD
- при необходимости мигрируем на SSD (см. [Migration manual](#миграция-с-microsd-на-ssd))

**Для подготовки к K3s:**
```bash
# Обновляем систему
ansible-playbook playbooks/update-all.yml --limit <HOST>

# Фикс локали
ansible-playbook playbooks/fix-locale.yml --limit <HOST>

# Проверяем информацию о системе
ansible-playbook playbooks/system-info.yml --limit <HOST>
```

## Миграция с microSD на SSD

Для улучшения производительности и долговечности системы рекомендуется перенести корневую файловую систему с microSD на SSD.

### ⚠️ Проверка SSD перед миграцией

**ПЕРЕД началом миграции** обязательно прочитай:
[→ Lessons Learned (ошибки и решения)](docs/lessons-learned.md) — **что НЕ надо делать**
[→ SSD Pre-check Guide](docs/ssd-precheck.md) — проверка SSD
[→ USB Adapters Tested](docs/usb-adapters-tested.md) — какие адаптеры работают

### Миграция вручную

Подробное руководство с пошаговой инструкцией:
[→ Migration manual](docs/ssd-migration-manual.md)

### Миграция с Ansible Playbook

**Playbooks:**
- `playbooks/ssd-migrate.yml` - основная миграция на SSD
- `playbooks/verify-ssd.yml` - проверка предпосылок и верификация

**Ключевые параметры:**
```bash
# Проверить подключен ли SSD (предварительно)
ansible-playbook playbooks/verify-ssd.yml -i inventory.yml --limit <HOST>

# Запустить миграцию с указанием устройства
ansible-playbook playbooks/ssd-migrate.yml -i inventory.yml \
  --limit <HOST> \
  -e ssd_device=sda \
  -e ssd_partition=auto

# Запуск с подтверждением (для безопасности)
ansible-playbook playbooks/ssd-migrate.yml -i inventory.yml \
  --limit <HOST> \
  -e ssd_skip_confirmation=false

# Автоматическая перезагрузка после миграции
ansible-playbook playbooks/ssd-migrate.yml -i inventory.yml \
  --limit <HOST> \
  -e ssd_reboot_after_config=true
```

**Примеры использования:**
```bash
# Миграция хоста leha с автоопределением SSD
ansible-playbook playbooks/ssd-migrate.yml -i inventory.yml --limit leha

# Миграция всех Pi 5 с SSD = sdb
ansible-playbook playbooks/ssd-migrate.yml -i inventory.yml --limit pi5 \
  -e ssd_device=sdb

# Проверка статуса после миграции
ansible-playbook playbooks/verify-ssd.yml -i inventory.yml --limit leha
```

**Дополнительные опции:**
- `ssd_mount_point` - точка монтирования SSD (по умолчанию `/mnt/ssd`)
- `ssd_min_free_space_ratio` - минимальный коэффициент свободного места (1.1 по умолчанию)
- `ssd_reboot_delay` - задержка перед перезагрузкой (5 секунд по умолчанию)

> **Важно:** Playbook использует ту же логику что и ручной метод:
> - Boot раздел остается на microSD (`PARTUUID=6d3d7424-01`)
> - Rootfs переносится на SSD с использованием `PARTUUID`
> - Автоматический откат через изменение LABEL на microSD

### Проверка статуса

```bash
# Проверить какой диск используется как корень
ansible active -a "df /"

# Проверить PARTUUID всех разделов
ansible active -a "sudo blkid -o list"

# Проверить метки (LABEL) дисков
ansible active -a "sudo blkid | grep LABEL"

# Вручную проверить на хосте
ssh <HOST> "lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,PARTUUID,MOUNTPOINT"
```

### Откат

При необходимости вернуться на microSD:
```bash
# Изменить LABEL microSD обратно на "writable"
ansible active -e ssd_device=/dev/mmcblk0p2 -a "sudo tune2fs -L writable /dev/mmcblk0p2"

# Перезагрузка (systemd автоматически выберет microSD)
ansible active -b -m reboot
```

---
[Структура кластера](#структура-кластера)

### Установка k3s (Kubernetes)

**Архитектура кластера:**
- `k3s_server` (control-plane) — нода управления (sema)
- `k3s_agent` (workers) — рабочие ноды (leha, motya, osya)

**Установка control-plane (server):**
```bash
# Установка на серверную ноду
ansible-playbook playbooks/k3s-install.yml --limit k3s_server

# Или через Makefile
make k3s-server
```

**Установка worker-нод (agents):**
```bash
# Установка на все agent-ноды
ansible-playbook playbooks/k3s-install.yml --limit k3s_agent

# Установка на хост motya
ansible-playbook playbooks/k3s-install.yml --limit motya                                            

# Или через Makefile
make k3s-agents
```

**Установка всего кластера одной командой:**
```bash
ansible-playbook playbooks/k3s-install.yml --limit k3s_cluster
# Или
make k3s-install
```

**Проверка статуса кластера:**
```bash
# Статус нод
make k3s-status

# Поды в кластере
make k3s-pods

# Получить токен для добавления новых нод
make k3s-token

# Kubeconfig для удалённого доступа
make k3s-kubeconfig
```

**Удаление k3s:**
```bash
# Удалить со всех хостов
make k3s-uninstall

# Удалить только server
make k3s-uninstall-server

# Удалить только agents
make k3s-uninstall-agents
```

**Подробнее:** [docs/k3s-install-manual.md](docs/k3s-install-manual.md)

### Устранение неполадок k3s

**Важные проблемы и решения:**

- **Проблема: Узел в состоянии NotReady** → [Time Synchronization Problem](docs/k3s-node-time-sync-problem.md) — синхронизация времени перед установкой k3s

### Все известные проблемы

Полный список всех известных проблем и их решений:
[→ Known Issues Index](docs/known-issues-index.md)

### Проверка подключения

```bash
# Ping всех активных хостов
ansible active -m ping

# Ping конкретного хоста
ansible leha -m ping

# Ping группы Pi 5
ansible pi5 -m ping
```

### Запуск playbook

```bash
# Проверка подключения с информацией о системе
ansible-playbook ping.yml

# Запуск только для Pi 5
ansible-playbook ping.yml --limit pi5

# Запуск для конкретного хоста
ansible-playbook ping.yml --limit leha
```

### Полезные команды

```bash
# Список всех хостов
ansible-inventory --list

# График групп и хостов
ansible-inventory --graph

# Выполнение команды на всех хостах
ansible active -a "uname -a"

# Проверка uptime
ansible active -a "uptime"

# Проверка свободной памяти
ansible active -a "free -h"

# Проверка места на диске
ansible active -a "df -h"

# Обновление системы (требует sudo)
ansible active -b -m apt -a "update_cache=yes upgrade=dist"
```

## Примеры использования групп

```bash
# Только Pi 5
ansible pi5 -a "vcgencmd measure_temp"

# Только хосты с 8GB
ansible high_memory -a "free -h"

# Исключить определенный хост
ansible active -a "hostname" --limit '!leha'
```

## Идеи для роли vitl (4GB)

- **DNS/DHCP сервер** - Pi-hole или dnsmasq
- **Monitoring** - Prometheus node exporter, collectd
- **Backup сервер** - легкий rsync/borg backup
- **VPN gateway** - WireGuard или OpenVPN
- **Git сервер** - Gitea (легковесный)
- **Контроллер умного дома** - Home Assistant
- **Print server** - CUPS
- **Time server** - NTP сервер для кластера
- **Syslog сервер** - централизованный сбор логов

## Следующие шаги

1. Настройте SSH ключи для беспарольного входа:
   ```bash
   ssh-copy-id pi@10.0.1.104
   ssh-copy-id pi@10.0.1.33
   ssh-copy-id pi@10.0.1.56
   ssh-copy-id pi@10.0.1.75
   ```

2. Проверьте подключение:
   ```bash
   ansible-playbook ping.yml
   ```

3. Создайте playbook'и для настройки кластера
