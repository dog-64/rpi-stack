# Ansible роль: ssd_rootfs

Перенос корневой файловой системы Raspberry Pi с microSD на SSD.

## Описание

Эта роль автоматически:
1. Обнаруживает подключённый SSD
2. Проверяет свободное место
3. Форматирует SSD в ext4 (если ещё не отформатирован)
4. Копирует систему с microSD на SSD через rsync
5. Обновляет fstab на SSD
6. Обновляет загрузочную конфигурацию для загрузки с SSD

## Поддерживаемые ОС

- **Ubuntu 25.10** (рекомендуется для Kubernetes)
- Raspberry Pi OS (legacy)

> **Важно:** Для Kubernetes на Raspberry Pi используйте Ubuntu 25.10, так как он предоставляет актуальную поддержку containerd и K8s компонентов на ARM64.

## Требования

- Raspberry Pi 4/5 с Ubuntu 25.10 или Raspberry Pi OS
- Ansible 2.9+ на контроллере
- SSD подключён через USB
- root доступ на целевом хосте

## Переменные

### Обязательные

Нет обязательных переменных — роль автоматически определит SSD.

### Опциональные

| Переменная | По умолчанию | Описание |
|------------|--------------|-----------|
| `ssd_target_os` | `ubuntu` | Целевая ОС: `ubuntu` или `rpi_os` |
| `ssd_device` | `auto` | SSD устройство (например, `/dev/sda`) |
| `ssd_partition` | `auto` | SSD раздел (например, `/dev/sda1`) |
| `ssd_mount_point` | `/mnt/ssd` | Точка монтирования для операций |
| `boot_mount_point` | авто | Boot раздел (авто: `/boot/firmware` для Ubuntu, `/boot` для RPi OS) |
| `ssd_filesystem` | `ext4` | Файловая система |
| `ssd_mount_options` | `defaults,noatime` | Опции монтирования |
| `ssd_skip_confirmation` | `false` | Пропустить подтверждение форматирования |
| `ssd_reboot_after_config` | `true` | Перезагрузить после конфигурации |
| `ssd_min_free_space_ratio` | `1.1` | Минимальный коэффициент свободного места |
| `ubuntu_root_label` | `writable` | Метка root раздела для Ubuntu |
| `ubuntu_boot_label` | `system-boot` | Метка boot раздела для Ubuntu |

## Использование

### Запуск роли на всех хостах

```bash
ansible-playbook -i inventory.yml playbooks/ssd-migrate.yml
```

### Запуск на конкретном хосте

```bash
ansible-playbook -i inventory.yml playbooks/ssd-migrate.yml --limit leha
```

### Запуск с проверкой (dry-run)

```bash
ansible-playbook -i inventory.yml playbooks/ssd-migrate.yml --check
```

### Запуск с переменными

```bash
ansible-playbook -i inventory.yml playbooks/ssd-migrate.yml -e "ssd_device=/dev/sda" -e "ssd_skip_confirmation=true"
```

### Для Raspberry Pi OS

```bash
ansible-playbook -i inventory.yml playbooks/ssd-migrate.yml -e "ssd_target_os=rpi_os"
```

## Теги

- `detect` — Обнаружение SSD
- `check` — Проверка места
- `prereq` — Проверка пререквизитов
- `prepare` — Подготовка SSD
- `mount` — Монтирование SSD
- `copy` — Копирование системы
- `fstab` — Обновление fstab
- `cmdline` — Обновление загрузочной конфигурации
- `verify` — Верификация
- `cleanup` — Очистка

Пример запуска только определённых задач:

```bash
ansible-playbook -i inventory.yml playbooks/ssd-migrate.yml --tags "detect,check"
```

## Идемпотентность

Роль идемпотентна:
- Если система уже загружается с SSD, роль пропускает все операции
- Если на SSD уже есть ext4 с rootfs, роль пропускает копирование
- При повторном запуске destructive операции не выполняются

## Структура роли

```
roles/ssd_rootfs/
├── defaults/
│   └── main.yml          # Переменные по умолчанию
├── handlers/
│   └── main.yml          # Обработчики (перезагрузка)
├── meta/
│   └── main.yml          # Метаданные роли
├── tasks/
│   ├── main.yml          # Главный файл задач
│   ├── detect_ssd.yml    # Обнаружение SSD
│   ├── check_space.yml   # Проверка места
│   ├── check_prerequisites.yml  # Проверка утилит
│   ├── prepare_ssd.yml   # Подготовка SSD (форматирование)
│   ├── mount_ssd.yml     # Монтирование SSD
│   ├── copy_rootfs.yml   # Копирование системы
│   ├── update_fstab.yml  # Обновление fstab
│   ├── update_cmdline.yml  # Обновление cmdline.txt
│   ├── verify.yml        # Верификация
│   └── cleanup.yml       # Очистка
└── README.md             # Этот файл
```

## Проверка результата

После перезагрузки выполните:

```bash
ssh dog@10.0.1.104 "df -h /"
```

Должно показать:
```
Файловая система Размер Использовано  Дост Использовано% Cмонтировано в
/dev/sda2          110G         6,7G   99G            7% /
```

Обратите внимание на `/dev/sda2` (SSD) вместо `/dev/mmcblk0p2` (microSD).

## Отличия Ubuntu от Raspberry Pi OS

| Характеристика | Ubuntu 25.10 | Raspberry Pi OS |
|----------------|--------------|-----------------|
| Boot раздел | `/boot/firmware` | `/boot` |
| Идентификатор раздела | LABEL | PARTUUID |
| Метка root | `writable` | N/A |
| Метка boot | `system-boot` | N/A |
| Загрузочный конфиг | `/boot/firmware/cmdline.txt` | `/boot/cmdline.txt` |

## Откат

Если что-то пошло не так:

1. Загрузитесь с microSD (уберите SSD)
2. Восстановите cmdline.txt из backup:

**Для Ubuntu:**
```bash
sudo cp /boot/firmware/cmdline.txt.backup /boot/firmware/cmdline.txt
sudo reboot
```

**Для Raspberry Pi OS:**
```bash
sudo cp /boot/cmdline.txt.backup /boot/cmdline.txt
sudo reboot
```

## Автор

dog для проекта rpi_stack

## Лицензия

MIT
