# Исправление сети в Ubuntu для Raspberry Pi

## Проблема

Ubuntu на Raspberry Pi: после записи образа через Raspberry Pi Imager ethernet-интерфейс не получает IP по DHCP. Причина — в стандартном образе файл `network-config` на boot-разделе содержит закомментированную конфигурацию, и cloud-init не настраивает сеть.

**Поддерживаемые версии:** Ubuntu 20.04, 22.04, 24.04, 25.10 для Raspberry Pi

## Корневая причина

На boot-разделе (`system-boot`) лежит файл `network-config`, который cloud-init читает при первой загрузке. В стандартном образе вся конфигурация в этом файле закомментирована. Cloud-init не находит активных настроек и не поднимает Ethernet.

## Решение

Два способа:
1. **Исправление уже записанной SD карты** — скрипт `fix-sd-network.sh`
2. **Создание исправленного образа** — скрипт `create-fixed-image.sh`

---

## Способ 1: Исправление записанной SD карты

```bash
# После записи образа на SD карту:
sudo ./scripts/fix-sd-network.sh /dev/diskX
```

Скрипт:
- Монтирует boot-раздел SD карты
- Проверяет и обновляет `meta-data` (добавляет `instance-id` если отсутствует)
- Создаёт правильный `network-config` с DHCP
- **Проверяет `cmdline.txt` на наличие `root=` параметра**
- **Предлагает восстановить `cmdline.txt` из `current/` если повреждён**

> **ВАЖНО: Ubuntu использует два cmdline.txt файла!**
>
> Ubuntu на Raspberry Pi хранит `cmdline.txt` в **ДВУХ местах**:
> - `/boot/firmware/cmdline.txt` — основной
> - `/boot/firmware/current/cmdline.txt` — резервная копия
>
> **При редактировании ВСЕГДА обновляйте ОБА файла, иначе изменения будут потеряны при загрузке!**

---

## Способ 2: Создание исправленного образа

Позволяет один раз создать образ с исправленной сетью и затем просто записывать его на новые SD карты.

```bash
# Создать исправленный образ:
sudo ./scripts/create-fixed-image.sh /path/to/ubuntu-24.04-raspi.img ubuntu-24.04-raspi-fixed.img

# Записать исправленный образ на SD карту (через dd или BalenaEtcher):
sudo dd if=ubuntu-24.04-raspi-fixed.img of=/dev/diskX bs=4m status=progress
```

---

## Структура скриптов

```
scripts/
├── fix-sd-network.sh      # Исправление уже записанной SD карты
└── create-fixed-image.sh  # Создание исправленного образа
```

---

## Что именно исправляется

**`network-config`** на boot-разделе заменяется на:
```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    id0:
      match:
        name: "en*"
      dhcp4: true
      optional: true
    id1:
      match:
        name: "eth*"
      dhcp4: true
      optional: true
    id2:
      match:
        name: "end*"
      dhcp4: true
      optional: true
```

Ключевые моменты:
- `match: name: "en*"` — современный systemd naming (enp0s25, eno1, enx...)
- `match: name: "eth*"` — классический naming (eth0, eth1...)
- `match: name: "end*"` — используется на некоторых ARM системах (end0)
- `renderer: networkd` — явно указываем рендерер для Ubuntu Server
- `dhcp4: true` — получает IP по DHCP автоматически
- `optional: true` — не блокирует загрузку если интерфейс не обнаружен сразу
- **meta-data** проверяется и обновляется (требуется `instance-id` для cloud-init)

### Чего НЕ нужно делать

Не добавляйте `network-config=...` в `cmdline.txt`. Это противоречит подходу:
- Если cloud-init network отключен, файл `network-config` не будет прочитан
- Некорректный синтаксис `network-config={config: disabled}` ломает парсинг cmdline

---

## Если скрипт уже применялся (старая версия)

Если вы ранее применяли скрипт, который добавлял `network-config={config: disabled}` в `cmdline.txt`, новая версия скрипта автоматически обнаружит и исправит это. Просто запустите обновлённый скрипт повторно.

---

## Отладка

Если сеть не работает после применения скрипта, проверьте на Raspberry Pi:

```bash
# Лог cloud-init (поиск ошибок сети)
cat /var/log/cloud-init-output.log | grep -i network

# Сгенерированный netplan конфиг
cat /etc/netplan/50-cloud-init.yaml

# Список интерфейсов
ip addr

# Статус интерфейса
ip link show

# Попробовать получить IP вручную
sudo dhclient -v eth0
# или
sudo dhclient -v end0
# или
sudo dhclient -v enp*
```

### Частые проблемы

1. **Интерфейс называется не eth0** — скрипт теперь покрывает `en*`, `eth*`, `end*`
2. **cloud-init уже отработал** — для повторного запуска:
   ```bash
   sudo cloud-init clean
   sudo reboot
   ```
3. **Нет instance-id в meta-data** — скрипт теперь проверяет и добавляет

---

## Ссылки

- [Raspberry Pi Forum - Ubuntu Server 24.04.1 eth0 disabled](https://forums.raspberrypi.com/viewtopic.php?t=377162)
- [AskUbuntu - Impossible to configure eth on Ubuntu 24.04](https://askubuntu.com/questions/1517469/on-raspberry-pi-3-with-ubuntu-24-04-server-64bits-impossible-to-configure-eth)
- [cloud-init Network Configuration](https://cloudinit.readthedocs.io/en/latest/reference/network-config.html)
- [cloud-init NoCloud Datasource](https://cloudinit.readthedocs.io/en/latest/reference/datasources/nocloud.html)
- [Ubuntu 25.10 A/B Boot for Raspberry Pi](https://canonical-ubuntu-hardware-support.readthedocs-hosted.com/boards/explanations/piboot-ab/)
