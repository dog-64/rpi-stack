# Manual Installation Notes: K3s на sema (Ubuntu Server 24.04)

**Date**: 2026-02-15
**Host**: sema (10.0.1.33)
**OS**: Ubuntu Server 24.04.4 LTS
**K3s Version**: v1.32.12+k3s1

## Почему sema вместо leha

leha (Raspberry Pi 5 с Raspberry Pi OS) имеет проблему `cgroup_disable=memory` в firmware, которая блокирует K3s. sema была переустановлена на Ubuntu Server 24.04, где этой проблемы нет.

См. подробности: `docs/k3s-rpi5-cgroup-issue.md`

## Pre-flight Checks

```bash
ssh dog@10.0.1.33
uname -m        # aarch64 ✅
df -h /         # 53GB free ✅
```

## Шаги установки

### 1. Подготовка хоста

```bash
# Отключить swap
sudo swapoff -a
sudo sed -i.bak '/swap/d' /etc/fstab

# Настроить модули ядра
echo -e 'overlay\nbr_netfilter' | sudo tee /etc/modules-load.d/k3s.conf
sudo modprobe overlay
sudo modprobe br_netfilter

# Настроить sysctl
cat | sudo tee /etc/sysctl.d/k3s.conf << 'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system
```

### 2. Установка K3s server

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='v1.32.12+k3s1' sh -s - server \
  --bind-address=10.0.1.33 \
  --advertise-address=10.0.1.33 \
  --disable=traefik \
  --disable=servicelb \
  --write-kubeconfig-mode=0600
```

### 3. Верификация

```bash
# На sema
sudo kubectl get nodes
# NAME   STATUS   ROLES                  AGE   VERSION
# sema   Ready    control-plane,master   30s   v1.32.12+k3s1

sudo kubectl get pods -A
# Все системные поды Running
```

### 4. kubeconfig на Mac

```bash
# Скопировать с sema
ssh dog@10.0.1.33 "sudo cp /etc/rancher/k3s/k3s.yaml /tmp/k3s.yaml && sudo chmod 644 /tmp/k3s.yaml"
scp dog@10.0.1.33:/tmp/k3s.yaml ~/.kube/rpi-k3s.yaml

# Заменить адрес
sed -i '' 's/127.0.0.1/10.0.1.33/g' ~/.kube/rpi-k3s.yaml
chmod 600 ~/.kube/rpi-k3s.yaml

# Проверить
KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl get nodes
```

### 5. Cluster Token (для будущих agent nodes)

```bash
# Получить токен (сохранить для добавления worker nodes)
ssh dog@10.0.1.33 "sudo cat /var/lib/rancher/k3s/server/node-token"
# K106e5b1c679971e50bb141675f84b6081077298ca6ebd59a07456dec5d4300eda6::server:f1799425c3cafcc0e8ddf0016095d151
```

## Результат

✅ **Одноузловой K3s кластер работает на sema**

- K3s server: sema (10.0.1.33)
- kubeconfig: ~/.kube/rpi-k3s.yaml
- Управление: `KUBECONFIG=~/.kube/rpi-k3s.yaml kubectl ...`
- Cluster token: сохранён для добавления worker nodes

## Следующие шаги

1. **Добавить worker nodes**:
   - leha: заблокирован (проблема cgroup), нужен патч DTB или Ubuntu
   - motya: недоступен по сети
   - osya: Raspberry Pi 4 с Raspberry Pi OS — проверить проблему cgroup

2. **Создать Ansible роли** для автоматизации (US3)

3. **Скрипт верификации** (US4)

## Замечания

- Ubuntu Server 24.04 на Raspberry Pi работает с K3s из коробки
- Raspberry Pi OS (Debian-based) имеет проблему `cgroup_disable=memory` в DTB
- Для production рекомендуется патчить DTB или использовать Ubuntu

## Обновления

- 2026-02-15: Initial installation on sema (Ubuntu Server 24.04)
