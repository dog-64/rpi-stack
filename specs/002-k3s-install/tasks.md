# Tasks: Установка K3s на Raspberry Pi стеке

**Input**: Design documents from `/specs/002-k3s-install/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/ansible-roles-contract.yml, quickstart.md

**Tests**: В спецификации не запрошены тестовые задачи. Верификация выполняется через quickstart.md сценарии.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- Ansible roles: `roles/<role_name>/`
- Playbooks: repository root (`*.yml`)
- Group variables: `group_vars/*.yml`
- Scripts: `scripts/`

---

## Phase 1: Setup (Подготовка проекта)

**Purpose**: Создание базовой структуры для Ansible ролей и documentation

- [X] T001 Создать директорию structure для Ansible ролей K3s в `roles/k3s_prerequisites/`, `roles/k3s_server/`, `roles/k3s_agent/`, `roles/k3s_uninstall/`
- [X] T002 [P] Создать структуру директорий для роли k3s_prerequisites: `tasks/`, `handlers/`, `defaults/`, `meta/`
- [X] T003 [P] Создать структуру директорий для роли k3s_server: `tasks/`, `handlers/`, `defaults/`, `templates/`, `meta/`
- [X] T004 [P] Создать структуру директорий для роли k3s_agent: `tasks/`, `handlers/`, `defaults/`, `meta/`
- [X] T005 [P] Создать структуру директорий для роли k3s_uninstall: `tasks/`, `defaults/`, `meta/`
- [X] T006 [P] Создать директорию `scripts/` для скриптов верификации
- [X] T007 Создать пустой файл `scripts/verify-k3s.sh` с заголовком shebang

**Checkpoint**: ✅ Структура проекта готова для реализации

---

## Phase 2: Foundational (Блокирующие предусловия)

**Purpose**: Критические изменения, которые должны быть завершены ДО начала любой User Story

**⚠️ CRITICAL**: Ни одна User Story не может начаться до завершения этой фазы

- [X] T008 Обновить `playbooks/setup-cluster.yml`: изменить vm.swappiness с 10 на 0 в sysctl задачах
- [X] T009 Добавить задачу полного отключения swap в `playbooks/setup-cluster.yml`: swapoff -a, удаление из fstab, disable dphys-swapfile
- [X] T010 Обновить inventory: добавить группу `k3s_server` с хостом leha в `inventory.yml` (или соответствующем inventory файле проекта)
- [X] T011 Обновить inventory: добавить группу `k3s_agent` с хостом sema в `inventory.yml`
- [X] T012 Создать `group_vars/all.yml`: добавить переменную k3s_version (placeholder, будет обновлена после ручной установки)
- [X] T013 [P] Создать `group_vars/k3s_server.yml` с переменными: k3s_server_bind_address, k3s_server_advertise_address, k3s_server_disable, k3s_kubeconfig_mode
- [X] T014 [P] Создать `group_vars/k3s_agent.yml` с переменными: k3s_server_url, k3s_agent_extra_args

**Checkpoint**: ✅ Foundation ready - можно начинать выполнение User Story 1

---

## Phase 3: User Story 1 - Ручная установка K3s server на leha (Priority: P1) 🎯 MVP

**Goal**: Установить K3s в режиме server на хосте leha (control plane), обеспечить доступ к кластеру с Mac через отдельный kubeconfig

**Independent Test**:
```bash
# С leha:
sudo kubectl get nodes  # → leha Ready

# С Mac:
KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl get nodes  # → leha Ready
```

### Implementation for User Story 1

- [ ] T015 [US1] Подключиться к leha по SSH и выполнить pre-flight checks в `specs/002-k3s-install/checklists/us1-preflight.txt`: архитектура arm64, свободное место >2GB, IP 10.0.1.104
- [ ] T016 [US1] Подготовить leha: отключить swap (swapoff -a), удалить записи swap из /etc/fstab, disable dphys-swapfile
- [ ] T017 [US1] Загрузить модули ядра на leha: overlay, br_netfilter, сохранить в /etc/modules-load.d/k3s.conf
- [ ] T018 [US1] Настроить sysctl параметры на leha: net.bridge.bridge-nf-call-iptables=1, net.ipv4.ip_forward=1, сохранить в /etc/sysctl.d/k3s.conf, применить через sysctl --system
- [ ] T019 [US1] Определить актуальную версию K3s для arm64 (проверить https://github.com/k3s-io/k3s/releases), записать в заметки для последующего использования в group_vars
- [ ] T020 [US1] Установить K3s server на leha через curl -sfL https://get.k3s.io с флагами: --bind-address=10.0.1.104, --advertise-address=10.0.1.104, --disable=traefik, --disable=servicelb, --write-kubeconfig-mode=0600, INSTALL_K3S_VERSION=<версия>
- [ ] T021 [US1] Верифицировать установку K3s server на leha: проверить systemctl status k3s, kubectl get nodes (должен показать leha Ready), kubectl get pods -A (все системные поды Running)
- [ ] T022 [US1] Извлечь cluster token с leha: sudo cat /var/lib/rancher/k3s/server/node-token, сохранить в безопасном месте для US2
- [ ] T023 [US1] Скопировать kubeconfig с leha на Mac: scp dog@10.0.1.104:/etc/rancher/k3s/k3s.yaml ~/.kube/rpi-k3s.yaml
- [ ] T024 [US1] Заменить server адрес в kubeconfig на Mac: sed -i '' 's/127.0.0.1/10.0.1.104/g' ~/.kube/rpi-k3s.yaml
- [ ] T025 [US1] Проверить права доступа на kubeconfig: chmod 600 ~/.kube/rpi-k3s.yaml
- [ ] T026 [US1] Верифицировать удалённое управление с Mac: KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl get nodes, KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl get pods -A
- [ ] T027 [US1] Обновить `group_vars/all.yml`: установить k3s_version в фактически установленную версию (например, v1.31.4+k3s1)
- [ ] T028 [US1] Документировать ручную установку в `specs/002-k3s-install/manual-install-notes.md`: все команды, версии, обнаруженные проблемы

**Checkpoint**: User Story 1 завершена - K3s server работает на leha, управление с Mac через отдельный kubeconfig работает

---

## Phase 4: User Story 2 - Подключение sema как worker-узла (Priority: P2)

**Goal**: Подключить хост sema к кластеру как K3s agent (worker), создать 2-узловой кластер

**Independent Test**:
```bash
KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl get nodes
# Ожидается: leha Ready, sema Ready
```

### Implementation for User Story 2

- [ ] T029 [US2] Подключиться к sema по SSH и выполнить pre-flight checks: архитектура arm64, свободное место >2GB, сетевая связность к leha (nc -zv 10.0.1.104 6443)
- [ ] T030 [US2] Подготовить sema: отключить swap (swapoff -a), удалить записи swap из /etc/fstab, disable dphys-swapfile
- [ ] T031 [US2] Загрузить модули ядра на sema: overlay, br_netfilter, сохранить в /etc/modules-load.d/k3s.conf
- [ ] T032 [US2] Настроить sysctl параметры на sema: net.bridge.bridge-nf-call-iptables=1, net.ipv4.ip_forward=1, сохранить в /etc/sysctl.d/k3s.conf, применить через sysctl --system
- [ ] T033 [US2] Получить cluster token (используя значение из T022 или перечитать с leha): ssh dog@10.0.1.104 "sudo cat /var/lib/rancher/k3s/server/node-token"
- [ ] T034 [US2] Установить K3s agent на sema через curl -sfL https://get.k3s.io с переменными: INSTALL_K3S_VERSION=<версия из group_vars>, K3S_URL=https://10.0.1.104:6443, K3S_TOKEN=<токен>
- [ ] T035 [US2] Верифицировать установку K3s agent на sema: проверить systemctl status k3s-agent
- [ ] T036 [US2] Верифицировать регистрацию sema в кластере с Mac: KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl get nodes (должен показать leha Ready, sema Ready)
- [ ] T037 [US2] Запустить тестовый pod для проверки кластера: KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl run test-nginx --image=nginx:alpine --restart=Never
- [ ] T038 [US2] Дождаться Ready статуса тестового pod: KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl wait --for=condition=Ready pod/test-nginx --timeout=120s
- [ ] T039 [US2] Удалить тестовый pod: KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl delete pod test-nginx
- [ ] T040 [US2] Документировать подключение worker в `specs/002-k3s-install/worker-join-notes.md`

**Checkpoint**: User Story 2 завершена - 2-узловой кластер работает, тестовый pod успешно запускается

---

## Phase 5: User Story 3 - Создание Ansible ролей для автоматизации (Priority: P3)

**Goal**: Создать идемпотентные Ansible роли для автоматической установки K3s на любом хосте стека

**Independent Test**:
```bash
# После удаления ручной установки и запуска playbook:
ansible-playbook k3s-install.yml
KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl get nodes  # → все узлы Ready

# Повторный запуск:
ansible-playbook k3s-install.yml  # → changed=0 (идемпотентность)
```

### Implementation for User Story 3

#### Role: k3s_prerequisites

- [ ] T041 [P] [US3] Создать `roles/k3s_prerequisites/defaults/main.yml` с переменными: k3s_kernel_modules, k3s_sysctl_params, k3s_disable_swap, k3s_required_packages
- [ ] T042 [P] [US3] Создать `roles/k3s_prerequisites/tasks/main.yml`: задача установки требуемых пакетов (curl, ca-certificates)
- [ ] T043 [US3] Создать задачу в `roles/k3s_prerequisites/tasks/main.yml`: загрузка модулей ядра из переменной k3s_kernel_modules, сохранение в /etc/modules-load.d/k3s.conf, modprobe
- [ ] T044 [US3] Создать задачу в `roles/k3s_prerequisites/tasks/main.yml`: применение sysctl параметров из переменной k3s_sysctl_params, сохранение в /etc/sysctl.d/k3s.conf, sysctl --system
- [ ] T045 [US3] Создать задачу в `roles/k3s_prerequisites/tasks/main.yml`: отключение swap (swapoff -a), удаление записей из /etc/fstab, systemctl disable dphys-swapfile (с проверкой существования)
- [ ] T046 [P] [US3] Создать `roles/k3s_prerequisites/meta/main.yml`: метаданные роли, зависимость от ansible.posix для модуля mount

#### Role: k3s_server

- [ ] T047 [P] [US3] Создать `roles/k3s_server/defaults/main.yml` с переменными: k3s_version, k3s_server_bind_address, k3s_server_advertise_address, k3s_server_disable, k3s_kubeconfig_mode
- [ ] T048 [US3] Создать `roles/k3s_server/tasks/main.yml`: проверка наличия установленного K3s (идемпотентность - пропуск если уже установлен той же версии)
- [ ] T049 [US3] Создать задачу в `roles/k3s_server/tasks/main.yml`: загрузка и установка K3s server через curl с флагами из переменных, INSTALL_K3S_VERSION
- [ ] T050 [US3] Создать задачу в `roles/k3s_server/tasks/main.yml`: ожидание готовности API-сервера (до 5 минут, проверка через kubectl или port 6443)
- [ ] T051 [US3] Создать задачу в `roles/k3s_server/tasks/main.yml`: извлечение cluster token через slurp или fetch для передачи в k3s_agent роль
- [ ] T052 [P] [US3] Создать `roles/k3s_server/handlers/main.yml`: handler для перезапуска k3s.service при изменении конфигурации
- [ ] T053 [P] [US3] Создать `roles/k3s_server/templates/k3s-config.yaml.j2` (шаблон конфигурации, если требуется для кастомных настроек)
- [ ] T054 [P] [US3] Создать `roles/k3s_server/meta/main.yml`: метаданные роли, зависимость от k3s_prerequisites

#### Role: k3s_agent

- [ ] T055 [P] [US3] Создать `roles/k3s_agent/defaults/main.yml` с переменными: k3s_version, k3s_server_url, k3s_token (placeholder, будет получена из k3s_server), k3s_agent_extra_args
- [ ] T056 [US3] Создать `roles/k3s_agent/tasks/main.yml`: получение cluster token с server-узла через hostvars (delegate_to: k3s_server group)
- [ ] T057 [US3] Создать задачу в `roles/k3s_agent/tasks/main.yml`: проверка наличия установленного K3s agent (идемпотентность)
- [ ] T058 [US3] Создать задачу в `roles/k3s_agent/tasks/main.yml`: установка K3s agent через curl с переменными K3S_URL, K3S_TOKEN, INSTALL_K3S_VERSION
- [ ] T059 [US3] Создать задачу в `roles/k3s_agent/tasks/main.yml`: ожидание регистрации узла в кластере (до 5 минут, проверка через kubectl get nodes с server)
- [ ] T060 [P] [US3] Создать `roles/k3s_agent/handlers/main.yml`: handler для перезапуска k3s-agent.service
- [ ] T061 [P] [US3] Создать `roles/k3s_agent/meta/main.yml`: метаданные роли, зависимость от k3s_prerequisites

#### Playbook: k3s-install.yml

- [ ] T062 [US3] Создать `k3s-install.yml` playbook: первый play - подготовка хостов (hosts: k3s_server:k3s_agent, role: k3s_prerequisites)
- [ ] T063 [US3] Добавить второй play в `k3s-install.yml`: установка K3s server (hosts: k3s_server, role: k3s_server)
- [ ] T064 [US3] Добавить третий play в `k3s-install.yml`: установка K3s agents (hosts: k3s_agent, role: k3s_agent)
- [ ] T065 [US3] Документировать playbook в комментарии k3s-install.yml: описание, использование, требования к inventory

#### Testing & Validation

- [ ] T066 [US3] Запустить ansible-lint для проверки k3s-install.yml: ansible-lint k3s-install.yml (исправить все ошибки и предупреждения)
- [ ] T067 [US3] Запустить dry-run проверку: ansible-playbook --check k3s-install.yml (проверить синтаксис, не внося изменений)
- [ ] T068 [US3] Подготовить хосты для чистой установки: удалить ручную установку K3s с leha и sema (через k3s-uninstall.sh скрипты или вручную)
- [ ] T069 [US3] Выполнить полную установку через Ansible: ansible-playbook k3s-install.yml
- [ ] T070 [US3] Верифицировать кластер после установки: KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl get nodes, kubectl get pods -A
- [ ] T071 [US3] Проверить идемпотентность: повторный запуск ansible-playbook k3s-install.yml, убедиться что changed=0 для всех задач
- [ ] T072 [US3] Документировать использование Ansible ролей в `specs/002-k3s-install/ansible-usage.md`

**Checkpoint**: User Story 3 завершена - Ansible автоматизация работает, идемпотентность подтверждена

---

## Phase 6: User Story 4 - Валидация и диагностика кластера (Priority: P4)

**Goal**: Создать скрипт для быстрой диагностики состояния кластера (здоровье узлов, подов, сети, температура)

**Independent Test**:
```bash
./scripts/verify-k3s.sh
# Ожидается: PASS с деталями по всем проверкам
```

### Implementation for User Story 4

- [ ] T073 [P] [US4] Создать `scripts/verify-k3s.sh`: shebang, функции для цветного вывода (PASS/FAIL), переменные для KUBECONFIG
- [ ] T074 [US4] Добавить в `scripts/verify-k3s.sh` функцию check_nodes: kubectl get nodes, проверка что все узлы в статусе Ready
- [ ] T075 [US4] Добавить в `scripts/verify-k3s.sh` функцию check_system_pods: kubectl get pods -A, проверка что coredns, local-path-provisioner, metrics-server Running
- [ ] T076 [US4] Добавить в `scripts/verify-k3s.sh` функцию check_network: проверка сетевой связности между узлами (ping, nc -zv для портов 6443, 8472)
- [ ] T077 [US4] Добавить в `scripts/verify-k3s.sh` функцию check_test_pod: запуск тестового nginx pod, ожидание Ready, удаление
- [ ] T078 [US4] Добавить в `scripts/verify-k3s.sh` функцию check_temperature: проверка температуры CPU на каждом узле через vcgencmd measure_temp или /sys/class/thermal
- [ ] T079 [US4] Добавить в `scripts/verify-k3s.sh` функцию check_resources: проверка свободного места и RAM на каждом узле через df -h, free -h
- [ ] T080 [US4] Реализовать в `scripts/verify-k3s.sh` основную функцию main: последовательный вызов всех проверок, агрегация результатов, вывод summary с общим статусом PASS/FAIL
- [ ] T081 [US4] Сделать `scripts/verify-k3s.sh` исполняемым: chmod +x scripts/verify-k3s.sh
- [ ] T082 [US4] Добавить в Makefile цель k3s-verify: запуск scripts/verify-k3s.sh с правильным KUBECONFIG
- [ ] T083 [US4] Добавить в Makefile цель k3s-status: быстрый статус кластера (kubectl get nodes + kubectl get pods -A)
- [ ] T084 [US4] Протестировать `scripts/verify-k3s.sh` на здоровом кластере: убедиться что все проверки PASS
- [ ] T085 [US4] Протестировать `scripts/verify-k3s.sh` при проблемах: выключить один узел, убедиться что скрипт корректно показывает FAIL с указанием проблемы

**Checkpoint**: User Story 4 завершена - скрипт верификации работает, выдаёт чёткие PASS/FAIL статусы

---

## Phase 7: User Story 5 - Ansible роль удаления K3s (Priority: P5)

**Goal**: Создать Ansible роль для полного удаления K3s с хоста (для переустановки, отката, вывода узла из кластера)

**Independent Test**:
```bash
ansible-playbook k3s-uninstall.yml
# Хост: K3s процессы остановлены, бинарники удалены, данные очищены
# Повторная установка через k3s-install.yml проходит без конфликтов
```

### Implementation for User Story 5

- [ ] T086 [P] [US5] Создать `roles/k3s_uninstall/defaults/main.yml` с переменными: k3s_uninstall_cleanup_data, k3s_uninstall_cleanup_config
- [ ] T087 [US5] Создать `roles/k3s_uninstall/tasks/main.yml`: определение типа установленного K3s (server или agent) через проверку наличия systemd сервисов или файлов
- [ ] T088 [US5] Создать задачу в `roles/k3s_uninstall/tasks/main.yml`: остановка и отключение K3s service (systemctl stop, systemctl disable)
- [ ] T089 [US5] Создать задачу в `roles/k3s_uninstall/tasks/main.yml`: вызов соответствующего uninstall скрипта (k3s-uninstall.sh или k3s-agent-uninstall.sh) с проверкой существования
- [ ] T090 [US5] Создать задачу в `roles/k3s_uninstall/tasks/main.yml`: очистка /etc/rancher/k3s если k3s_uninstall_cleanup_config=true
- [ ] T091 [US5] Создать задачу в `roles/k3s_uninstall/tasks/main.yml`: очистка /var/lib/rancher/k3s если k3s_uninstall_cleanup_data=true
- [ ] T092 [US5] Создать задачу в `roles/k3s_uninstall/tasks/main.yml`: очистка модулей ядра из /etc/modules-load.d/k3s.conf
- [ ] T093 [US5] Создать задачу в `roles/k3s_uninstall/tasks/main.yml`: очистка sysctl параметров из /etc/sysctl.d/k3s.conf, перезагрузка sysctl
- [ ] T094 [US5] Создать задачу в `roles/k3s_uninstall/tasks/main.yml`: опциональное удаление kubeconfig с Mac (предупреждение перед удалением ~/.kube/rpi-k3s.yaml)
- [ ] T095 [P] [US5] Создать `roles/k3s_uninstall/meta/main.yml`: метаданные роли
- [ ] T096 [US5] Создать `k3s-uninstall.yml` playbook: первый play - удаление agents (hosts: k3s_agent, role: k3s_uninstall), второй play - удаление server (hosts: k3s_server, role: k3s_uninstall)
- [ ] T097 [US5] Протестировать полное удаление через k3s-uninstall.yml, затем повторную установку через k3s-install.yml (убедиться что нет конфликтов)

**Checkpoint**: User Story 5 завершена - роль удаления работает, переустановка проходит без конфликтов

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Финализация, документация, оптимизация

- [ ] T098 [P] Обновить README.md (если существует) или создать docs/k3s-setup.md с описанием установки K3s кластера
- [ ] T099 [P] Обновить CLAUDE.md: добавить информацию о K3s, kubectl, управлении кластером
- [ ] T100 [P] Создать docs/k3s-troubleshooting.md с типичными проблемами и решениями
- [ ] T101 [P] Добавить alias в .zshrc на рабочей станции (опционально): alias k3s-kubectl='KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl' для удобства
- [ ] T102 Выполнить полную валидацию по quickstart.md: все сценарии из раздела Verification должны проходить
- [ ] T103 Финальная проверка идемпотентности: на уже настроенном кластере ansible-playbook k3s-install.yml должен показать changed=0
- [ ] T104 Проверка constitution compliance: все роли следуют принципам из .github/spec-kit/constitution.md
- [ ] T105 Code review: убедиться что нет hardcoded значений, все переменные вынесены в defaults/main.yml или group_vars

---

## Dependencies & Execution Order

### Phase Dependencies

```
Setup (Phase 1)
    ↓
Foundational (Phase 2) ← БЛОКИРУЕТ все User Stories
    ↓
    ├─→ US1 (Phase 3) 🎯 MVP
    ├─→ US2 (Phase 4)
    ├─→ US3 (Phase 5)
    ├─→ US4 (Phase 6)
    └─→ US5 (Phase 7)
         ↓
Polish (Phase 8)
```

### User Story Dependencies

| User Story | Depends On | Can Start After |
|------------|------------|-----------------|
| US1 (P1) | Phase 2 (Foundational) | T014 завершена |
| US2 (P2) | US1, Phase 2 | T028 (US1 документация) завершена |
| US3 (P3) | US1, US2, Phase 2 | T040 (US2 документация) завершена |
| US4 (P4) | US3 | T072 (US3 тестирование) завершена |
| US5 (P5) | US3 | T072 (US3 тестирование) завершена |

**Примечание**: US4 и US5 могут выполняться параллельно после завершения US3

### Within Each User Story

- **US1**: T015-T020 последовательно (подготовка перед установкой), T021-T026 последовательно (верификация), T027-T028 последовательно (документация)
- **US2**: T029-T032 последовательно (подготовка sema), T033-T034 последовательно (установка agent), T035-T040 последовательно (верификация)
- **US3**: T041-T046 параллельно [P] (k3s_prerequisites), T047-T054 параллельно [P] (k3s_server), T055-T061 параллельно [P] (k3s_agent), T062-T072 последовательно (playbook и тестирование)
- **US4**: T073-T083 последовательно (разработка скрипта), T084-T085 последовательно (тестирование)
- **US5**: T086-T095 параллельно [P] (роль), T096-T097 последовательно (playbook и тестирование)

### Parallel Opportunities

**Setup (Phase 1):** T002, T003, T004, T005, T006 могут выполняться параллельно

**Foundational (Phase 2):** T013, T014 могут выполняться параллельно [P]

**US3 (Phase 5):**
- T041, T047, T055 — параллельно [P] (defaults/main.yml для разных ролей)
- T042-T046 (k3s_prerequisites) могут идти параллельно с T048-T054 (k3s_server) и T056-T061 (k3s_agent)
- T052, T053, T060 — параллельно [P] (handlers/meta для разных ролей)

**US5 (Phase 7):** T086, T095 — параллельно [P] (defaults/meta)

**Polish (Phase 8):** T098, T099, T100, T101 — параллельно [P]

---

## Parallel Example: User Story 3 (Ansible Roles)

```bash
# Параллельное создание defaults/main.yml для всех ролей:
Task T041: roles/k3s_prerequisites/defaults/main.yml
Task T047: roles/k3s_server/defaults/main.yml
Task T055: roles/k3s_agent/defaults/main.yml

# Параллельное создание meta/main.yml и handlers:
Task T046: roles/k3s_prerequisites/meta/main.yml
Task T052: roles/k3s_server/handlers/main.yml
Task T053: roles/k3s_server/templates/k3s-config.yaml.j2
Task T054: roles/k3s_server/meta/main.yml
Task T060: roles/k3s_agent/handlers/main.yml
Task T061: roles/k3s_agent/meta/main.yml
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

**Минимально работающий продукт:** Одноузловой кластер K3s на leha с управлением с Mac

1. Complete Phase 1: Setup (T001-T007)
2. Complete Phase 2: Foundational (T008-T014) — КРИТИЧЕСКИ
3. Complete Phase 3: User Story 1 (T015-T028)
4. **STOP and VALIDATE**: Проверить что K3s server работает, kubeconfig на Mac настроен
5. Demo: `KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl get nodes`

**MVP Value:** Уже можно запускать pod'ы на одном узле, учиться kubectl, deployments, services

### Incremental Delivery

| Increment | Tasks Added | Value Delivered |
|-----------|-------------|-----------------|
| **MVP** | Phase 1-3 (US1) | Одноузловой K3s, управление с Mac |
| **v2** | + US2 | Двухузловой кластер, распределение нагрузки |
| **v3** | + US3 | Полная автоматизация через Ansible |
| **v4** | + US4 | Диагностика и мониторинг кластера |
| **v5** | + US5 | Безопасное удаление и переустановка |

### Parallel Team Strategy

С несколькими разработчиками:

```
После завершения Phase 2 (Foundational):
   ├─ Developer A: US1 (T015-T028) — 1-2 часа
   ├─ Developer B: Ждёт завершения US1 → US2 (T029-T040) — 1-2 часа
   └─ Developer C: Ждёт завершения US2 → US3 (T041-T072) — 4-6 часов

После завершения US3:
   ├─ Developer A: US4 (T073-T085) — 2-3 часа
   └─ Developer B: US5 (T086-T097) — 2-3 часа
```

---

## Format Validation

Все 105 задач следуют обязательному формату:

✅ `- [ ] [TaskID] [P?] [Story?] Description with file path`

| Формат компонента | Статус |
|-------------------|--------|
| Checkbox `- [ ]` | ✅ Все задачи |
| Task ID (T001-T105) | ✅ Все задачи |
| [P] marker (там где применимо) | ✅ 20 задач с [P] |
| [Story] label (для US задач) | ✅ Все задачи в фазах 3-7 |
| File path в описании | ✅ Все задачи |
| Independent Test для US | ✅ Все 5 User Stories |

---

## Notes

- **[P] задачи** = разные файлы, нет зависимостей, можно выполнять параллельно
- **[Story] label** = привязка задачи к конкретной User Story для traceability
- **Каждая User Story** независимо завершаема и тестируема
- **Commit after each task or logical group** — коммитьте после каждой задачи или логической группы
- **Stop at any checkpoint** для проверки story независимо
- **KUBECONFIG** — всегда использовать ~/.kube/rpi-k3s.yaml, никогда не трогать ~/.kube/config
- **Идемпотентность** — критично для Ansible ролей, проверять через повторный запуск