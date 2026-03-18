# План: Мониторинг (Grafana + Mimir + Prometheus + Node Exporter)

## Архитектура

```
[Node Exporter] → [Prometheus] → remote_write → [Mimir] ← query ← [Grafana]
  DaemonSet         Deployment                   Deployment          Deployment
  все 4 ноды        sema                         sema                sema
  порт 9100         порт 9090                    порт 9009           NodePort :30300
```

> **Важно:** Mimir — хранилище метрик, он не умеет скрейпить сам. Prometheus собирает метрики
> с Node Exporter и отправляет в Mimir через `remote_write`. Grafana читает данные из Mimir
> через Prometheus-совместимый API.

## Ключевые решения

| Вопрос | Решение | Почему |
|--------|---------|--------|
| Скрейпер | Prometheus | Классический, хорошо задокументирован, remote_write в Mimir |
| Деплой | Raw K8s манифесты через Ansible | Нет Helm в проекте, проще для этого набора компонентов |
| Хранение | PVC через `local-path` (встроен в K3S) | Уже есть, данные на SSD |
| Namespace | `monitoring` | Изоляция от системных компонентов |
| Mimir режим | Monolithic (один процесс) | Для 4 нод microservices-режим — overkill |
| Grafana доступ | NodePort `:30300` | Простой доступ из LAN: `http://10.0.1.33:30300` |

## Лимиты ресурсов

| Компонент | Реплики | RAM request/limit | CPU request/limit |
|-----------|---------|-------------------|-------------------|
| Node Exporter | ×4 (DaemonSet) | 64Mi / 128Mi | 50m / 100m |
| Prometheus | ×1 | 128Mi / 512Mi | 100m / 300m |
| Mimir | ×1 | 256Mi / 512Mi | 100m / 500m |
| Grafana | ×1 | 128Mi / 256Mi | 100m / 250m |

## Структура файлов

```
roles/monitoring/
├── defaults/main.yml              # Версии образов, лимиты, порты
├── tasks/
│   ├── main.yml                   # Оркестратор (паттерн как у roles/k3s)
│   ├── check.yml                  # Проверка: уже установлено?
│   ├── namespace.yml              # Создать namespace monitoring
│   ├── node_exporter.yml          # DaemonSet + Service
│   ├── mimir.yml                  # ConfigMap + PVC + Deployment + Service
│   ├── prometheus.yml             # ConfigMap + Deployment + Service
│   ├── grafana.yml                # ConfigMap (datasource) + PVC + Deployment + Service
│   └── verify.yml                 # Ожидание Ready, проверка health endpoints
└── templates/
    ├── namespace.yml.j2
    ├── node-exporter.yml.j2       # DaemonSet (hostNetwork, hostPID) + Service
    ├── mimir-config.yml.j2        # ConfigMap с mimir.yaml
    ├── mimir.yml.j2               # PVC 10Gi + Deployment + ClusterIP Service
    ├── prometheus-config.yml.j2   # ConfigMap: scrape_configs + remote_write → Mimir
    ├── prometheus.yml.j2          # Deployment + ClusterIP Service
    ├── grafana-datasource.yml.j2  # ConfigMap: provisioning datasource → Mimir
    └── grafana.yml.j2             # PVC 5Gi + Deployment + NodePort Service

playbooks/monitoring-install.yml   # hosts: k3s_server
Makefile                           # + секция monitoring-*
```

## Порядок деплоя

1. **check** — проверить namespace и поды, пропустить если уже работает
2. **namespace** — создать `monitoring`
3. **node_exporter** — DaemonSet с `hostNetwork: true`, `hostPID: true`, порт 9100
4. **mimir** — ConfigMap + PVC 10Gi + Deployment (nodeSelector: sema) + ClusterIP :9009
5. **prometheus** — ConfigMap (scrape node-exporter, remote_write → mimir:9009) + Deployment + ClusterIP :9090
6. **grafana** — ConfigMap datasource (Mimir как Prometheus-type) + PVC 5Gi + Deployment (nodeSelector: sema) + NodePort :30300
7. **verify** — ожидание всех подов Ready, curl /ready и /api/health

## Makefile targets

```makefile
monitoring-install    # ansible-playbook playbooks/monitoring-install.yml
monitoring-status     # k3s kubectl get pods -n monitoring -o wide
monitoring-uninstall  # k3s kubectl delete namespace monitoring (с подтверждением)
monitoring-open       # open http://10.0.1.33:30300
```

## Верификация после установки

1. `make monitoring-status` — все поды Running: node-exporter ×4, prometheus ×1, mimir ×1, grafana ×1
2. `make monitoring-open` — Grafana открывается в браузере
3. Grafana → Data Sources → Mimir → Test → зелёная галка
4. Импорт дашборда **Node Exporter Full** (Grafana ID: 1860)
