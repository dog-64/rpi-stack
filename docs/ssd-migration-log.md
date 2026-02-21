# SSD Migration Log — motya (10.0.1.56)

## Проблемы предыдущих попыток

1. **Не регенерировался initramfs** — initramfs не знает где новый корень, загрузка зависает
2. **Таймауты zram, GPU, cups** — модули ядра не находятся из-за несовпадения путей
3. **Ядро 6.17 и отсутствие ip_tables/nf_tables** — upstream баг, нужен пакет `linux-modules-extra-raspi`
4. **Дублирование LABEL=writable** — обе метки совпадают, ядро монтирует не тот раздел

## Правильная последовательность

1. Форматировать SSD, создать ext4 с меткой `writable`
2. Смонтировать, скопировать rootfs через `rsync -axHAWX`
3. Написать правильный fstab на SSD
4. Регенерировать initramfs через chroot
5. Установить `linux-modules-extra-raspi` на SSD
6. Переименовать метку microSD в `writable-sd`
7. Перезагрузить

---

## Исходное состояние

- Хост: motya (10.0.1.56), Raspberry Pi 4, 8GB
- Root: `/dev/mmcblk0p2` (microSD, 57G, использовано 2.4G)
- Ядро: `6.17.0-1003-raspi`
- SSD: `/dev/sda` (119.2G), один раздел `sda1` (119.2G)
- Метка microSD: `writable`
- Метка SSD: `writable` (осталась от предыдущей неудачной миграции)
- cmdline.txt: `cfg80211.ieee80211_regdom=RU` (без root= — значит используется LABEL из initramfs)
- fstab: `LABEL=writable / ext4`, `LABEL=system-boot /boot/firmware vfat`

---

## Выполнение

### Шаг 1: Форматирование SSD
- **Команда:** `sudo mkfs.ext4 -F -L writable /dev/sda1`
- **Результат:** FORMAT OK, UUID: 205ccd49-42e2-4fb8-9848-7208594f4c6f, метка: writable
- **Хост доступен:** ДА

### Шаг 2: Монтирование SSD и копирование rootfs
- **Команды:**
  - `sudo mkdir -p /mnt/ssd && sudo mount /dev/sda1 /mnt/ssd`
  - `sudo rsync -axHAWX --info=progress2 / /mnt/ssd/ --exclude='/mnt/*' --exclude='/proc/*' --exclude='/sys/*' --exclude='/dev/*' --exclude='/run/*' --exclude='/tmp/*' --exclude='/boot/firmware/*'`
- **Результат:** RSYNC OK. SSD: 2.5G использовано из 117G
- **Хост доступен:** ДА

### Шаг 3: Записать fstab на SSD
- **Команда:** `echo '...' | sudo tee /mnt/ssd/etc/fstab`
- **Результат:** fstab записан, проверен — 2 строки, без дубликатов
- **Хост доступен:** ДА

### Шаг 4: Регенерировать initramfs через chroot
- **Команды:**
  - `sudo mount --bind /dev /mnt/ssd/dev`
  - `sudo mount --bind /proc /mnt/ssd/proc`
  - `sudo mount --bind /sys /mnt/ssd/sys`
  - `sudo mount --bind /boot/firmware /mnt/ssd/boot/firmware`
  - `sudo chroot /mnt/ssd update-initramfs -u -k all`
- **Результат:** `update-initramfs: Generating /boot/initrd.img-6.17.0-1003-raspi` — INITRAMFS OK
- **Хост доступен:** ДА

### Шаг 5: Проверка linux-modules-extra-raspi
- **Команда:** `find /lib/modules/6.17.0-1003-raspi -name 'br_netfilter*' -o -name 'ip_tables*' -o -name 'nf_tables*'`
- **Результат:** Модули br_netfilter.ko.zst, ip_tables.ko.zst, nf_tables.ko.zst ЕСТЬ в ядре 6.17.0-1003-raspi. Пакет linux-modules-extra-raspi не существует для Ubuntu 25.10, но модули включены в базовый пакет. На SSD они тоже скопированы.
- **Хост доступен:** ДА

### Шаг 6: Размонтировать и переименовать метку microSD
- **Команды:**
  - `sudo umount /mnt/ssd/{boot/firmware,sys,proc,dev}` + `sudo umount /mnt/ssd`
  - `sudo e2label /dev/mmcblk0p2 writable-sd`
- **Результат:** UNMOUNT OK. microSD label: `writable-sd`, SSD label: `writable`
- **Хост доступен:** ДА

### Шаг 7: Перезагрузка и проверка
- **Команда:** `sudo sync && sudo reboot now`
- **Результат:**
  - Root: `/dev/sda1` (SSD, 117G) — **МИГРАЦИЯ УСПЕШНА**
  - Ядро: `6.17.0-1003-raspi`
  - graphical.target: 45.6 сек
  - Полная загрузка: 5 мин 9 сек (из них ~4 мин — apt-daily.service, не критично)
  - `modprobe br_netfilter` — OK
  - `modprobe ip_tables` — OK
- **Хост доступен:** ДА

## Итог

Миграция rootfs на SSD выполнена успешно. Ключевое отличие от предыдущих неудачных попыток — **регенерация initramfs через chroot** (шаг 4), которая ранее пропускалась.

