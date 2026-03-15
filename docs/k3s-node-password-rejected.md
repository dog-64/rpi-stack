# k3s-agent: Node password rejected — после миграции SSD

## Дата
2026-03-07

## Симптомы
- Узел `motya` в статусе `NotReady`
- `kubectl get nodes` показывает `Ready: Unknown`
- `kubectl describe node motya` → `Kubelet stopped posting node status`

## Диагностика

### 1. Проверка статуса k3s-agent на узле
```bash
ssh motya "sudo systemctl status k3s-agent"
```

**Результат:** Агент запущен, но в логах:
```
Node password rejected, duplicate hostname or contents of '/etc/rancher/node/password'
may not match server node-passwd entry
```

### 2. Проверка статуса узла с сервера
```bash
ssh sema "sudo k3s kubectl describe node motya"
```

**Результат:**
- `LastHeartbeatTime`: Thu, 05 Mar 2026 23:00:01 (более 2 дней назад)
- `Reason`: `Kubelet stopped posting node status`
- `Taints`: `node.kubernetes.io/unreachable`

## Причина

**K3s использует механизм node-password для аутентификации узлов.**

При миграции на SSD:
1. Система была переустановлена на motya
2. Был сгенерирован новый `/etc/rancher/node/password`
3. На сервере (sema) остался старый password в `node-passwd` записи
4. Агент не мог пройти аутентификацию → узел стал `NotReady`

## Решение

### Шаг 1: Удалить узел с сервера
```bash
ssh sema "sudo k3s kubectl delete node motya"
```

### Шаг 2: Остановить агент и очистить данные
```bash
ssh motya "sudo systemctl stop k3s-agent"
ssh motya "sudo rm -rf /var/lib/rancher/k3s/agent/*"
```

### Шаг 3: Запустить агент (авторегистрация)
```bash
ssh motya "sudo systemctl start k3s-agent"
```

### Шаг 4: Проверить статус
```bash
ssh sema "sudo k3s kubectl get nodes"
```

**Ожидаемый результат:** `motya Ready` через 10-30 секунд

## Профилактика

### После миграции SSD на узле с k3s-agent:

1. **Проверить статус агента:**
   ```bash
   ssh <hostname> "sudo systemctl status k3s-agent"
   ```

2. **Проверить логи на ошибки аутентификации:**
   ```bash
   ssh <hostname> "sudo journalctl -u k3s-agent -n 50 | grep -i password"
   ```

3. **Проверить статус узла в кластере:**
   ```bash
   ssh sema "sudo k3s kubectl get nodes"
   ```

### Если обнаружена проблема:

Выполнить шаги решения выше. Узел перерегистрируется с новым паролем.

## Связанные документы

- [→ Lessons Learned](lessons-learned.md) — общий список проблем
- [→ SSD Migration Checklist](ssd-migration-checklist.md) — чеклист миграции
