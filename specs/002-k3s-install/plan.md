# Implementation Plan: Установка K3s на Raspberry Pi стеке

**Branch**: `002-k3s-install` | **Date**: 2026-02-15 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/002-k3s-install/spec.md`

## Summary

Развёртывание K3s кластера на Raspberry Pi стеке в три этапа: (1) ручная установка K3s server на leha (control plane), (2) ручное подключение sema как worker-узла, (3) создание Ansible ролей для автоматизации. Используется Flannel CNI, базовая сетевая безопасность, управление с Mac через отдельный kubeconfig файл. Референсная реализация из проекта k8s-study адаптируется под Raspberry Pi ARM64.

## Technical Context

**Language/Version**: Ansible 2.x, YAML, Bash (скрипты установки/верификации)
**Primary Dependencies**: K3s (фиксированная версия в group_vars), kubectl, Ansible
**Storage**: SQLite (встроенное хранилище K3s для single-server), local-path-provisioner (default StorageClass)
**Testing**: ansible-lint, ansible-playbook --check (dry-run), verify-k3s.sh (скрипт верификации кластера)
**Target Platform**: Raspberry Pi OS (Debian-based), arm64/aarch64, Pi 4 (8GB) и Pi 5 (8GB)
**Project Type**: Infrastructure as Code (Ansible roles + playbooks)
**Performance Goals**: K3s idle <1GB RAM/node, pod запуск <2 мин, перезагрузка узла <3 мин возврат в Ready
**Constraints**: arm64 only, домашняя сеть 10.0.1.0/24, API-сервер только на локальной сети, существующий ~/.kube/config не трогать
**Scale/Scope**: 2 узла (leha + sema) начально, до 4 узлов (+ motya, osya) в будущем

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Принцип | Статус | Как обеспечивается |
|---------|--------|--------------------|
| Идемпотентность (Ansible) | PASS | FR-013: все роли идемпотентны, проверка состояния перед изменением |
| Одна роль = одна ответственность | PASS | 4 роли: k3s_prerequisites, k3s_server, k3s_agent, k3s_uninstall |
| Секреты не в репозитории | PASS | Cluster token генерируется в runtime, не хранится в git |
| Тестирование (lint, check, verify) | PASS | ansible-lint + --check + verify-k3s.sh скрипт |
| ARM архитектура | PASS | FR-001: arm64/aarch64 на Pi 4 и Pi 5 |
| Минимизация ресурсов | PASS | FR-006: Traefik и ServiceLB отключены |
| Мониторинг температуры | PASS | US4: скрипт диагностики включает температуру |
| Kubernetes resources/limits | PASS | Будет в будущих deployments |
| Переменные в defaults/ | PASS | Все настраиваемые параметры в defaults/main.yml каждой роли |

**Нарушений нет. Gate пройден.**

## Project Structure

### Documentation (this feature)

```text
specs/002-k3s-install/
├── spec.md              # Спецификация (готова)
├── plan.md              # Этот файл
├── research.md          # Phase 0: исследование и решения
├── data-model.md        # Phase 1: модель инфраструктуры
├── quickstart.md        # Phase 1: быстрый старт и верификация
└── checklists/
    └── requirements.md  # Чеклист качества спецификации
```

### Source Code (repository root)

```text
roles/
├── k3s_prerequisites/          # Подготовка хостов для K3s
│   ├── tasks/main.yml          # Модули ядра, sysctl, swap, пакеты
│   ├── defaults/main.yml       # Дефолтные переменные
│   └── handlers/main.yml       # Хэндлеры перезагрузки
├── k3s_server/                 # Установка K3s server (control plane)
│   ├── tasks/main.yml          # Установка K3s, ожидание API, kubeconfig
│   ├── defaults/main.yml       # k3s_version, server flags
│   ├── handlers/main.yml       # Restart k3s
│   └── templates/
│       └── k3s-config.yaml.j2  # Конфигурация сервера
├── k3s_agent/                  # Установка K3s agent (worker)
│   ├── tasks/main.yml          # Установка agent, присоединение к кластеру
│   ├── defaults/main.yml       # Agent flags
│   └── handlers/main.yml       # Restart k3s-agent
└── k3s_uninstall/              # Удаление K3s (P5, в последнюю очередь)
    ├── tasks/main.yml          # Вызов uninstall скриптов, очистка
    └── defaults/main.yml       # Настройки очистки

group_vars/
├── all.yml                     # Добавить: k3s_version
├── k3s_server.yml              # Новый: переменные control plane
└── k3s_agent.yml               # Новый: переменные worker nodes

k3s-install.yml                 # Главный playbook установки K3s
k3s-uninstall.yml               # Playbook удаления K3s
scripts/
└── verify-k3s.sh               # Скрипт верификации кластера
```

**Structure Decision**: Ansible roles в директории `roles/` по стандартной структуре проекта. Каждая роль следует принципу "одна ответственность" из constitution. Переменные в `group_vars/` для кластерных настроек. Инвентарь расширяется группами `k3s_server` и `k3s_agent`.

## Implementation Phases

### Phase 1: Ручная установка K3s server на leha (US1)

**Предусловия и критерии проверки перед началом:**
```bash
# 1. SSH доступ
ssh dog@10.0.1.104 "echo OK"

# 2. Архитектура
ssh dog@10.0.1.104 "uname -m"  # Ожидается: aarch64

# 3. Свободное место
ssh dog@10.0.1.104 "df -h / | tail -1"  # Минимум 2GB свободно

# 4. Сеть
ssh dog@10.0.1.104 "ip addr show eth0 | grep 10.0.1.104"
```

**Шаги:**

1. **Подготовка хоста** (prerequisites):
   - Отключить swap: `sudo swapoff -a`, удалить из fstab
   - Загрузить модули ядра: overlay, br_netfilter
   - Настроить sysctl: ip_forward, bridge-nf-call-iptables
   - Обновить setup-cluster.yml (swappiness=10 → 0)

2. **Установка K3s server:**
   ```bash
   curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="<version>" \
     sh -s - server \
     --bind-address=10.0.1.104 \
     --advertise-address=10.0.1.104 \
     --disable=traefik \
     --disable=servicelb \
     --write-kubeconfig-mode=0600
   ```

3. **Верификация:**
   ```bash
   sudo kubectl get nodes           # leha Ready
   sudo kubectl get pods -A         # Все системные поды Running
   sudo cat /var/lib/rancher/k3s/server/node-token  # Сохранить токен
   ```

4. **Копирование kubeconfig на Mac:**
   - Скопировать /etc/rancher/k3s/k3s.yaml как ~/.kube/rpi-k3s.yaml
   - Заменить 127.0.0.1 → 10.0.1.104
   - Использовать: `KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl get nodes`

**Критерии успеха Phase 1:**
- `kubectl get nodes` → leha Ready
- `kubectl get pods -A` → все поды Running
- `kubectl get nodes` работает с Mac через rpi-k3s.yaml
- K3s автозапуск после reboot

### Phase 2: Подключение sema как worker (US2)

**Предусловия:**
```bash
# Phase 1 выполнена
KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl get nodes  # leha Ready

# sema доступна
ssh dog@10.0.1.33 "echo OK"

# Сетевая связность к API
ssh dog@10.0.1.33 "nc -zv 10.0.1.104 6443"
```

**Шаги:**

1. **Подготовка sema** (те же prerequisites что и leha)

2. **Получить токен с leha:**
   ```bash
   ssh dog@10.0.1.104 "sudo cat /var/lib/rancher/k3s/server/node-token"
   ```

3. **Установка K3s agent на sema:**
   ```bash
   curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="<version>" \
     K3S_URL=https://10.0.1.104:6443 \
     K3S_TOKEN="<token>" \
     sh -s - agent
   ```

4. **Верификация:**
   ```bash
   KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl get nodes  # leha + sema Ready
   KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl run test --image=nginx:alpine --restart=Never
   KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl get pods    # test Running
   KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl delete pod test
   ```

**Критерии успеха Phase 2:**
- `kubectl get nodes` → leha Ready, sema Ready
- Тестовый pod nginx запускается и удаляется
- После reboot sema — автоматическое подключение к кластеру

### Phase 3: Ansible роли (US3)

**Предусловия:**
- Phase 1 и 2 успешно выполнены
- Процесс ручной установки задокументирован
- Все переменные и параметры известны

**Шаги:**

1. **Обновить setup-cluster.yml**: swappiness=10 → swappiness=0, добавить swapoff

2. **Обновить inventory.yml**: добавить группы k3s_server и k3s_agent
   ```yaml
   k3s_server:
     hosts:
       leha:
   k3s_agent:
     hosts:
       sema:
   ```

3. **Создать group_vars:**
   - `group_vars/all.yml` — добавить k3s_version
   - `group_vars/k3s_server.yml` — server flags, bind-address
   - `group_vars/k3s_agent.yml` — server URL, token retrieval

4. **Создать роль k3s_prerequisites:**
   - Модули ядра (overlay, br_netfilter)
   - Sysctl (ip_forward, bridge-nf-call-iptables)
   - Swap полное отключение
   - Необходимые пакеты (curl, ca-certificates)

5. **Создать роль k3s_server:**
   - Проверка: K3s уже установлен?
   - Установка K3s server с флагами из переменных
   - Ожидание готовности API (до 5 минут)
   - Извлечение cluster token для agent-узлов
   - Настройка kubeconfig (chmod 600)

6. **Создать роль k3s_agent:**
   - Получение token с server-узла
   - Установка K3s agent
   - Ожидание регистрации узла (до 5 минут)

7. **Создать playbook k3s-install.yml:**
   ```yaml
   - name: Prepare hosts for K3s
     hosts: k3s_server:k3s_agent
     roles: [k3s_prerequisites]

   - name: Install K3s server
     hosts: k3s_server
     roles: [k3s_server]

   - name: Install K3s agents
     hosts: k3s_agent
     roles: [k3s_agent]
   ```

8. **Тестирование:**
   - ansible-lint k3s-install.yml
   - ansible-playbook --check k3s-install.yml (dry-run)
   - Полный запуск на хостах (после предварительного удаления ручной установки)
   - Повторный запуск — проверка идемпотентности

**Критерии успеха Phase 3:**
- ansible-lint проходит без ошибок
- Playbook разворачивает кластер за один запуск
- Повторный запуск — 0 changed
- `kubectl get nodes` — все узлы Ready

### Phase 4: Верификация и диагностика (US4)

**Шаги:**

1. **Создать scripts/verify-k3s.sh:**
   - Проверка 1: Все узлы в статусе Ready
   - Проверка 2: Системные поды (coredns, local-path-provisioner, metrics-server) Running
   - Проверка 3: Сетевая связность между узлами (Flannel overlay)
   - Проверка 4: Тестовый pod запускается и удаляется
   - Проверка 5: Температура CPU на каждом узле
   - Выход: PASS/FAIL с деталями

2. **Добавить в Makefile:**
   - `make k3s-verify` — запуск verify-k3s.sh
   - `make k3s-status` — быстрый kubectl get nodes + pods

**Критерии успеха Phase 4:**
- Скрипт выдаёт PASS на здоровом кластере
- Скрипт выдаёт FAIL с конкретной причиной при проблемах

### Phase 5: Ansible роль удаления K3s (US5, последний приоритет)

**Шаги:**

1. **Создать роль k3s_uninstall:**
   - Определение типа узла (server/agent)
   - Вызов соответствующего скрипта: k3s-uninstall.sh или k3s-agent-uninstall.sh
   - Очистка: /etc/rancher, /var/lib/rancher, sysctl, модули ядра
   - Удаление kubeconfig с Mac (опционально)

2. **Создать playbook k3s-uninstall.yml**

**Критерии успеха Phase 5:**
- Полное удаление K3s с хоста
- Повторная установка проходит без конфликтов

## Risks & Mitigations

| Риск | Вероятность | Влияние | Митигация |
|------|-------------|---------|-----------|
| K3s не запускается на Pi 5 (новое железо) | Низкая | Высокое | Ручная установка первой (Phase 1) выявит проблемы до автоматизации |
| Перезапись существующего kubeconfig | Низкая | **Критическое** | FR-010a: отдельный файл rpi-k3s.yaml, никогда не трогать ~/.kube/config |
| Нехватка RAM при запуске K3s | Низкая | Среднее | Pi 5 8GB достаточно; Traefik/ServiceLB отключены; мониторинг RAM в verify-k3s.sh |
| Потеря сети между узлами | Средняя | Среднее | Flannel VXLAN устойчив к кратковременным потерям; agent автопереподключение |
| Конфликт swap настроек | Решено | - | setup-cluster.yml обновлён: swappiness=0, swapoff -a |

## Complexity Tracking

Нарушений constitution нет. Таблица не требуется.
