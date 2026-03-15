# Развертывание Ubuntu на SSD без миграции с SD карты

**Простой и надёжный способ** установки Ubuntu на Raspberry Pi 4/5 напрямую на SSD/NVMe, минуя сложную миграцию с SD карты.

## Преимущества прямого развертывания

- ✅ **Проще**: fewer steps, less potential for errors
- ✅ **Надёжнее**: нет повреждённых cmdline.txt, cgroup проблем, etc.
- ✅ **Чистее**: свежая система без артефактов миграции
- ✅ **Быстрее**: один этап вместо двух (SD → SSD)

## Требования

- Raspberry Pi 4 или 5 (только эти модели поддерживают USB boot)
- SSD или NVMe диск с USB адаптером
- Mac (для записи образа) или Linux система
- Ubuntu 25.10 Raspberry Pi image

## Шаг 1: Прошивка Ubuntu на SSD

**На Mac:**
```bash
# Скачать Ubuntu 25.10 Raspberry Pi image
wget https://cdimage.ubuntu.com/releases/25.10/release/ubuntu-25.10-preinstalled-server-arm64+raspi.img.xz

# Распаковать
unxz ubuntu-25.10-preinstalled-server-arm64+raspi.img.xz

# Найти SSD диск
diskutil list

# Записать образ на SSD (внимательно проверь диск!)
sudo dd if=ubuntu-25.10-preinstalled-server-arm64+raspi.img of=/dev/rdiskX bs=4m conv=sync
```

## Шаг 2: Настройка EEPROM для загрузки с SSD

Подключи SSD к Raspberry Pi и загрузи **временно с SD карты** (любой Raspberry Pi OS image).

```bash
# Обнови EEPROM до последней версии
sudo rpi-eeprom-update -a

# Измени boot order для приоритетной загрузки с USB
sudo raspi-config

# Advanced Options → Boot Order → B1 USB Boot
# Или через команду:
echo "BOOT_ORDER=0xf15" | sudo tee /boot/firmware/pins.tsv

# Перезагрузи для применения настроек EEPROM
sudo reboot
```

**Проверь boot order:**
```bash
vcgencmd bootloader_config
# Должен показывать "BOOT_ORDER: 0xf15" (USB优先)
```

## Шаг 3: Фикс network на SSD разделе

**Тебе нужен Mac для этого шага!** Подключи SSD к Mac:

```bash
# Найди SSD раздел
diskutil list

# Запусти скрипт фикса сети
sudo ./scripts/fix-sd-network.sh /dev/diskX
```

**Что делает скрипт:**
- Добавляет `instance-id` в meta-data для cloud-init
- Настраивает network-config для DHCP
- Проверяет и исправляет cmdline.txt
- Включает `cgroup_enable=memory` (теперь автоматически!)

## Шаг 4: Первая загрузка с SSD

1. **Выключи Raspberry Pi**
2. **Убери SD карту** (важно для проверки что загрузка идёт с SSD!)
3. **Подключи только SSD**
4. **Включи питание**

Система загрузится с SSD и cloud-init настроит сеть.

## Шаг 5: Установка k3s

После первой загрузки и настройки сети:

```bash
# Обнови систему
sudo apt update && sudo apt upgrade -y

# Установи k3s через Ansible
make k3s-install NODES=sema

# Или вручную (для single-node setup)
curl -sfL https://get.k3s.io | sh -
```

## Проверка установки

```bash
# Проверь что загрузка идёт с SSD
mount | grep "/"

# Проверь сеть
ip addr show
ping -c 3 google.com

# Проверь k3s
systemctl status k3s
kubectl get nodes
```

## Отличия от миграции с SD

| Параметр | Миграция с SD | Прямое развертывание |
|----------|---------------|---------------------|
| **Сложность** | Высокая (много шагов) | Низкая (3-4 шага) |
| **Риски** | Повреждение cmdline.txt, cgroup проблемы | Минимальные |
| **Время** | 2-3 этапа | 1 этап |
| **Чистота системы** | Артефакты миграции | Свежая установка |
| **Отладка** | Сложно (что-то пошло не так?) | Просто (стандартная установка) |

## Troubleshooting

### Система не загружается с SSD

**Проверь EEPROM:**
```bash
# Загрузись с SD карты и проверь
vcgencmd bootloader_config
# Должен быть USB boot (0xf15)
```

**Проверь соединение SSD:**
```bash
lsusb
# Должен видеть USB адаптер с SSD
```

### Нет сети после первой загрузки

**Проверь network-config:**
```bash
cat /etc/netplan/50-cloud-init.yaml
# Должен быть DHCP configuration
```

**Проверь cloud-init логи:**
```bash
cat /var/log/cloud-init-output.log
cat /var/log/cloud-init.log
```

### k3s не стартует

**Проверь cgroups:**
```bash
cat /proc/cmdline | grep cgroup
# НЕ должно быть cgroup_disable=memory

systemctl status k3s
journalctl -u k3s -n 50
```

## Когда использовать миграцию с SD?

Прямое развертывание на SSD рекомендуется в **99% случаев**. Миграция с SD карты имеет смысл только если:

- У тебя **уже настроенная система** на SD которую нужно перенести
- Есть **специфические настройки** которые сложно воспроизвести
- Нужен **backup на SD** как fallback

Для всех новых установок - используй прямое развертывание!

## Автоматизация через Ansible

TODO: Можно добавить `make ssd-direct-setup` задачу для автоматизации:
- Прошивка SSD с правильным network-config
- Генерация cloud-init конфигов с hostname/SSH keys
- Подготовка EEPROM настроек
- Последующая установка k3s

## Ресурсы

- [Raspberry Pi USB Boot](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#usb-boot-mode)
- [Ubuntu Raspberry Pi Images](https://cdimage.ubuntu.com/releases/25.10/release/)
- [Raspberry Pi EEPROM Documentation](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#update-the-bootloader-eeprom)
