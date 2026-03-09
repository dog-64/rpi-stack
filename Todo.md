# Задачи для Raspberry Pi Cluster

**Приоритет:** от самого высокого (начало файла) к низшему (конец файла).

---

## [x] Миграция rootfs на SSD (Ubuntu 25.10, Pi 5)

**Статус:** ЗАВЕРШЕНО ✓ (2026-02-18)

**Выполнено на хосте:** sema (Pi 5, Ubuntu 25.10)

**Результат:**
- Root устройство: /dev/mmcblk0p2 → /dev/sda2 ✓
- Размер root: 57G → 111G ✓
- Boot остаётся на microSD (LABEL=system-boot)
- SSD имеет LABEL=writable, microSD переименован в writable-sd

**Процесс миграции:**
1. `rsync -axHAWX` — синхронизация rootfs на SSD
2. `tune2fs -L writable-sd /dev/mmcblk0p2` — изменение LABEL microSD
3. Обновление /etc/fstab на SSD
4. Перезагрузка

**Откат:** Если SSD не загрузится:
1. Отключить SSD физически
2. `tune2fs -L writable /dev/mmcblk0p2` (с Live USB)
3. Система загрузится с microSD

**Ansible роль:** `roles/ssd_rootfs/` — обновлена и протестирована

---

## [ ] Рефакторинг плейбуков в Ansible роли

**Описание:** Переписать все отдельные YAML файлы плейбуков в переиспользуемые Ansible роли по best practices.

**Текущая структура:**
- `ping.yml`
- `system-info.yml`
- `update-all.yml`
- `setup-cluster.yml`
- `fix-locale.yml`

**Требуемая структура:**
```
roles/
├── common/
│   ├── tasks/
│   ├── handlers/
│   ├── templates/
│   ├── files/
│   ├── vars/
│   └── defaults/
├── locale/
├── monitoring/
└── ...
```

**Чек-лист:**
- [ ] Создать структуру директорий roles/
- [ ] Выделить общие задачи в роль `common`
- [ ] Создать роль `locale` из fix-locale.yml
- [ ] Создать роль `cluster_setup` из setup-cluster.yml
- [ ] Обновить main playbooks для использования ролей
- [ ] Добавить тесты для ролей (molecule/ansible-test)

---

## [ ] Установить Mimir на сервер

**Описание:** Нужно сделать мониторинг состояния узлов кластера на Mimir + Grafana

**Чек-лист:**
- [ ] установка mimir to server as k8s app
- [ ] grafana sinstall to server as k8s app
- [ ] node-exporter to server and nodes as k8s app

---

## [ ] Попробовать сделать crontask at k3s

**Описание:** Краткое описание

**Чек-лист:**
- [ ] Подзадача 1
- [ ] Подзадача 2


---

## [ ] Поппробовать PVC on NFS

**Описание:** Краткое описание

**Чек-лист:**
- [ ] Подзадача 1
- [ ] Подзадача 2

---

## [ ] Сделать make status

**Описание:** Показ состояния всех компонентов - ping, temparature, переназначения / на ssd, k3s

**Чек-лист:**
- [ ] ping
- [ ] temperature
- [ ] / на ssd
- [ ] k3s 

---

## [ ] Новая задача

**Описание:** Краткое описание

**Чек-лист:**
- [ ] Подзадача 1
- [ ] Подзадача 2
