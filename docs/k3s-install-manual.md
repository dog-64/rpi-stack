# Установка k3s на Raspberry Pi кластер (ручной режим)

**Цель:** Развёртывание Kubernetes кластера на базе k3s для Raspberry Pi.

**Архитектура:**
- **Server (control-plane):** sema (10.0.1.33) - Pi 5, Ubuntu 25.10, SSD
- **Agents (workers):** leha, motya, osya - Pi 5/4, Ubuntu/Debian

---

## Предварительные требования

### На всех хостах:

```bash
# Проверить архитектуру (должна быть aarch64)
uname -m

# Проверить ядро (рекомендуется 5.x+)
uname -r

# Проверить cgroups
cat /proc/cgroups | grep -E 'memory|cpu'
```

### Настройка sysctl (если не настроено):

```bash
# Загрузить модули
sudo modprobe br_netfilter
sudo modprobe overlay

# Настроить sysctl
cat << 'EOF' | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

# Применить
sudo sysctl --system
```

### Установить необходимые пакеты:

```bash
# Ubuntu/Debian
sudo apt update && sudo apt install -y curl iptables
```

---

## Шаг 1: Установка k3s Server (Control Plane)

Выполняется на **sema (10.0.1.33)**.

### Базовая установка:

```bash
# Установка с настройками для кластера
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_EXEC='server' \
  K3S_NODE_NAME='sema' \
  sh -s - \
  --write-kubeconfig-mode 644 \
  --tls-san 10.0.1.33 \
  --advertise-address 10.0.1.33 \
  --bind-address 10.0.1.33
```

### С кластерной инициализацией (для HA):

```bash
# Для high-availability кластера (несколько server-нод)
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_EXEC='server' \
  K3S_NODE_NAME='sema' \
  K3S_TOKEN='<СГЕНЕРИРОВАННЫЙ_ТОКЕН>' \
  sh -s - \
  --cluster-init \
  --write-kubeconfig-mode 644 \
  --tls-san 10.0.1.33 \
  --advertise-address 10.0.1.33 \
  --bind-address 10.0.1.33
```

### Проверка установки:

```bash
# Статус сервиса
sudo systemctl status k3s

# Версия
k3s --version

# Ноды
sudo k3s kubectl get nodes -o wide

# Поды
sudo k3s kubectl get pods -A
```

**Критерий успеха:**
- ✓ k3s service: active (running)
- ✓ Node STATUS: Ready
- ✓ Все системные поды: Running

### Получить токен для агентов:

```bash
# Сохранить этот токен!
sudo cat /var/lib/rancher/k3s/server/node-token

# Пример вывода:
# K10xxxxxxxx::server:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

### Получить kubeconfig:

```bash
# kubeconfig для локального доступа
sudo cat /etc/rancher/k3s/k3s.yaml

# Для удалённого доступа - заменить server:
# server: https://127.0.0.1:6443 → server: https://10.0.1.33:6443
```

**Откат:**
```bash
sudo /usr/local/bin/k3s-uninstall.sh
sudo rm -rf /var/lib/rancher /etc/rancher /var/lib/kubelet /var/lib/cni
sudo reboot
```

---

## Шаг 2: Установка k3s Agent (Worker Nodes)

Выполняется на каждой **worker** ноде.

### Установка агента:

```bash
# Заменить переменные:
# K3S_URL - адрес server
# K3S_TOKEN - токен из шага 1
# K3S_NODE_NAME - имя ноды (уникальное)

curl -sfL https://get.k3s.io | \
  K3S_URL='https://10.0.1.33:6443' \
  K3S_TOKEN='K10xxxxxxxx::server:xxxxxxxxxxxxxxxx' \
  INSTALL_K3S_EXEC='agent' \
  K3S_NODE_NAME='leha' \
  sh -
```

### Проверка:

```bash
# Статус сервиса агента
sudo systemctl status k3s-agent

# Логи
sudo journalctl -u k3s-agent -f
```

**Откат:**
```bash
sudo /usr/local/bin/k3s-agent-uninstall.sh
sudo rm -rf /var/lib/rancher /etc/rancher
sudo reboot
```

---

## Шаг 3: Верификация кластера

Выполняется на **server**.

```bash
# Все ноды
sudo k3s kubectl get nodes -o wide

# Ожидаемый вывод:
# NAME   STATUS   ROLES           AGE   VERSION        INTERNAL-IP
# sema   Ready    control-plane   10m   v1.34.4+k3s1   10.0.1.33
# leha   Ready    <none>          2m    v1.34.4+k3s1   10.0.1.104
# motya  Ready    <none>          1m    v1.34.4+k3s1   10.0.1.56
# osya   Ready    <none>          30s   v1.34.4+k3s1   10.0.1.75

# Все поды
sudo k3s kubectl get pods -A

# Компоненты
sudo k3s kubectl get cs

# Информация о кластере
sudo k3s kubectl cluster-info
```

---

## Шаг 4: Настройка kubectl для удалённого доступа

На локальной машине:

```bash
# Создать директорию
mkdir -p ~/.kube

# Скопировать kubeconfig (заменить server)
ssh dog@10.0.1.33 "sudo cat /etc/rancher/k3s/k3s.yaml" | \
  sed 's/127.0.0.1/10.0.1.33/' > ~/.kube/config

# Установить права
chmod 600 ~/.kube/config

# Проверить
kubectl get nodes
```

---

## Полезные команды

### Управление сервисами:

```bash
# Server
sudo systemctl start k3s
sudo systemctl stop k3s
sudo systemctl restart k3s
sudo systemctl status k3s

# Agent
sudo systemctl start k3s-agent
sudo systemctl stop k3s-agent
sudo systemctl restart k3s-agent
sudo systemctl status k3s-agent
```

### Логи:

```bash
# Server
sudo journalctl -u k3s -f

# Agent
sudo journalctl -u k3s-agent -f

# Containerd
sudo journalctl -u k3s -u containerd -f
```

### kubectl (на server):

```bash
# Локально
sudo k3s kubectl get nodes

# Или через kubectl (если настроен)
kubectl get nodes --kubeconfig=/etc/rancher/k3s/k3s.yaml
```

### Управление нодами:

```bash
# Вывести ноду из обслуживания
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Вернуть ноду
kubectl uncordon <node-name>

# Удалить ноду
kubectl delete node <node-name>
```

---

## Удаление k3s

### Удаление Server:

```bash
# Остановить
sudo systemctl stop k3s

# Удалить
sudo /usr/local/bin/k3s-uninstall.sh

# Очистить
sudo rm -rf /var/lib/rancher /etc/rancher /var/lib/kubelet /var/lib/cni /run/k3s

# Очистить iptables
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo iptables -X

# Перезагрузка
sudo reboot
```

### Удаление Agent:

```bash
# Остановить
sudo systemctl stop k3s-agent

# Удалить
sudo /usr/local/bin/k3s-agent-uninstall.sh

# Очистить
sudo rm -rf /var/lib/rancher /etc/rancher

# Перезагрузка
sudo reboot
```

### Удаление ноды из кластера (на server):

```bash
# Удалить ноду из kubernetes
sudo k3s kubectl delete node <node-name>
```

---

## Переменные окружения установки

| Переменная | Описание | Пример |
|------------|----------|--------|
| `INSTALL_K3S_EXEC` | Роль: server или agent | `server` |
| `K3S_URL` | URL сервера (для agent) | `https://10.0.1.33:6443` |
| `K3S_TOKEN` | Токен кластера | `K10xxx::server:xxx` |
| `K3S_NODE_NAME` | Имя ноды | `sema` |
| `INSTALL_K3S_CHANNEL` | Канал релиза | `stable`, `latest` |
| `INSTALL_K3S_VERSION` | Конкретная версия | `v1.34.4+k3s1` |

---

## Флаги k3s server

| Флаг | Описание |
|------|----------|
| `--write-kubeconfig-mode 644` | Права на kubeconfig |
| `--tls-san IP` | SAN для TLS сертификата |
| `--advertise-address IP` | IP для API server |
| `--bind-address IP` | Адрес привязки |
| `--cluster-init` | Инициализация HA кластера |
| `--disable TRAEFIK` | Отключить компонент |
| `--cluster-cidr CIDR` | CIDR для подов |
| `--service-cidr CIDR` | CIDR для сервисов |

---

## Типичные проблемы

### Проблема: Agent не подключается к Server

**Диагностика:**
```bash
# Проверить доступность
ping 10.0.1.33
curl -k https://10.0.1.33:6443

# Проверить токен
sudo cat /var/lib/rancher/k3s/agent/node-password
```

**Решение:**
- Проверить firewall (открыть 6443, 10250)
- Проверить правильность токена
- Проверить время (NTP синхронизация)

### Проблема: Node NotReady

**Диагностика:**
```bash
kubectl describe node <node-name>
kubectl get events -n kube-system
```

### Проблема: Pod stuck in Pending

**Диагностика:**
```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl get events -n <namespace>
```

### Проблема: cgroup memory not enabled

**Решение (Raspberry Pi):**
```bash
# Добавить в /boot/firmware/cmdline.txt
cgroup_memory=1 cgroup_enable=memory
```

---

## Конфигурационные файлы

| Файл | Описание |
|------|----------|
| `/etc/rancher/k3s/k3s.yaml` | kubeconfig |
| `/var/lib/rancher/k3s/server/node-token` | токен кластера |
| `/etc/systemd/system/k3s.service` | systemd unit (server) |
| `/etc/systemd/system/k3s-agent.service` | systemd unit (agent) |
| `/var/lib/rancher/k3s/agent/etc/k3s-agent.yaml` | конфиг агента |

---

## Порты

| Порт | Протокол | Описание |
|------|----------|----------|
| 6443 | TCP | Kubernetes API |
| 10250 | TCP | Kubelet |
| 8472 | UDP | Flannel VXLAN |
| 51820 | UDP | Flannel Wireguard |
| 2379-2380 | TCP | Etcd (HA) |
