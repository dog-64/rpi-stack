---

# Tasks: Перенос rootfs Raspberry Pi на SSD

**Input**: Design documents from `/specs/001-raspi-ssd-root/`
**Prerequisites**: plan.md, spec.md

**Tests**: Ansible роли тестируются путём выполнения на хосте leha (10.0.1.104) с последующей верификацией состояния.

**Всего задач**: 42 (T000-T041)

**Распределение по фазам**:
- Phase 0: Manual Testing — 8 задач (T000-T007)
- Phase 1: Setup — 5 задач (T008-T012)
- Phase 2: Foundational — 4 задачи (T013-T016)
- Phase 3: US1 — 4 задачи (T017-T020) 🎯 MVP
- Phase 4: US2 — 4 задачи (T021-T024)
- Phase 5: US3 — 4 задачи (T025-T028)
- Phase 6: US4 — 3 задачи (T029-T031)
- Phase 7: US5 — 4 задачи (T032-T035)
- Phase 8: Polish — 6 задач (T036-T041)

**Organization**: Задачи сгруппированы по user story для независимой реализации и тестирования каждого сценария.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Может выполняться параллельно (разные файлы, нет зависимостей от незавершённых задач)
- **[Story]**: К какому user story принадлежит задача (например, US1, US2, US3)
- Включать полные пути к файлам в описании

## Path Conventions

- **Ansible роль**: `roles/ssd_rootfs/`
- **Playbooks**: `playbooks/`
- **Документация**: `roles/ssd_rootfs/README.md`

---

## Phase 0: Manual Testing (Ручная верификация через SSH)

**Цель**: Проверить все команды на реальном хосте перед автоматизацией через Ansible

⚠️ **CRITICAL**: Эта фаза ДОЛЖНА быть завершена до начала написания любого Ansible кода

- [ ] T000 Подключиться по SSH к хосту leha (10.0.1.104) и проверить текущее состояние системы (lsblk, df -h)
- [ ] T001 [P] Выполнить lsblk для определения подключённых SSD устройств и их имён (/dev/sda, /dev/sdb)
- [ ] T002 [P] Проверить свободное место на SSD и текущее использование на microSD (df -h /)
- [ ] T003 [P] Проверить наличие необходимых утилит: which fdisk mkfs.ext4 rsync blkid
- [ ] T004 [P] Выполнить тестовое форматирование небольшого раздела или полный диск (потребуется подтверждение!)
- [ ] T005 [P] Протестировать rsync с опциями -axHAWX на небольшом тестовом наборе файлов
- [ ] T006 [P] Проверить текущее содержимое /etc/fstab и /boot/cmdline.txt для понимания текущей конфигурации
- [ ] T007 [P] Выполнить blkid для получения UUID раздела и сохранить его для последующего использования

**Checkpoint**: Все команды проверены вручную, понятен каждый шаг — можно начинать автоматизацию

---

## Phase 1: Setup (Общая инфраструктура)

**Цель**: Инициализация проекта и базовой структуры Ansible роли

- [ ] T008 Создать структуру директорий Ansible роли roles/ssd_rootfs/{tasks,defaults,handlers,meta,templates}
- [ ] T009 Создать roles/ssd_rootfs/defaults/main.yml с переменными по умолчанию (ssd_device: auto, ssd_mount_point: /mnt/ssd)
- [ ] T010 Создать roles/ssd_rootfs/meta/main.yml с метаданными роли (описание, автор, зависимости)
- [ ] T011 Создать roles/ssd_rootfs/tasks/main.yml с точкой входа в роль
- [ ] T012 [P] Создать roles/ssd_rootfs/handlers/main.yml для обработчиков событий

**Checkpoint**: Структура роли готова, можно начинать разработку задач

---

## Phase 2: Foundational (Блокирующие пререквизиты)

**Цель**: Базовая функциональность, необходимая для ВСЕХ user stories

⚠️ **CRITICAL**: Ни одна user story не может быть реализована до завершения этой фазы

- [ ] T013 Реализовать roles/ssd_rootfs/tasks/detect_ssd.yml для обнаружения SSD среди блочных устройств (lsblk)
- [ ] T014 [P] Реализовать roles/ssd_rootfs/tasks/check_space.yml для проверки свободного места на SSD
- [ ] T015 [P] Реализовать роли в roles/ssd_rootfs/tasks/check_prerequisites.yml для проверки наличия утилит (fdisk, mkfs.ext4, rsync, blkid)
- [ ] T016 Создать fact для хранения SSD UUID и использовать его в последующих задачах

**Checkpoint**: Foundation готова — реализация user stories может начаться параллельно

---

## Phase 3: User Story 1 - Подготовка SSD к использованию (Priority: P1) 🎯 MVP

**Цель**: SSD автоматически определяется, инициализируется и форматируется в ext4

**Independent Test**: После выполнения роль должна сообщить что SSD отформатирован и готов к использованию, можно проверить через `lsblk` и `df -h`

### Implementation for User Story 1

- [ ] T017 Реализовать роли в roles/ssd_rootfs/tasks/confirm_format.yml для запроса подтверждения если SSD содержит данные
- [ ] T018 [P] [US1] Реализовать roles/ssd_rootfs/tasks/prepare_ssd.yml с разметкой GPT через fdisk
- [ ] T019 [P] [US1] Реализовать форматирование в ext4 с опцией noatime в roles/ssd_rootfs/tasks/prepare_ssd.yml
- [ ] T020 [P] [US1] Добавить получение UUID раздела через blkid и сохранение в fact

**Checkpoint**: В этот точке User Story 1 должен быть полностью функционален и тестируем независимо

---

## Phase 4: User Story 2 - Перенос корневой файловой системы (Priority: P1)

**Цель**: rootfs копируется с microSD на SSD с сохранением всех атрибутов

**Independent Test**: После выполнения `df -h` показывает что корень `/` на SSD (`/dev/sdX1`), а `/boot` остаётся на microSD (`/dev/mmcblk0p1`)

### Implementation for User Story 2

- [ ] T021 [P] [US2] Реализовать монтирование SSD в roles/ssd_rootfs/tasks/mount_ssd.yml (mount to {{ ssd_mount_point }})
- [ ] T022 [US2] Реализовать roles/ssd_rootfs/tasks/copy_rootfs.yml с rsync -axHAWX --info=progress2 для копирования /
- [ ] T023 [US2] Добавить прогресс бар для больших переносов в roles/ssd_rootfs/tasks/copy_rootfs.yml
- [ ] T024 [US2] Добавить сохранение UUID в fact для использования в конфигурационных файлах в roles/ssd_rootfs/tasks/copy_rootfs.yml

**Checkpoint**: В этот точке User Stories 1 И 2 должны оба работать независимо

---

## Phase 5: User Story 3 - Настройка конфигурации для загрузки с SSD (Priority: P1)

**Цель**: Система автоматически загружается с SSD при каждом старте

**Independent Test**: После настройки содержимое `/mnt/ssd/etc/fstab` и `/boot/cmdline.txt` содержит UUID SSD раздела

### Implementation for User Story 3

- [ ] T025 [US3] Реализовать роли в roles/ssd_rootfs/tasks/update_fstab.yml для замены root mount на UUID в /mnt/ssd/etc/fstab
- [ ] T026 [US3] Добавить проверку что /boot mount остаётся на mmcblk0p1 в roles/ssd_rootfs/tasks/update_fstab.yml
- [ ] T027 [US3] Реализовать роли в roles/ssd_rootfs/tasks/update_cmdline.yml для замены root= в /boot/cmdline.txt на root=UUID=
- [ ] T028 [US3] Добавить сохранение .backup копий оригинальных fstab и cmdline.txt в roles/ssd_rootfs/tasks/

**Checkpoint**: В этот точке User Stories 1, 2, 3 все работают независимо

---

## Phase 6: User Story 4 - Верификация успешного переноса (Priority: P2)

**Цель**: Подтверждение что перенос прошёл успешно и система работает с SSD

**Independent Test**: Проверить что корень смонтирован с SSD и система работает стабильно

### Implementation for User Story 4

- [ ] T029 [P] [US4] Реализовать roles/ssd_rootfs/tasks/verify.yml для сравнения размера до/после копирования
- [ ] T030 [P] [US4] Добавить проверку ключевых системных файлов в roles/ssd_rootfs/tasks/verify.yml
- [ ] T031 [US4] Реализовать unmount SSD в roles/ssd_rootfs/tasks/cleanup.yml

**Checkpoint**: В этот точке все User Stories (1-4) должны работать независимо

---

## Phase 7: User Story 5 - Интеграция с существующими Ansible ролями (Priority: P2)

**Цель**: Роль соответствует структуре проекта и работает совместно с другими ролями

**Independent Test**: Выполнить роль из другого playbook или совместно с другими ролями — она должна корректно работать

### Implementation for User Story 5

- [ ] T032 [P] [US5] Создать playbooks/ssd-migrate.yml для запуска роли ssd_rootfs
- [ ] T033 [US5] Добавить пример использования в roles/ssd_rootfs/README.md с переменными
- [ ] T034 [US5] Добавить проверку идемпотентности в roles/ssd_rootfs/tasks/detect_ssd.yml (проверить что / уже на SSD)
- [ ] T035 [US5] Реализовать пропуск destructive operations если перенос уже выполнен в roles/ssd_rootfs/tasks/

**Checkpoint**: Все user stories независимо функциональны

---

## Phase 8: Polish & Cross-Cutting Concerns

**Цель**: Улучшения влияющие на множество user stories

- [ ] T036 [P] Создать roles/ssd_rootfs/README.md с описанием, переменными, примерами использования
- [ ] T037 [P] Добавить подробные коментарии в задачи для будущих разработчиков
- [ ] T038 [P] Создать playbooks/verify-ssd.yml для проверки состояния после переноса
- [ ] T039 Протестировать роль на хосте leha (10.0.1.104) с фактическим переносом системы
- [ ] T040 Обновить Todo.md отметив задачу по рефакторингу в Ansible роли выполненной
- [ ] T041 [P] Добавить recommendation в конце роли с сообщением о необходимости ручной перезагрузки

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Нет зависимостей — можно начинать немедленно
- **Foundational (Phase 2)**: Зависит от завершения Setup — БЛОКИРУЕТ все user stories
- **User Stories (Phase 3-7)**: Все зависят от завершения Foundational phase
  - User stories могут выполняться параллельно (если есть ресурсы)
  - Или последовательно в порядке приоритета (P1 → P2 → P3)
- **Polish (Phase 8)**: Зависит от завершения всех желаемых user stories

### User Story Dependencies

- **User Story 1 (P1)**: Может начаться после Foundational (Phase 2) — нет зависимостей от других stories
- **User Story 2 (P1)**: Может начаться после Foundational (Phase 2) — должна интегрироваться с US1
- **User Story 3 (P1)**: Может начаться после Foundational (Phase 2) — должна интегрироваться с US1
- **User Story 4 (P2)**: Может начаться после Foundational (Phase 2) — зависит от US2 (требует скопированную систему)
- **User Story 5 (P2)**: Может начаться после Foundational (Phase 2) — может интегрироваться с US1-US4

### Within Each User Story

- Модульные задачи (mark [P]) внутри story могут выполняться параллельно
- Зависимые задачи должны выполняться последовательно
- Story завершён перед переходом к следующей (для последовательной стратегии)

### Parallel Opportunities

- Все Setup задачи (Phase 1) отмеченные [P] могут выполняться параллельно
- Все Foundational задачи (Phase 2) отмеченные [P] могут выполняться параллельно (внутри Phase 2)
- После завершения Foundational phase все user stories могут начаться параллельно (если позволяет команда)
- Все задачи внутри user story отмеченные [P] могут выполняться параллельно
- Разные user stories могут разрабатываться параллельно разными участниками команды

---

## Parallel Example: User Story 1

```bash
# Запуск всех задач параллельно для User Story 1:
T017: confirm_format.yml
T018: prepare_ssd.yml (GPT разметка)
T019: prepare_ssd.yml (форматирование ext4)
T020: prepare_ssd.yml (получение UUID)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Завершить Phase 1: Setup
2. Завершить Phase 2: Foundational (CRITICAL — блокирует все stories)
3. Завершить Phase 3: User Story 1
4. **ОСТАНОВИТЬСЯ И ВЕРИФИЦИРОВАТЬ**: Протестировать User Story 1 независимо
5. Развернуть/продемонстрировать если готово

### Incremental Delivery

1. Завершить Setup + Foundational → Foundation ready
2. Добавить User Story 1 → Протестировать независимо → Deploy/Demo (MVP!)
3. Добавить User Story 2 → Протестировать независимо → Deploy/Demo
4. Добавить User Story 3 → Протестировать независимо → Deploy/Demo
5. Добавить User Story 4 → Протестировать независимо → Deploy/Demo
6. Добавить User Story 5 → Протестировать независимо → Deploy/Demo
7. Каждая story добавляет ценность не ломая предыдущие

### Parallel Team Strategy

С несколькими разработчиками:

1. Команда завершает Setup + Foundational вместе
2. После завершения Foundational:
   - Developer A: User Story 1
   - Developer B: User Story 2
   - Developer C: User Story 3
3. Stories завершаются и интегрируются независимо

---

## Notes

- [P] задачи = разные файлы, нет зависимостей
- [Story] label связывает задачу с конкретным user story для traceability
- Каждая user story должна быть независимо завершаемой и тестируемой
- Коммитить после каждой задачи или логической группы задач
- Остановиться на любом checkpoint для валидации story независимо
- Избегать: размытые задачи, конфликты файлов, cross-story зависимости что нарушают независимость
