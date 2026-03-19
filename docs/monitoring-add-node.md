# Добавление новой ноды в мониторинг

## Автоматическая часть (DaemonSet)

Node Exporter установлен как **DaemonSet**, поэтому новая нода получит его автоматически при добавлении в k3s_cluster:

```bash
# После добавления ноды в k3s_cluster проверь:
make monitoring-status
# Должен появиться новый node-exporter-<pod> на новой ноде
```

## Ручная часть (Prometheus scrape_config)

Prometheus нужно явно указать IP-адреса нод для сбора метрик.

### 1. Добавь ноду в inventory.yml

```yaml
new_node:
  ansible_host: 10.0.1.XXX
  hostname: pXX
  k3s_role: agent  # или server
```

### 2. Обнови Prometheus scrape_configs

Отредактируй `roles/monitoring/templates/prometheus-config.yml.j2`:

```yaml
scrape_configs:
  - job_name: "node-exporter"
    static_configs:
      - targets:
          - "10.0.1.33:9100"   # sema
          - "10.0.1.104:9100"  # leha
          - "10.0.1.55:9100"   # motya
          - "10.0.1.75:9100"   # osya
          - "10.0.1.XXX:9100"  # new_node  # <-- добавь эту строку
```

### 3. Примени изменения

```bash
# Переустанови мониторинг (только Prometheus)
ansible k3s_server -b -a "k3s kubectl delete configmap -n monitoring prometheus-config"
ansible k3s_server -b -a "k3s kubectl rollout restart deployment/prometheus -n monitoring"
```

Или полностью переустанови (если используются Ansible таски):

```bash
make monitoring-uninstall  # с подтверждением
make monitoring-install
```

## Верификация

### 1. Проверь Node Exporter на новой ноде

```bash
curl http://10.0.1.XXX:9100/metrics | grep node_cpu
```

### 2. Проверь Prometheus targets

Открой Grafana → Explore → запрос `up{job="node-exporter"}` — должна появиться новая нода.

### 3. Проверь дашборд

В дашборде **Node Exporter Full** должен появиться график для новой ноды.

## Если нода не появилась в Grafana

1. Проверь что Node Exporter запущен:
   ```bash
   make monitoring-status
   ```

2. Проверь логи Prometheus:
   ```bash
   ansible k3s_server -b -a "k3s kubectl logs -n monitoring deployment/prometheus"
   ```

3. Проверь что Prometheus видит target:
   ```bash
   # Prometheus UI (через port-forward)
   k3s kubectl port-forward -n monitoring svc/prometheus 9090:9090
   # Открой http://localhost:9090/targets
   ```
