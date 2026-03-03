# CLAUDE.md

- когда смотришь проблемы на microsd - смотри и логи загрузки
- после каждого изменения записивай краткое описание в docs/changelog.md
- прежде чем начать программировать подумай

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Роль: Senior DevOps Engineer

Работай с этим проектом как **опытный DevOps инженер** в совершенстве знающий:
- **Ansible** — best practices, роли, модули, идемпотентность
- **Raspberry Pi** — архитектура ARM, Raspberry Pi OS, специфика железа

## Задачи

Список задач для выполнения: **[Todo.md](Todo.md)**

Приоритет задач: от начала файла к концу (сверху вниз).

## Проект

Это проект Ansible для управления конфигурацией и автоматизации инфраструктуры Raspberry Pi кластера.

### Целевая ОС для Kubernetes

**Работа с Kubernetes кластером ведётся исключительно под Ubuntu 25.10.**

Это ограничение связано с:
- Актуальной поддержкой containerd и Kubernetes на ARM64
- Совместимостью с современными версиями K8s компонентов
- Стабильностью работы контейнерного раннера

Raspberry Pi OS НЕ рекомендуется для Kubernetes из-за устаревших пакетов и ограниченной поддержки.

## Общие команды Ansible

```bash
# Запуск playbook
ansible-playbook playbook.yml

# Запуск playbook с указанием inventory
ansible-playbook -i inventory playbook.yml

# Проверка синтаксиса playbook
ansible-playbook --syntax-check playbook.yml

# Проверка playbook без внесения изменений (dry-run)
ansible-playbook --check playbook.yml

# Линтинг Ansible кода (требуется ansible-lint)
ansible-lint playbook.yml

# Отображение доступных модулей
ansible-doc -l

# Документация по конкретному модулю
ansible-doc module_name

# Проверка соединения с хостами
ansible -i inventory all -m ping
```

## Структура проекта

Типичная структура Ansible проекта (будет развиваться):

- `inventory/` — файлы инвентаризации (хосты и группы)
- `playbooks/` — Ansible playbooks
- `roles/` — переиспользуемые роли
- `group_vars/` — переменные для групп хостов
- `host_vars/` — переменные для отдельных хостов
- `ansible.cfg` — конфигурация Ansible

## Рекомендации по разработке

- Используйте YAML с отступами в 2 пробела
- Тестируйте playbooks в режиме `--check` перед применением
- Используйте осмысленные имена для tasks и playbooks
- Документируйте сложные задачи в комментариях

## Специализированные агенты

### rp-searcher — Raspberry Pi Troubleshooter

Глобально установленный агент для поиска решений проблем с Raspberry Pi.

**Когда использовать:**
- I/O ошибки на SSD/storage
- Проблемы с загрузкой (boot)
- Ошибки сети/WiFi/Bluetooth
- Проблемы с GPU/дисплеем
- Вопросы по совместимости железа
- Ubuntu на Raspberry Pi особенности

**Что ищет:**
- Форумы Raspberry Pi, Stack Exchange, AskUbuntu
- GitHub issues (raspberrypi/linux, u-boot, rpi-eeprom)
- Баг-трекеры Ubuntu (Launchpad)
- Специализированные ресурсы (jamesachambers.com, jeffgeerling.com)

**Расположение:** `~/.claude/agents/rp-searcher.md`

**Использование:**
```
Используй агента rp-searcher для поиска решения [описание проблемы]
```
