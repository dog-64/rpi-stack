# Quickstart & Verification: K3s на Raspberry Pi стеке

**Date**: 2026-02-15
**Feature**: 002-k3s-install

## Предусловия

- [ ] Хосты leha и sema доступны по SSH: `ssh dog@10.0.1.104`, `ssh dog@10.0.1.33`
- [ ] Базовая настройка выполнена (setup-cluster.yml): hostname, /etc/hosts, timezone
- [ ] Архитектура arm64: `ssh dog@10.0.1.104 "uname -m"` → aarch64
- [ ] Свободное место: `ssh dog@10.0.1.104 "df -h /"` → минимум 2GB
- [ ] Сетевая связность: `ssh dog@10.0.1.33 "nc -zv 10.0.1.104 6443"` (после установки server)

## Быстрый старт: Ручная установка

### 1. K3s Server на leha

```bash
# SSH на leha
ssh dog@10.0.1.104

# Подготовка
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab
sudo systemctl disable dphys-swapfile 2>/dev/null || true

# Модули ядра
echo -e "overlay\nbr_netfilter" | sudo tee /etc/modules-load.d/k3s.conf
sudo modprobe overlay
sudo modprobe br_netfilter

# Sysctl
cat <<EOF | sudo tee /etc/sysctl.d/k3s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system

# Установка K3s server
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="<VERSION>" \
  sh -s - server \
  --bind-address=10.0.1.104 \
  --advertise-address=10.0.1.104 \
  --disable=traefik \
  --disable=servicelb \
  --write-kubeconfig-mode=0600

# Верификация
sudo kubectl get nodes
sudo kubectl get pods -A
```

### 2. kubeconfig на Mac

```bash
# С Mac: скопировать kubeconfig
scp dog@10.0.1.104:/etc/rancher/k3s/k3s.yaml ~/.kube/rpi-k3s.yaml

# Заменить адрес
sed -i '' 's/127.0.0.1/10.0.1.104/g' ~/.kube/rpi-k3s.yaml

# Проверить
KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl get nodes
```

### 3. K3s Agent на sema

```bash
# Получить токен (с Mac)
ssh dog@10.0.1.104 "sudo cat /var/lib/rancher/k3s/server/node-token"

# SSH на sema
ssh dog@10.0.1.33

# Подготовка (те же шаги что для leha: swap, модули, sysctl)
# ...

# Установка K3s agent
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="<VERSION>" \
  K3S_URL=https://10.0.1.104:6443 \
  K3S_TOKEN="<TOKEN>" \
  sh -s - agent

# Проверить с Mac
KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl get nodes
```

## Быстрый старт: Ansible

```bash
# Полная установка кластера
ansible-playbook k3s-install.yml

# Проверка кластера
make k3s-verify

# Проверка идемпотентности
ansible-playbook k3s-install.yml  # Ожидается 0 changed
```

## Верификация (Verification Scenarios)

### V1: Узлы кластера

```bash
# Все узлы в статусе Ready
KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl get nodes
# Ожидается:
# NAME   STATUS   ROLES                  AGE   VERSION
# leha   Ready    control-plane,master   Xm    v1.31.4+k3s1
# sema   Ready    <none>                 Xm    v1.31.4+k3s1
```

**Критерий**: Все узлы STATUS=Ready

### V2: Системные поды

```bash
KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl get pods -A
# Ожидается все поды в Running/Completed:
# kube-system   coredns-xxx                Running
# kube-system   local-path-provisioner-xxx Running
# kube-system   metrics-server-xxx         Running
# kube-system   svclb-* — НЕ должно быть (servicelb отключён)
```

**Критерий**: Нет подов в CrashLoopBackOff или Pending

### V3: Тестовый pod

```bash
KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl run test-nginx \
  --image=nginx:alpine \
  --restart=Never

KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl wait --for=condition=Ready \
  pod/test-nginx --timeout=120s

KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl delete pod test-nginx
```

**Критерий**: Pod запускается и становится Ready за <2 минуты

### V4: Автозапуск после reboot

```bash
# Перезагрузить узел
ssh dog@10.0.1.33 "sudo reboot"

# Подождать 3 минуты, проверить
sleep 180
KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl get nodes
```

**Критерий**: Узел возвращается в Ready за <3 минуты

### V5: Ресурсы (RAM)

```bash
# Проверить потребление RAM на каждом узле
ssh dog@10.0.1.104 "free -h | grep Mem"
ssh dog@10.0.1.33 "free -h | grep Mem"
```

**Критерий**: K3s потребляет <1GB RAM на узел в idle

### V6: Безопасность

```bash
# API не слушает на 0.0.0.0
ssh dog@10.0.1.104 "sudo ss -tlnp | grep 6443"
# Ожидается: только 10.0.1.104:6443

# kubeconfig права
ssh dog@10.0.1.104 "ls -la /etc/rancher/k3s/k3s.yaml"
# Ожидается: -rw------- (0600)

# Существующий kubeconfig на Mac не затронут
ls -la ~/.kube/config  # Дата модификации не изменилась
```

**Критерий**: API только на локальной сети, kubeconfig 0600, ~/.kube/config не тронут

### V7: Идемпотентность Ansible

```bash
# Повторный запуск
ansible-playbook k3s-install.yml 2>&1 | tail -5
# Ожидается: changed=0
```

**Критерий**: 0 changed tasks при повторном запуске

## Удаление (при необходимости)

```bash
# Через Ansible
ansible-playbook k3s-uninstall.yml

# Вручную (server)
ssh dog@10.0.1.104 "sudo /usr/local/bin/k3s-uninstall.sh"

# Вручную (agent)
ssh dog@10.0.1.33 "sudo /usr/local/bin/k3s-agent-uninstall.sh"

# Удалить kubeconfig с Mac
rm ~/.kube/rpi-k3s.yaml
```
