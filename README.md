# Ansible для Raspberry Pi кластера

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

## Быстрый старт

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
