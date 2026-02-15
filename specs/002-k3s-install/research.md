# Research: Установка K3s на Raspberry Pi стеке

**Date**: 2026-02-15
**Feature**: 002-k3s-install

## 1. K3s на Raspberry Pi ARM64

**Decision**: Использовать K3s (не полный Kubernetes, не K3d, не MicroK8s)

**Rationale**:
- K3s специально оптимизирован для ARM и edge-устройств
- Единый бинарник <100MB, минимальные требования к RAM
- Встроенный containerd, Flannel, CoreDNS, local-path-provisioner
- Проект k8s-study уже содержит проверенные Ansible роли для K3s
- Активная поддержка Rancher/SUSE, стабильные релизы для arm64

**Alternatives considered**:
- Full Kubernetes (kubeadm): слишком тяжёлый для Pi, ~2GB RAM только на control plane
- MicroK8s (Canonical): snap-based, проблемы с ARM64 на Pi OS
- K3d: требует Docker, дополнительный overhead, предназначен для dev/testing

## 2. CNI: Flannel vs Cilium

**Decision**: Flannel (vxlan backend) — встроенный в K3s

**Rationale**:
- Flannel встроен в K3s, не требует отдельной установки
- Потребление RAM: ~50MB vs ~300MB+ для Cilium
- Cilium требует eBPF, который менее стабилен на ARM64
- Для домашнего dev-кластера Flannel достаточен
- Документация k8s-study/docs/raspberry-pi-guide.md прямо рекомендует Flannel для Pi

**Alternatives considered**:
- Cilium: eBPF networking, Hubble observability, но слишком ресурсоёмкий для Pi (подтверждено в k8s-study)
- Calico: хороший вариант, но Flannel проще и уже встроен
- WireGuard backend: лучше производительность, но сложнее настройка, не нужно для домашней сети

## 3. Версия K3s

**Decision**: Фиксировать в group_vars/all.yml через переменную k3s_version

**Rationale**:
- Воспроизводимость: одна версия на всех узлах
- Контролируемые обновления: не будет неожиданных breaking changes
- Проект k8s-study использовал v1.28.5+k3s1 (для Proxmox)
- Для Pi нужна актуальная стабильная версия с хорошей ARM64 поддержкой
- Конкретная версия будет определена при ручной установке (Phase 1)

**Alternatives considered**:
- Всегда latest: удобно, но непредсказуемо
- Channel-based (stable): K3s поддерживает, но менее контролируемо чем явная версия

## 4. Безопасность кластера

**Decision**: Базовый уровень — привязка к локальной сети, ограничение прав

**Rationale**:
- Домашний dev/learning кластер, не production
- API-сервер привязан к 10.0.1.104 (не 0.0.0.0)
- kubeconfig chmod 600, доступен только dog
- Межузловой трафик ограничен портами: 6443, 8472, 10250
- RBAC и network policies избыточны на данном этапе

**Alternatives considered**:
- Минимальная (K3s defaults): API слушает на 0.0.0.0 — риск для домашней сети
- Продвинутая (RBAC, network policies, audit): избыточна для 2-узлового dev-кластера

## 5. kubeconfig на рабочей станции

**Decision**: Отдельный файл ~/.kube/rpi-k3s.yaml, KUBECONFIG env переменная

**Rationale**:
- КРИТИЧНО: существующий ~/.kube/config содержит конфиги других кластеров
- Отдельный файл полностью изолирует rpi-кластер от других
- Использование: `export KUBECONFIG=~/.kube/rpi-k3s.yaml` или `KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl ...`
- При необходимости можно добавить alias в .zshrc: `alias k3s-kubectl='KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl'`

**Alternatives considered**:
- Merge в ~/.kube/config: рискованно, может повредить существующие контексты
- kubectl config set-context: безопаснее merge, но всё равно модифицирует ~/.kube/config

## 6. Конфликт swap в setup-cluster.yml

**Decision**: Обновить setup-cluster.yml — vm.swappiness=0, добавить swapoff -a

**Rationale**:
- Текущее значение swappiness=10 конфликтует с требованием K3s (полное отключение swap)
- Kubernetes kubelet по умолчанию отказывается запускаться при включённом swap
- Все хосты в стеке будут использоваться для K3s, поэтому отключение swap глобально корректно
- Raspberry Pi OS по умолчанию использует dphys-swapfile, его тоже нужно отключить

**Alternatives considered**:
- Отключать только в K3s роли: дублирование, несогласованность конфигов
- Условное отключение по группе: излишняя сложность для 4-узлового кластера

## 7. Референсные материалы из k8s-study

**Полезные артефакты для адаптации:**

| Файл в k8s-study | Назначение | Адаптация для rpi_stack |
|-------------------|------------|-------------------------|
| ansible/roles/prerequisites/tasks/main.yml | Подготовка хостов | Убрать LXC-специфику, добавить dphys-swapfile |
| ansible/roles/k3s_server/tasks/main.yml | Установка server | Адаптировать флаги (bind-address, disable traefik) |
| ansible/roles/k3s_agent/tasks/main.yml | Установка agent | Прямое использование с минимальными изменениями |
| ansible/group_vars/all.yml | Глобальные переменные | Шаблон для k3s_version, модулей ядра |
| docs/raspberry-pi-guide.md | Pi-специфика | Рекомендации по ресурсам и CNI |
| scripts/verify-cluster.sh | Верификация | Адаптировать для rpi_stack (температура, RAM) |

**Ключевые отличия от k8s-study:**
- k8s-study: Proxmox LXC контейнеры → rpi_stack: физические Raspberry Pi
- k8s-study: Cilium CNI → rpi_stack: Flannel (ресурсы Pi)
- k8s-study: 3 узла (1 server + 2 workers) → rpi_stack: 2 узла начально, до 4
- k8s-study: LXC nesting validation → rpi_stack: не нужно
- k8s-study: kubeconfig на сервере → rpi_stack: kubeconfig на Mac (отдельный файл)
