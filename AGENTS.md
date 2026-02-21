# Repository Guidelines

## Роль: Senior DevOps Engineer

Работай с этим проектом как **опытный DevOps инженер** в совершенстве знающий:
- **Ansible** — best practices, роли, модули, идемпотентность
- **Raspberry Pi** — архитектура ARM, Raspberry Pi OS/Ubuntu, специфика железа

- никогда не делай `ssh-keygen`

---
Если при обращении к хосту
```
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!
IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
```
то удали записи о хосте из `~/.ssh/known_hosts` и повтори обращение к нему

## Задачи

Список задач для выполнения: **[Todo.md](Todo.md)**

Приоритет задач: от начала файла к концу (сверху вниз).

---

## Project Overview

Ansible проект для управления конфигурацией и автоматизации Raspberry Pi кластера.

### Целевая ОС

**Kubernetes кластер работает исключительно под Ubuntu 25.10.**

Raspberry Pi OS НЕ используется для Kubernetes из-за устаревших пакетов и ограниченной поддержки containerd.

---

## Build, Test, and Development Commands

### Основные команды (Makefile)

```bash
make help          # Показать все доступные команды
make check         # Проверить синтаксис всех playbook'ов
make ping          # Проверить подключение ко всем хостам
make info          # Показать информацию о системе
make update        # Обновить все хосты
make clean         # Очистить временные файлы (*.retry)
```

### Ansible команды

```bash
# Проверка синтаксиса playbook
ansible-playbook --syntax-check playbook.yml

# Dry-run (без внесения изменений)
ansible-playbook --check playbook.yml

# Запуск с ограничением по хостам
ansible-playbook playbook.yml --limit pi5
ansible-playbook playbook.yml --limit leha

# Запуск с конкретными тегами
ansible-playbook playbook.yml --tags detect,verify
```

### Линтинг

```bash
# Проверка линтером (требуется ansible-lint)
ansible-lint playbook.yml

# Проверка всей директории
ansible-lint roles/

# Конкретная роль
ansible-lint roles/ssd_rootfs/
```

### Тестирование ролей (Molecule)

```bash
# Установка molecule
pip install molecule molecule-docker

# Создание тестов для новой роли
molecule init scenario --role-name my_role

# Запуск тестов роли
molecule test

# Запуск конкретного шага
molecule create    # Создать тестовые контейнеры
molecule converge  # Применить роль
molecule verify    # Запустить тесты
molecule destroy   # Удалить контейнеры
```

### Запуск теста для отдельной роли

```bash
cd roles/ssd_rootfs
molecule test
```

---

## Project Structure

```
rpi_stack/
├── ansible.cfg              # Конфигурация Ansible
├── inventory.yml            # Инвентаризация хостов
├── Makefile                 # Команды автоматизации
├── playbooks/               # Playbook'и
│   ├── ssd-migrate.yml
│   └── verify-ssd.yml
├── roles/                   # Ansible роли
│   └── ssd_rootfs/
│       ├── defaults/main.yml    # Переменные по умолчанию
│       ├── handlers/main.yml    # Обработчики событий
│       ├── meta/main.yml        # Метаданные роли
│       ├── tasks/               # Задачи роли
│       │   ├── main.yml
│       │   ├── detect_ssd.yml
│       │   └── ...
│       └── README.md            # Документация роли
├── specs/                   # Спецификации задач
├── *.yml                    # Корневые playbook'и
└── Todo.md                  # Список задач
```

---

## Code Style Guidelines

### YAML форматирование

- **Отступы:** 2 пробела (НЕ табы)
- **Кодировка:** UTF-8
- **Длина строки:** максимум 120 символов
- **Списки:** каждый элемент на новой строке с дефисом

```yaml
# Правильно
- name: Install packages
  ansible.builtin.apt:
    name:
      - vim
      - htop
    state: present

# Неправильно
- name: Install packages
  ansible.builtin.apt: name=[vim, htop] state=present
```

### Именование

| Элемент | Стиль | Пример |
|---------|-------|--------|
| Файлы YAML | `snake_case.yml` | `detect_ssd.yml` |
| Переменные | `snake_case` | `ssd_device`, `ssd_mount_point` |
| Роли | `snake_case` | `ssd_rootfs`, `cluster_setup` |
| Таски | Описательные имена | `Detect SSD device` |
| Теги | `snake_case` | `detect`, `verify`, `ssd_rootfs` |

### Имена задач (tasks)

```yaml
# Правильно: осмысленное описание на русском или английском
- name: Detect SSD device
- name: Проверить свободное место на диске

# Неправильно: неинформативные имена
- name: Run command
- name: Do stuff
```

### Модули Ansible

Используйте полные имена модулей с пространством имён:

```yaml
# Правильно
ansible.builtin.apt:
ansible.builtin.copy:
ansible.builtin.template:
ansible.builtin.command:
ansible.builtin.shell:
ansible.builtin.stat:
ansible.builtin.set_fact:
ansible.builtin.debug:
ansible.builtin.include_tasks:
ansible.builtin.meta:

# Неправильно (устаревший формат)
apt:
copy:
command:
```

### Идемпотентность

Все задачи должны быть идемпотентными:

```yaml
# Правильно: с проверкой changed_when
- name: Get current root device
  ansible.builtin.shell: df / | tail -1 | awk '{print $1}'
  changed_when: false
  register: current_root_device

# Правильно: использование модуля с проверкой состояния
- name: Ensure package is installed
  ansible.builtin.apt:
    name: vim
    state: present
```

### Переменные

```yaml
# defaults/main.yml - значения по умолчанию
ssd_device: auto
ssd_mount_point: /mnt/ssd

# Использование Jinja2 с фильтрами
boot_mount_full_path: "{{ '/boot/firmware' if ssd_target_os == 'ubuntu' else '/boot' }}"

# Значения по умолчанию для неопределённых переменных
when: ssd_reboot_after_config | default(false) | bool
```

### Условия (when)

```yaml
# Многострочные условия для читаемости
- name: Skip if already on SSD
  ansible.builtin.debug:
    msg: "Already on SSD"
  when:
    - ssd_rootfs_exists | default(false) | bool
    - ssd_device != 'auto'
```

### Теги

Добавляйте теги для выборочного запуска задач:

```yaml
- name: Detect SSD device
  ansible.builtin.shell: lsblk -d -o NAME,SIZE -n
  tags:
    - detect
    - ssd_rootfs
```

### Обработчики (handlers)

```yaml
# handlers/main.yml
- name: Reboot to boot from SSD
  ansible.builtin.shell: sleep {{ ssd_reboot_delay | default(5) }} && reboot
  async: 1
  poll: 0
  listen: "reboot system"

# В tasks:
- name: Notify reboot
  ansible.builtin.debug:
    msg: "Reboot required"
  notify: "reboot system"
```

### Обработка ошибок

```yaml
# Явная проверка результата
- name: Check SSD device exists
  ansible.builtin.stat:
    path: "/dev/{{ ssd_device }}"
  register: ssd_stat
  failed_when: not ssd_stat.stat.exists

# Игнорирование ошибок (когда допустимо)
- name: Try to unmount
  ansible.builtin.mount:
    path: "{{ ssd_mount_point }}"
    state: unmounted
  ignore_errors: true

# Явное сообщение об ошибке
- name: Fail if no SSD found
  ansible.builtin.fail:
    msg: "SSD устройство не найдено. Подключите SSD и попробуйте снова."
  when:
    - ssd_candidates_output.stdout_lines | length == 0
```

---

## Commit Guidelines

- Формат: `type(scope): summary` или свободный формат на русском
- Типы: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`
- Примеры:
  - `feat(ssd_rootfs): add Ubuntu 25.10 support`
  - `fix(mount): correct fstab entry for ext4`
  - `docs: update README with new commands`

---

## Security

- **Секреты:** используйте Ansible Vault для шифрования секретов
- **Файлы секретов:** добавлены в `.gitignore` (`secrets.yml`, `vault_pass.txt`, `*.vault`)
- **SSH ключи:** не коммитьте, используйте `ssh-copy-id` для развертывания

```bash
# Создание зашифрованного файла
ansible-vault create secrets.yml

# Редактирование
ansible-vault edit secrets.yml

# Запуск playbook с секретами
ansible-playbook playbook.yml --ask-vault-pass
```

---

## Inventory

Группы хостов в `inventory.yml`:

| Группа | Описание | Хосты |
|--------|----------|-------|
| `active` | Активные хосты | leha, sema, motya, osya |
| `pi5` | Raspberry Pi 5 | leha, sema |
| `pi4_8gb` | Raspberry Pi 4 8GB | motya, osya |
| `high_memory` | Хосты с 8GB+ | pi5 + pi4_8gb |

---

## Рекомендации

1. Всегда запускайте `make check` или `ansible-lint` перед коммитом
2. Тестируйте playbooks в режиме `--check` перед применением на production
3. Используйте `--limit` для тестирования на одном хосте
4. Документируйте сложные задачи в комментариях
5. Следите за идемпотентностью задач
