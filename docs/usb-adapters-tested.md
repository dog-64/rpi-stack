# USB-SATA адаптеры для Raspberry Pi 4

Протестированные адаптеры для подключения SSD к Raspberry Pi 4.

---

## ✅ Работающие адаптеры

### ASMedia (174c:235c) — Ugreen Storage Device

**Хост:** osya (Raspberry Pi 4, Ubuntu)
**Скорость:** 197 MB/sec
**USB:** 3.0 (5000M)
**Драйвер:** uas
**I/O ошибки:** Нет

```bash
lsusb
# Bus 002 Device 003: ID 174c:235c ASMedia Technology Inc. Ugreen Storage Device
```

**Статус:** ✅ Рекомендуется

---

## ❌ Проблемные адаптеры

### VIA VL817 (2109:0715)

**Хост:** osya (Raspberry Pi 4, Ubuntu)
**Скорость:** 8.5 MB/sec
**Проблема:** UAS driver не работает корректно

**Подробнее:** [→ lessons-learned.md](lessons-learned.md)

---

## Как проверить адаптер

```bash
# Показать все USB устройства
lsusb

# Показать USB топологию с драйверами
lsusb -t

# Проверить скорость SSD
sudo hdparm -t /dev/sdaX
```

---

## Ожидаемые скорости

| Адаптер | Скорость чтения |
|---------|-----------------|
| ASMedia (174c:235c) | ~200 MB/sec ✅ |
| VIA VL817 (2109:0715) | ~8 MB/sec ❌ |
| JMS578 | ~180-350 MB/sec ✅ |
| OWC/ULT-Best (7825:a2a4) | ~380+ MB/sec ✅ |

---

## Дата последнего обновления
2026-03-05
