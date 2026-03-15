# Project Constitution

**Project**: rpi_stack — Raspberry Pi Cluster Infrastructure
**Created**: 2025-02-14
**Status**: Active

## Overview

Этот проект представляет собой Ansible-управляемую инфраструктуру для кластера Raspberry Pi. Цель — автоматизация конфигурации, развертывания и обслуживания однородных узлов для запуска контейнеризированных сервисов.

### Назначение

- DevOps/SysAdmin управление Raspberry Pi кластером
- Автоматизация рутиных операций через Ansible
- Развертывание K3s Kubernetes кластера на ARM-архитектуре
- Единая точка конфигурации для всех узлов

### Стек технологий

| Компонент | Выбор | Обоснование |
|------------|--------|--------------|
| Автоматизация | Ansible 2.9+ | Декларативная конфигурация, agentless |
| ОС | Raspberry Pi OS (Debian-based) | Официальная поддержка, оптимизации ARM |
| Оркестрация | K3s | Лёгкий Kubernetes, оптимизирован для IoT/edge |
| Железо | Raspberry Pi 4/5 | ARM64, достаточные ресурсы для контейнеров |
| Хранилище | SSD + microSD boot | Производительность I/O, надёжность |

---

## Core Principles

### 1. Идемпотентность (MUST)

Каждая операция Ansible ДОЛЖНА быть идемпотентной. Повторный запуск playbook или роли не должен менять состояние системы, если она уже в нужном состоянии.

**Примеры**:
- Проверка существования файла перед изменением
- Использование `state: present` вместо shell команд где возможно
- Регистрация фактов о выполненных изменениях

### 2. Безопасность сначала (MUST)

Никаких паролей или секретов в plaintext. Использовать Ansible Vault для чувствительных данных.

**Требования**:
- Все секреты в `group_vars/all/vault.yml`
- Vault пароль никогда не коммитится
- SSH ключи управляются отдельно от репозитория

### 3. Минимализм и простота (SHOULD)

Предпочитать простые решения над сложными. Использовать нативные Ansible модули вместо shell команд где возможно.

### 4. Документация как код (MUST)

Каждая роль ДОЛЖНА иметь README.md с описанием, переменными и примерами использования.

### 5. Тестируемость (SHOULD)

Каждое изменение ДОЛЖНО быть проверено на одном узле перед применением ко всему кластеру.

---

## Ansible Best Practices

### Структура ролей

```
role_name/
├── defaults/
│   └── main.yml          # Переменные по умолчанию
├── tasks/
│   ├── main.yml            # Entry point (include других файлов)
│   ├── main.yml            # Основные задачи
│   └── _subtask.yml        # Подзадачи (префикс _ для порядка)
├── handlers/
│   └── main.yml            # Handlers (notify: name)
├── templates/
│   └── config.j2           # Jinja2 шаблоны
├── files/
│   └── static_file          # Статические файлы
├── vars/
│   └── main.yml            # Переменные роли (редко используется)
├── meta/
│   └── main.yml            # Метаданные, зависимости
└── README.md               # Обязательная документация
```

### Соглашения по коду

| Правило | Пример |
|---------|---------|
| Отступы | 2 пробела (YAML) |
| Имена задач | verb_noun (например, install_docker, configure_network) |
| Имена переменных | snake_case |
| Теги | Всегда определять tags для задач (например, install, configure, verify) |
| Коментарии | Пояснять "зачем", а не "что" (код сам говорит что) |

### Использование модулей

**Предпочитать**:
- `apt` / `apt_repository` вместо `apt-get` shell команд
- `systemd` / `service` вместо systemctl
- `copy` / `template` вместо cp через shell
- `file` для создания директорий и файлов

**Избегать**:
- `shell` / `command` без `creates:` или `removes:`
- `ignore_errors: yes` без явной причины
- `async:` без понимания последствий

### Теги для задач

```yaml
- name: Install dependencies
  apt:
    name: "{{ packages }}"
    state: present
  tags:
    - install
    - dependencies
```

Рекомендуемые теги:
- `install` — установка пакетов
- `configure` — изменение конфигурации
- `verify` — проверки состояния
- `bootstrap` — первичная настройка

---

## Raspberry Pi Best Practices

### Производительность хранилища

| Рекомендация | Обоснование |
|--------------|--------------|
| rootfs на SSD (USB 3.0) | Скорость I/O в 5-10x выше microSD |
- /boot остаётся на microSD | Упрощает восстановление |
- ext4 с noatime | Снижение износа flash-памяти |
- Отключить swap на microSD | Избежать износа карты |

### Оптимизация системы

```bash
# /boot/config.txt оптимизации
gpu_mem=16              # Минимальный GPU для headless режима
max_usb_current=1         # Максимум тока для USB дисков

# sysctl оптимизации
vm.swappiness=1            # Минимальное использование swap
vm.dirty_ratio=40          # Кеширование записи для flash
```

### Сетевые настройки

```bash
# /etc/dhcpcd.conf для статического IP (если нужно)
interface eth0
static ip_address=10.0.1.XX/24
static routers=10.0.1.1
static domain_name_servers=1.1.1.1
```

### Мониторинг состояния

```bash
# Проверка температуры
vcgencmd measure_temp

# Проверка частоты throttling
vcgencmd get_throttled

# Проверка состояния SSD
smartctl -a /dev/sda
```

---

## K3s Best Practices

### Установка

```bash
# Рекомендуемый способ для Pi
curl -sfL https://get.k3s.io | sh -s - \
  --write-kubeconfig-mode 644 \
  --disable traefik \
  --disable servicelb \
  --node-name {{ inventory_hostname }}
```

### Конфигурация

```yaml
# /etc/rancher/k3s/config.yaml
write-kubeconfig-mode: 0644
disable:
  - traefik              # Используем свой ingress
  - servicelb            # Используем MetalLB
node-name: ${HOSTNAME}
tls-san:
  - ${HOSTNAME}
  - ${IP_ADDRESS}
```

### Управление кластером

| Практика | Описание |
|-----------|----------|
| Однородные узлы | Одинаковая версия K3s на всех нодах |
| Фиксированные IP | Использовать inventory IP, не полагаться на DHCP |
| Отдельный storage | Не смешивать системный диск и PVC |
| Registry proximity | Локальный registry для снижения трафика |

### Ресурсы

```yaml
# Лимиты для контейнеров на Pi
resources:
  requests:
    memory: "64Mi"
    cpu: "100m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

---

## Project Conventions

### Именование хостов

| Формат | Пример | Описание |
|---------|---------|-----------|
| {имя} | leha | Краткое, мнемоническое имя |
| ansible_host | 10.0.1.104 | IP адрес для подключения |
| hostname | p104 | Системное hostname (p + последние октеты) |

### Организация inventory

```yaml
all:
  children:
    active:        # Активные узлы
    inactive:      # Неактивные/планируемые
    pi5:          # Группировка по модели
    pi4_8gb:      # Группировка по памяти
```

### Структура playbooks

```
playbooks/
├── ping.yml              # Проверка доступности
├── update-all.yml        # Обновление пакетов
├── setup-cluster.yml     # Первичная настройка
├── fix-locale.yml        # Исправление локали
└── *.yml                # Операцонные playbooks
```

---

## Quality Gates

### Перед коммитом

- [ ] Playbook проходит `ansible-playbook --syntax-check`
- [ ] Новые роли имеют README.md
- [ ] Секреты в vault (если применимо)
- [ ] Тест на одном хосте пройден

### Перед слиянием

- [ ] Ветка обновлена от master
- [ ] Конфликты мерджены
- [ ] Todo.md обновлён (если применимо)

---

## Глоссарий

| Термин | Определение |
|---------|------------|
| node / узел | Один Raspberry Pi в кластере |
| master | Первая нода K3s (control plane) |
| worker | Рабочая нода K3s |
| pvc | PersistentVolumeClaim — запрос на хранилище |
| role | Ansible роль — переиспользуемая единица конфигурации |
| playbook | Ansible playbook — сценарий конфигурации хостов |
| inventory | Инвентарь — список хостов и групп |
| idempotent | Идемпотентность — повторное выполнение не меняет состояние |

---

## Изменения

Эта конституция может быть обновлена по мере развития проекта. Все изменения должны быть согласованы с DevOps командой и задокументированы в этом разделе.

| Дата | Изменение | Автор |
|-------|-----------|--------|
| 2025-02-14 | Создание конституции | Claude Code |
