# Инструкция: Установка мониторинга (Grafana + Prometheus + Node Exporter)

Полное руководство по развёртыванию стека мониторинга на k3s кластере
Raspberry Pi с нуля.

---

## Обзор архитектуры

```
[Node Exporter] ---> [Prometheus] ---> [Mimir] ---> [Grafana]
  (каждая нода)      (сбор метрик)   (хранение)    (визуализация)
    :9100               :9090          :9009         :30300
   DaemonSet          Deployment     Deployment    Deployment+NodePort
```

Поток данных:

1. **Node Exporter** на каждой ноде собирает системные метрики (CPU, memory, disk, temperature)
2. **Prometheus** скрейпит node-exporter каждые 15 секунд
3. **Prometheus** отправляет метрики через remote_write в **Mimir** для долгосрочного хранения
4. **Grafana** читает данные из Mimir и отображает дашборды

## Требования

- Работающий k3s кластер (server + agents)
- Все ноды в статусе `Ready`
- `make monitoring-install` автоматически устанавливает всё через Ansible

## Компоненты

| Компонент     | Образ                                     | Назначение                   | Ресурсы       |
|---------------|-------------------------------------------|------------------------------|---------------|
| Node Exporter | `quay.io/prometheus/node-exporter:v1.8.2` | Сбор системных метрик        | 64-128Mi RAM  |
| Prometheus    | `prom/prometheus:v2.54.1`                 | Скрейпинг и буфер метрик     | 128-512Mi RAM |
| Mimir         | `grafana/mimir:2.13.0`                    | Долгосрочное хранение метрик | 256-512Mi RAM |
| Grafana       | `grafana/grafana:11.2.0`                  | Визуализация и дашборды      | 128-256Mi RAM |

## Пошаговая установка

### Шаг 1. Проверить что кластер работает

```bash
make k3s-status
```

Ожидаемый результат — все ноды `Ready`:

```
NAME    STATUS   ROLES           AGE   VERSION
leha    Ready    <none>          5m    v1.34.6+k3s1
motya   Ready    <none>          5m    v1.34.6+k3s1
osya    Ready    <none>          5m    v1.34.6+k3s1
sema    Ready    control-plane   30m   v1.34.6+k3s1
```

### Шаг 2. Запустить установку мониторинга

```bash
make monitoring-install
```

Ansible автоматически:

1. Создаёт namespace `monitoring`
2. Развёртывает Node Exporter как DaemonSet (на каждой ноде)
3. Устанавливает Prometheus с конфигурацией скрейпинга
4. Устанавливает Mimir с PersistentVolume (10Gi)
5. Устанавливает Grafana с NodePort 30300 и преднастроенным дашбордом

### Шаг 3. Проверить что всё работает

```bash
make monitoring-status
```

Ожидаемый результат — все поды `Running`:

```
NAME                          READY   STATUS    RESTARTS   AGE
grafana-xxxxxxxxxx-xxxxx      1/1     Running   0          2m
mimir-xxxxxxxxxx-xxxxx        1/1     Running   0          2m
node-exporter-xxxxx           1/1     Running   0          2m   (на каждой ноде)
prometheus-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
```

### Шаг 4. Открыть Grafana

```bash
make monitoring-open
```

Или вручную: http://10.0.1.33:30300

- Логин: **admin**
- Пароль: **admin**

Grafana предложит сменить пароль при первом входе.

### Шаг 5. Проверить дашборд

После входа: Dashboards -> **Node Exporter Full**

Дашборд показывает:

- CPU Usage по нодам
- Memory Usage по нодам
- Temperature CPU
- Disk Available на корневом разделе
- Network I/O
- Uptime

## Порты и доступ

| Сервис        | Внутренний порт | Внешний доступ         | Описание      |
|---------------|-----------------|------------------------|---------------|
| Node Exporter | 9100            | IP_ноды:9100/metrics   | Метрики хоста |
| Prometheus    | 9090            | Только внутри кластера | Скрейпинг     |
| Mimir         | 9009            | Только внутри кластера | Хранилище     |
| Grafana       | 3000            | IP_server:30300        | Web UI        |

## Хранилище

Используется `local-path` StorageClass (встроен в k3s):

| Компонент | PVC          | Размер | Нода |
|-----------|--------------|--------|------|
| Mimir     | data-mimir   | 10Gi   | sema |
| Grafana   | data-grafana | 5Gi    | sema |

Данные хранятся в `/var/lib/rancher/k3s/storage/` на ноде sema.

## Добавление новой ноды в мониторинг

При добавлении новой ноды в кластер (через `make k3s-agents`), Node Exporter
разворачивается автоматически благодаря DaemonSet. Дополнительных действий
не требуется.

## Управление

```bash
make monitoring-install    # Установить стек мониторинга
make monitoring-status     # Статус всех подов
make monitoring-open       # Открыть Grafana в браузере
make monitoring-uninstall  # Удалить весь стек (с подтверждением)
```

## Troubleshooting

### Поды не стартуют

```bash
# Описание проблемного пода
ssh sema "sudo k3s kubectl describe pod -n monitoring <pod-name>"

# Логи пода
ssh sema "sudo k3s kubectl logs -n monitoring <pod-name>"
```

### Нет данных в дашборде

1. Проверь Data Sources: Grafana -> Configuration -> Data Sources -> Mimir -> Test
2. Проверь что Prometheus скрейпит метрики:
   ```bash
   ssh sema "sudo k3s kubectl logs -n monitoring deployment/prometheus | tail -20"
   ```
3. Проверь что Node Exporter отвечает на ноде:
   ```bash
   curl http://10.0.1.33:9100/metrics | head -5
   ```

### Grafana недоступна

```bash
# Проверь сервис
ssh sema "sudo k3s kubectl get svc -n monitoring grafana"

# Проверь логи
ssh sema "sudo k3s kubectl logs -n monitoring deployment/grafana"
```

### PVC не создаётся

local-path provisioner входит в k3s. Проверь:

```bash
ssh sema "sudo k3s kubectl get storageclass"
# Должен быть local-path (default)
```

## Переменные конфигурации

Основные переменные определены в `roles/monitoring/defaults/main.yml`:

| Переменная                    | Значение по умолчанию | Описание                          |
|-------------------------------|-----------------------|-----------------------------------|
| `monitoring_namespace`        | monitoring            | Kubernetes namespace              |
| `monitoring_server_hostname`  | sema                  | Нода для Grafana/Mimir/Prometheus |
| `monitoring_grafana_nodeport` | 30300                 | Внешний порт Grafana              |
| `monitoring_mimir_storage`    | 10Gi                  | Размер хранилища Mimir            |
| `monitoring_grafana_storage`  | 5Gi                   | Размер хранилища Grafana          |
