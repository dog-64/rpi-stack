# Ansible роль: ssd_rootfs

Перенос корневой файловой системы Raspberry Pi с microSD на SSD.

## Описание

Эта роль автоматически:
1. Обнаруживает подключённый SSD
2. Проверяет свободное место
3. Форматирует SSD в ext4 (если ещё не отформатирован)
4. Копирует систему с microSD на SSD через rsync
5. Обновляет fstab на SSD
6. Обновляет cmdline.txt на microSD для загрузки с SSD

## Требования

- Raspberry Pi 4/5 с Raspberry Pi OS
- Ansible 2.9+ на контроллере
- SSD подключён через USB
- root доступ на целевом хосте

## Переменные

### Обязательные

Нет обязательных переменных — роль автоматически определит SSD.

### Опциональные

| Переменная | По умолчанию | Описание |
|------------|--------------|-----------|
| `ssd_device` | `auto` | SSD устройство (например, `/dev/sda`) |
| `ssd_partition` | `auto` | SSD раздел (например, `/dev/sda1`) |
| `ssd_mount_point` | `/mnt/ssd` | Точка монтирования для операций |
| `boot_mount_point` | `/boot/firmware` | Boot раздел на microSD |
| `ssd_filesystem` | `ext4` | Файловая система |
| `ssd_mount_options` | `defaults,noatime` | Опции монтирования |
| `ssd_skip_confirmation` | `false` | Пропустить подтверждение форматирования |
| `ssd_reboot_after_config` | `true` | Перезагрузить после конфигурации |
| `ssd_min_free_space_ratio` | `1.1` | Минимальный коэффициент свободного места |

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

## Теги

- `detect` — Обнаружение SSD
- `check` — Проверка места
- `prereq` — Проверка пререквизитов
- `prepare` — Подготовка SSD
- `mount` — Монтирование SSD
- `copy` — Копирование системы
- `fstab` — Обновление fstab
- `cmdline` — Обновление cmdline.txt
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

## Откат

Если что-то пошло не так:

1. Загрузитесь с microSD (уберите SSD)
2. Восстановите cmdline.txt из backup:

```bash
sudo cp /boot/firmware/cmdline.txt.backup /boot/firmware/cmdline.txt
sudo reboot
```

## Автор

dog для проекта rpi_stack

## Лицензия

MIT
