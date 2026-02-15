# Data Model: Установка K3s на Raspberry Pi стеке

**Date**: 2026-02-15
**Feature**: 002-k3s-install

## Infrastructure Entities

### K3s Cluster

- **Имя**: rpi-k3s (контекст в kubeconfig)
- **Тип**: Single-server (без HA)
- **Хранилище состояния**: SQLite (встроенное в K3s)
- **CNI**: Flannel (vxlan)
- **API endpoint**: https://10.0.1.104:6443

### Nodes (Узлы)

| Атрибут | leha (server) | sema (agent) | motya (agent, будущий) | osya (agent, будущий) |
|---------|---------------|--------------|------------------------|------------------------|
| Роль | control-plane | worker | worker | worker |
| Модель | Pi 5 | Pi 5 | Pi 4 | Pi 4 |
| RAM | 8GB | 8GB | 8GB | 8GB |
| IP | 10.0.1.104 | 10.0.1.33 | 10.0.1.56 | 10.0.1.75 |
| Hostname | p104 | p33 | p56 | p75 |
| Arch | arm64 | arm64 | arm64 | arm64 |

### Cluster Token

- **Генерируется**: при установке K3s server
- **Хранится**: /var/lib/rancher/k3s/server/node-token (на leha)
- **Используется**: agent-узлами при присоединении к кластеру
- **Доступ**: только root на leha
- **В Ansible**: извлекается из server через slurp/fetch, передаётся в k3s_agent роль

### kubeconfig

- **Источник**: /etc/rancher/k3s/k3s.yaml (на leha)
- **Копия на Mac**: ~/.kube/rpi-k3s.yaml
- **Трансформация**: server адрес 127.0.0.1:6443 → 10.0.1.104:6443
- **Права**: 0600 (только владелец)
- **Контекст**: rpi-k3s (переименовать из default)
- **КРИТИЧНО**: ~/.kube/config НЕ модифицируется

## Ansible Inventory Model

### Новые группы

```yaml
k3s_server:
  hosts:
    leha:

k3s_agent:
  hosts:
    sema:
    # Будущие:
    # motya:
    # osya:

k3s_cluster:
  children:
    k3s_server:
    k3s_agent:
```

### Переменные (group_vars)

**group_vars/all.yml** (дополнение):
```yaml
k3s_version: "v1.31.4+k3s1"  # Конкретная версия — определить при ручной установке
```

**group_vars/k3s_server.yml** (новый):
```yaml
k3s_server_bind_address: "{{ ansible_host }}"
k3s_server_advertise_address: "{{ ansible_host }}"
k3s_server_disable:
  - traefik
  - servicelb
k3s_kubeconfig_mode: "0600"
k3s_server_extra_args: ""
```

**group_vars/k3s_agent.yml** (новый):
```yaml
k3s_server_url: "https://{{ hostvars[groups['k3s_server'][0]]['ansible_host'] }}:6443"
k3s_agent_extra_args: ""
```

## Ansible Roles Model

### k3s_prerequisites

**Inputs (defaults/main.yml)**:
```yaml
k3s_kernel_modules:
  - overlay
  - br_netfilter
k3s_sysctl_params:
  net.bridge.bridge-nf-call-iptables: 1
  net.bridge.bridge-nf-call-ip6tables: 1
  net.ipv4.ip_forward: 1
k3s_disable_swap: true
k3s_required_packages:
  - curl
  - ca-certificates
```

**Outputs**: Хост готов к установке K3s

### k3s_server

**Inputs (defaults/main.yml)**:
```yaml
k3s_version: ""  # Из group_vars/all.yml
k3s_server_bind_address: ""
k3s_server_advertise_address: ""
k3s_server_disable: []
k3s_kubeconfig_mode: "0600"
```

**Outputs**:
- K3s server запущен (systemd service)
- API-сервер доступен на порту 6443
- Cluster token в /var/lib/rancher/k3s/server/node-token
- kubeconfig в /etc/rancher/k3s/k3s.yaml

### k3s_agent

**Inputs (defaults/main.yml)**:
```yaml
k3s_version: ""
k3s_server_url: ""
k3s_token: ""  # Получается из server в runtime
```

**Outputs**:
- K3s agent запущен (systemd service)
- Узел зарегистрирован в кластере

### k3s_uninstall

**Inputs (defaults/main.yml)**:
```yaml
k3s_uninstall_cleanup_data: true
k3s_uninstall_cleanup_config: true
```

**Outputs**: K3s полностью удалён с хоста

## Network Model

```
Mac (workstation)
  │
  │ kubectl (KUBECONFIG=~/.kube/rpi-k3s.yaml)
  │
  └──── 10.0.1.0/24 (home network) ────┐
        │                                │
   leha (10.0.1.104)              sema (10.0.1.33)
   K3s Server                     K3s Agent
   ├── API :6443 ◄────────────── join via token
   ├── Flannel VXLAN :8472 ◄──► Flannel VXLAN :8472
   └── kubelet :10250             kubelet :10250
```

## State Transitions

### Node Lifecycle

```
[Not Installed] → (k3s install) → [Running] → (reboot) → [Running]
                                      │
                                      ├── (network loss) → [NotReady] → (network restored) → [Ready]
                                      │
                                      └── (k3s uninstall) → [Not Installed]
```

### Cluster Lifecycle

```
[Empty] → (server install) → [Single Node] → (agent join) → [Multi Node]
                                                                 │
                                                     (add motya/osya) → [Full Cluster]
```
