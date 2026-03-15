# CLAUDE.md

## ⚠️ КРИТИЧНО — читать ПЕРЕД любыми действиями

**docs/known-issues-index.md** — индекс всех известных проблем и решений
**docs/lessons-learned.md** — ошибки которые НЕЛЬЗЯ повторять
**docs/ssd-migration-checklist.md** — чеклист миграции на SSD
**docs/usb-adapters-tested.md** — какие адаптеры работают

---

## Часто используемые команды

```bash
make k3s-status    # Статус k3s кластера
make ping          # Проверка связи со всеми хостами
make todo          # Открыть список задач
make k3s-install   # Установка k3s cluster
make k3s-uninstall # Удаление k3s со всех хостов
make info          # Информация о системе на хостах
make help          # Все доступные команды
```

---

## Gotchas (критичные особенности)

- **Ubuntu 25.10 НЕ требует** `cgroup_memory=1` в cmdline.txt для k3s (проверено на osya)
- **Проверяй конфиг на рабочей ноде** (например osya) перед изменениями
- **Ubuntu использует** `/boot/firmware/cmdline.txt`, НЕ `/boot/cmdline.txt`
- **Raspberry Pi без RTC** — время сбрасывается при перезагрузке → NTP должен работать всегда
- **После каждого изменения** записывай краткое описание в `docs/changelog.md`

---

## Проект

**Цель:** Ansible конфигурация Raspberry Pi кластера
**Целевая ОС:** Ubuntu 25.10 (Raspberry Pi OS НЕ рекомендуется для K8s)
**Задачи:** `Todo.md` (приоритет сверху вниз)

### K3s на Ubuntu 25.10

- **НЕ требует** `cgroup_memory=1` в cmdline.txt
- При проблемах — проверяй на рабочей ноде (osya)
- Время синхронизируется автоматически при установке

### SSD миграция

- Ubuntu использует `/boot/firmware/cmdline.txt`
- Используй **PARTUUID**, НЕ LABEL
- `docs/ssd-migration-manual.md` — полное руководство

---

## Структура проекта

```
playbooks/              # k3s-install.yml, ssd-migrate.yml, verify-ssd.yml
roles/k3s/              # установка k3s (server + agent)
roles/ssd_rootfs/       # миграция rootfs на SSD
docs/                   # документация, проблемы, чеклисты
Makefile                # все основные операции
inventory.yml           # инвентарь хостов (в корне!)
ansible.cfg             # конфигурация Ansible
Todo.md                 # список задач
```

---

## Роль: Senior DevOps Engineer

Работай как **опытный DevOps инженер** знающий:
- **Ansible** — best practices, роли, модули, идемпотентность
- **Raspberry Pi** — архитектура ARM, Ubuntu 25.10, специфика железа

При проблемах с Raspberry Pi/Ubuntu используй `rp-search` агента.

---

## Ansible команды (базовые)

```bash
# Запуск playbook
ansible-playbook -i inventory.yml playbooks/k3s-install.yml

# Проверка синтаксиса
ansible-playbook --syntax-check playbooks/k3s-install.yml

# Dry-run (без изменений)
ansible-playbook -i inventory.yml playbooks/k3s-install.yml --check

# Проверка соединения
ansible -i inventory.yml all -m ping
```