# k3s Node: Time Synchronization Problem

**Дата:** 2026-03-14
**Категория:** Kubernetes / k3s
**Серьезность:** High

## Симптомы

- Узел `motya` в статусе `NotReady`
- `kubectl get nodes` показывает `Ready: Unknown`
- `kubectl describe node motya`:
  ```
  Ready Unknown Kubelet stopped posting node status
  ```
- В логах k3s-agent:
  ```
  CA cert validation failed: Get "https://127.0.0.1:6444/cacerts": tls: failed to verify certificate: x509: certificate has expired or is not yet valid
  ```

## Диагностика

### 1. Проверка статуса узла

```bash
# С сервера
kubectl get nodes
kubectl describe node motya

# С проблемного узла
sudo systemctl status k3s-agent
journalctl -u k3s-agent -n 50
```

### 2. Проверка времени

```bash
date
timedatectl status
```

**Результат на motya:**
```
Local time: Mon Sep  1 12:00:00 EET 2025  ❌
System clock synchronized: no
```

### 3. Причина проблемы

**K3s использует SSL/TLS сертификаты** с датой начала действия. Если системное время в прошлом:
- Сертификат "not yet valid" (наступающая дата)
- TLS handshake fails
- Узел не может подключиться к серверу

**Особенности Raspberry Pi:**
- Нет RTC (батарейки для часов)
- При перезагрузке время сбрасывается
- Если NTP не работает → время устанавливается из предыдущего сеанса

## Решение

### 1. Ручное исправление

```bash
# Проверить и запустить chrony
sudo systemctl status chrony
sudo systemctl start chrony

# Дождаться синхронизации (до 60 секунд)
timedatectl status | grep "System clock"

# Перезапустить k3s-agent
sudo systemctl restart k3s-agent

# Проверить статус в кластере
sudo k3s kubectl get nodes
```

### 2. Автоматическое исправление (в роли k3s)

Добавлено в `roles/k3s/tasks/prerequisites.yml`:

```yaml
# Автоматическая синхронизация времени перед установкой k3s
- name: Check available NTP services
  ansible.builtin.stat:
    path: "{{ item }}"
  loop:
    - /usr/lib/systemd/systemd-timesyncd  # Стандарт для Ubuntu
    - /usr/lib/systemd/system/chrony.service  # Альтернатива

- name: Enable and run NTP service
  ansible.builtin.systemd:
    name: "{{ ntp_service }}"  # Автоматически выбирает доступный
    state: started
    enabled: true

- name: Wait for time synchronization
  shell: |
    timeout={{ k3s_time_sync_timeout }}
    # Ждать пока часы синхронизируются
    while [ $elapsed -lt $timeout ]; do
      if timedatectl status | grep -q "System clock synchronized: yes"; then
        exit 0
      fi
      sleep 2
      elapsed=$((elapsed + 2))
    done
```

### 3. Настройка в inventory.yml (опционально)

```yaml
k3s_ensure_time_sync: true      # Включить синхронизацию времени (по умолчанию)
k3s_time_sync_timeout: 60       # Таймаут ожидания в секундах
```

## Профилактика

### 1. Проверка NTP статуса

```bash
# Проверить статус chrony
chronyc tracking
chronyc sources

# Проверить timedatectl
timedatectl status
```

### 2. Мониторинг времени

Добавить в cron для регулярной проверки:
```bash
# Проверять каждые 5 минут
*/5 * * * * /usr/bin/timedatectl status | grep -q "System clock synchronized: yes" || /usr/bin/logger -t time-check "Time sync issue!"
```

### 3. Настройка Raspberry Pi

- **Raspberry Pi 4/5:** USB 2.0 ограничивает скорость, но NTP работает
- **Нет RTC:** Всегда оставлять NTP включенным
- **Network boot:** Если используется PXE, NTP критически важен

## Устаревшие решения

### НЕ работает:

```bash
# ❌ timedatectl set-time 2026-03-14  # Не сработает если NTP включен
# ❌ Не останавливать chrony вручную
# ❌ Использовать ntpdate (устаревший пакет)
```

## Связанные документы

- [→ k3s Installation Guide](k3s-install-guide.md)
- [→ SSD Migration Checklist](ssd-migration-checklist.md) - может вызывать данную проблему при миграции
- [→ Cluster Node Management](cluster-node-management.md)
- [→ Network Time Protocol](network-time-protocol.md)

## История изменений

| Дата | Изменение |
|------|-----------|
| 2026-03-14 | Первое обнаружение на motya, добавлена автоматизация в роль k3s |
| 2026-03-14 | Тестирование подтверждает работу решения |