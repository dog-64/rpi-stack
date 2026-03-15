# Implementation Plan: Перенос rootfs Raspberry Pi на SSD

**Feature**: 001-raspi-ssd-root
**Status**: Draft
**Created**: 2025-02-14
**Source**: [spec.md](./spec.md)

## Overview

Цель: Создать переиспользуемую Ansible роль для автоматического переноса корневой файловой системы Raspberry Pi с microSD на SSD, оставляя загрузочный раздел на microSD карте.

**Бизнес-ценность**:
- Повышение производительности I/O операций на 50%+
- Снижение износа microSD карты (логи, временные файлы на SSD)
- Автоматизация рутинной операции DevOps

---

## Architecture & Technology Stack

### Технологический выбор

| Компонент | Выбор | Обоснование |
|------------|--------|--------------|
| Автоматизация | Ansible 2.9+ | Уже используется в проекте, декларативный подход |
| Файловая система | ext4 | Стандарт для Raspberry Pi OS, стабильность |
| Таблица разделов | GPT | Современный стандарт, совместимость с Pi 4/5 |
| Копирование | rsync | Сохранение атрибутов, возможности инкрементального копирования |
| Идентификация | UUID | Надёжность при изменении порядка устройств |

### Структура Ansible роли

```
roles/
└── ssd_rootfs/
    ├── defaults/
    │   └── main.yml           # Переменные по умолчанию
    ├── tasks/
    │   ├── main.yml             # Главный entry point
    │   ├── detect_ssd.yml       # Обнаружение SSD
    │   ├── check_space.yml        # Проверка свободного места
    │   ├── prepare_ssd.yml       # Разметка и форматирование
    │   ├── copy_rootfs.yml       # Копирование системы
    │   ├── update_fstab.yml      # Обновление fstab
    │   ├── update_cmdline.yml     # Обновление cmdline.txt
    │   ├── verify.yml            # Верификация
    │   └── cleanup.yml           # Очистка временных файлов
    ├── handlers/
    │   └── main.yml
    ├── templates/
    │   └── fstab.j2            # Шаблон fstab (опционально)
    └── meta/
        └── main.yml             # Метаданные роли, зависимости
```

---

## Data Flow

```
┌─────────────────┐
│  Ansible       │
│  Controller    │
└───────┬───────┘
        │ SSH
        ▼
┌─────────────────────────────────────────┐
│  Raspberry Pi (leha: 10.0.1.104)   │
│                                      │
│  ┌────────────┐  ┌──────────────┐    │
│  │ microSD     │  │ SSD (USB)     │    │
│  │ /boot       │  │               │    │
│  │            │  │ ┌──────────┐ │    │
│  │ /          │  │ │ / (rootfs)│ │    │
│  └────────────┘  │ └──────────┘ │    │
│  └─────────────────────────────────┘
│         mmcblk0p1     sda1
└─────────────────────────────────────────┘
```

### Процесс переноса

```
1. DETECT:   Определить SSD среди блочных устройств
2. CHECK:     Проверить свободное место (SSD >= использовано на microSD)
3. PREPARE:   Создать GPT таблицу + ext4 раздел на SSD
4. COPY:      rsync -axHAWX / → /mnt/ssd
5. CONFIGURE: Обновить fstab (root=UUID) на SSD
6. CONFIGURE: Обновить cmdline.txt (root=UUID) на microSD
7. VERIFY:    Проверить целостность скопированных файлов
8. REBOOT:    Перезагрузка для загрузки с SSD
9. VALIDATE:  df -h подтвердить что / на SSD
```

---

## Implementation Phases

### Phase 1: Foundation (P0 - Базовая инфраструктура)

**Цель**: Создать структуру роли и базовое обнаружение SSD

| Задача | Описание | Зависимости |
|--------|----------|--------------|
| Создать структуру директорий роли | roles/ssd_rootfs/{tasks,defaults,handlers,meta,templates} | - |
| Определить переменные по умолчанию | ssd_device (auto-detect), ssd_mount_point (/mnt/ssd) | - |
| Реализовать detec_ssd.yml | lsblk для поиска USB устройств хранения | - |
| Реализовать проверки пререквизитов | Проверить наличие fdisk, mkfs.ext4, rsync, blkid | detect_ssd.yml |

**Результат**: Роль может определить SSD и проверить наличие необходимых утилит.

---

### Phase 2: SSD Preparation (P1 - Критический путь)

**Цель**: Подготовить SSD к приёму данных

| Задача | Описание | Зависимости |
|--------|----------|--------------|
| Реализовать check_space.yml | Сравнить объём SSD с текущим использованием / | detect_ssd.yml |
| Реализовать confirm_format.yml | Запрос подтверждения если SSD имеет данные | check_space.yml |
| Реализовать prepare_ssd.yml | fdisk GPT + mkfs.ext4 с noatime | confirm_format.yml |
| Получить UUID раздела | blkid для использования в конфигах | prepare_ssd.yml |

**Результат**: SSD отформатирован в ext4, UUID известен.

---

### Phase 3: Data Migration (P1 - Критический путь)

**Цель**: Перенести корневую файловую систему на SSD

| Задача | Описание | Зависимости |
|--------|----------|--------------|
| Реализовать монтирование SSD | mount to {{ ssd_mount_point }} | prepare_ssd.yml |
| Реализовать copy_rootfs.yml | rsync -axHAWX --info=progress2 / → /mnt/ssd | mount |
| Добавить progress bar | Опционально: показать прогресс копирования | copy_rootfs.yml |
| Сохранить UUID для конфигов | set_fact для использования в следующих tasks | copy_rootfs.yml |

**Результат**: rootfs скопирован на SSD с сохранением всех атрибутов.

---

### Phase 4: Configuration Update (P1 - Критический путь)

**Цель**: Настроить загрузку с SSD

| Задача | Описание | Зависимости |
|--------|----------|--------------|
| Реализовать update_fstab.yml | Заменить root mount на UUID в /mnt/ssd/etc/fstab | copy_rootfs.yml |
| Сохранить /boot mount в fstab | Убедиться что /boot остаётся на mmcblk0p1 | update_fstab.yml |
| Реализовать update_cmdline.yml | Заменить root= в /boot/cmdline.txt на root=UUID= | copy_rootfs.yml |
| Добавить откат при ошибке | Сохранить оригиналы .backup | update_fstab.yml, update_cmdline.yml |

**Результат**: Система настроена для загрузки с SSD.

---

### Phase 5: Verification & Cleanup (P2 - Важное)

**Цель**: Убедиться в корректности переноса

| Задача | Описание | Зависимости |
|--------|----------|--------------|
| Реализовать verify.yml | Сравнить размер до/после, проверить ключевые файлы | copy_rootfs.yml |
| Реализовать cleanup.yml | unmount SSD, удалить временные файлы | verify.yml |
| Добавить recommendation | Вывести сообщение о необходимости ручной перезагрузки | cleanup.yml |

**Результат**: Роль завершена корректно, система готова к перезагрузке.

---

### Phase 6: Idempotency & Safety (P2 - Важное)

**Цель**: Обеспечить безопасный повторный запуск

| Задача | Описание | Зависимости |
|--------|----------|--------------|
| Добавить проверку состояния | Detect если / уже на SSD | detect_ssd.yml |
| Пропустить destructive ops | Если перенос уже выполнен | state check |
| Добавить rollback опцию | Опционально: восстановить microSD boot | - |

**Результат**: Роль идемпотентна.

---

### Phase 7: Integration & Testing (P3 - Улучшение)

**Цель**: Интеграция с проектом и тестирование

| Задача | Описание | Зависимости |
|--------|----------|--------------|
| Создать playbook для роли | playbooks/ssd-migrate.yml | Все phases |
| Добавить в README документацию | Инструкция по использованию | - |
| Протестировать на leha (10.0.1.104) | Фактический перенос системы | - |
| Обновить Todo.md | Отметить задачу выполненной | - |

**Результат**: Роль готова к использованию на других узлах.

---

## Variables & Configuration

### Переменные роли (defaults/main.yml)

```yaml
# SSD устройство (auto-detect если не указан)
ssd_device: auto

# Точка монтирования для операций
ssd_mount_point: /mnt/ssd

# Файловая система
ssd_filesystem: ext4
ssd_mount_options: defaults,noatime

# Безопасность
ssd_skip_confirmation: false
ssd_enable_rollback: false

# Порог для предупреждения (GB)
ssd_min_free_space_ratio: 1.1  # 10% запас
```

### Inventory переменные (опционально)

```yaml
# host_vars/leha.yml
ssd_device: /dev/sda
ssd_skip_confirmation: true  # для автоматического запуска
```

---

## Risk Mitigation

| Риск | Вероятность | Влияние | Митигация |
|------|-------------|----------|-----------|
| SSD не обнаружен | Средняя | Блокировка | Проверка с clear error message |
| Недостаточно места | Низкая | Потеря данных | Pre-check до форматирования |
| Сбой питания при копировании | Средняя | Частичная потеря данных | rsync с возможностью продолжения |
| Ошибочные UUID в конфигах | Низкая | Невозможность загрузки | Backup оригиналов + verify step |
| Несколько SSD | Низкая | Неправильный диск | Явное указание или prompt |

---

## Non-Functional Considerations

### Performance

- rsync с `-axHAWX` для оптимизации скорости копирования
- Прогресс бар для больших переносов (до 20GB / ~30 min)

### Reliability

- Backup оригинальных fstab и cmdline.txt
- Проверка целостности после копирования
- Idempotency для безопасного повторного запуска

### Maintainability

- Модульная структура tasks (каждая операция в отдельном файле)
- Подробные комментарии для будущих разработчиков
- Документация в README роли

---

## Success Metrics

| Метрика | Цель | Способ измерения |
|----------|--------|------------------|
| Корень на SSD после перезагрузки | /dev/sdX1 | `df -h` |
| /boot остаётся на microSD | /dev/mmcblk0p1 | `df -h` |
| Скорость I/O улучшена | +50% | benchmark (dd/iozone) |
| Идемпотентность | unchanged при повторном запуске | ansible-playbook --check |
| Время выполнения | <30 min для 20GB | time ansible-playbook |

---

## Definition of Done

- [ ] Все фазы реализованы
- [ ] Роль работает на leha (10.0.1.104)
- [ ] Система загружается с SSD после переноса
- [ ] Роль идемпотентна
- [ ] README с инструкцией создан
- [ ] Todo.md обновлён
