# Руководство: Grafana + Mimir

## Установка

```bash
make monitoring-install
```

## Доступ

| Сервис | URL | Логин | Пароль |
|--------|-----|-------|--------|
| Grafana | http://10.0.1.33:30300 | admin | admin |

## Полезные команды

```bash
make monitoring-status    # Статус всех подов
make monitoring-open      # Открыть Grafana в браузере
make monitoring-uninstall # Удалить (с подтверждением)
```

## Структура дашбордов

После автоматического provisioning создаётся дашборд **Node Exporter Full** с панелями:

1. **CPU Usage** — загрузка CPU по нодам (%)
2. **Memory Usage** — использование памяти по нодам (%)
3. **Temperature** — температура CPU по нодам (°C)
4. **Disk Available** — доступное место на корневом разделе

## Data Sources

- **Mimir** — http://mimir:9009/prometheus (автоматически провижинен)
- Prometheus отправляет метрики через remote_write → Mimir

## Изменение пароля Grafana

После первого входа Grafana предложит изменить пароль. Рекомендуется сделать это.

Для изменения через Ansible отредактируй `roles/monitoring/templates/grafana.yml.j2`:

```yaml
env:
  - name: GF_SECURITY_ADMIN_PASSWORD
    value: "твой_новый_пароль"
```

Затем переустанови мониторинг:

```bash
ansible k3s_server -b -a "k3s kubectl delete namespace monitoring"
make monitoring-install
```

## Troubleshooting

### Поды не стартуют

```bash
make monitoring-status
ansible k3s_server -b -a "k3s kubectl describe pod -n monitoring <pod-name>"
```

### Grafana недоступна

```bash
# Проверь NodePort
ansible k3s_server -b -a "k3s kubectl get svc -n monitoring grafana"

# Провери логи
ansible k3s_server -b -a "k3s kubectl logs -n monitoring deployment/grafana"
```

### Нет данных в дашбордах

1. Проверь Data Sources → Mimir → Test
2. Проверь что Prometheus делает scrape:
   ```bash
   ansible k3s_server -b -a "k3s kubectl logs -n monitoring deployment/prometheus"
   ```
3. Проверь что Node Exporter доступен:
   ```bash
   curl http://10.0.1.33:9100/metrics
   ```
