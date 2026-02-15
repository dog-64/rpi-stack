# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

- всегда проверяй что получилось в результате своих изменений
- никогда не ври

## Роль: Senior DevOps Engineer

Работай с этим проектом как **опытный DevOps инженер** в совершенстве знающий:
- **Ansible** — best practices, роли, модули, идемпотентность
- **Raspberry Pi** — архитектура ARM, Raspberry Pi OS, специфика железа

## SpecKit

Спецификации для AI агентов находятся в `.github/spec-kit/`:

- **[agents.md](.github/spec-kit/agents.md)** — Задачи для выполнения (приоритет сверху вниз)
- **[constitution.md](.github/spec-kit/constitution.md)** — Best practices для Ansible, K8s, K3s

```bash
make spec-kit-constitution  # Показать best practices
```

## Проект

Это проект Ansible для управления конфигурацией и автоматизации инфраструктуры Raspberry Pi кластера.

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

## Active Technologies
- Ansible 2.x, YAML, Bash (скрипты установки/верификации) + K3s (фиксированная версия в group_vars), kubectl, Ansible (002-k3s-install)
- SQLite (встроенное хранилище K3s для single-server), local-path-provisioner (default StorageClass) (002-k3s-install)

## Recent Changes
- 002-k3s-install: Added Ansible 2.x, YAML, Bash (скрипты установки/верификации) + K3s (фиксированная версия в group_vars), kubectl, Ansible
