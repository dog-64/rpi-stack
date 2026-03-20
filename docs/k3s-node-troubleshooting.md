# Диагностика и исправление проблем K3s нод

## Признаки проблемы

```bash
make k3s-status
# Нода показывает NotReady вместо Ready
```

---

## Шаг 1: Диагностика ноды

### 1.1 Проверить детали ноды

```bash
# С control-plane ноды (sema)
ssh sema 'kubectl describe node <имя-ноды>' | head -80
```

**Искать в выводе:**
- `Conditions` → `Ready: Unknown` = kubelet остановился
- `Taints` → `node.kubernetes.io/unreachable` = нода недоступна
- `LastHeartbeatTime` — когда нода последний раз отвечала

### 1.2 Проверить SSH доступ

```bash
ssh <имя-ноды> 'hostname'
```

**Если ошибка `REMOTE HOST IDENTIFICATION HAS CHANGED`:**
```bash
ssh-keygen -R <имя-ноды>
ssh-keygen -R <IP-ноды>
```

---

## Шаг 2: Проверка K3s на ноде

### 2.1 Проверить сервис

```bash
ssh <имя-ноды> 'sudo systemctl status k3s-agent --no-pager -l'
```

**Возможные проблемы:**

| Ошибка | Причина | Решение |
|--------|---------|---------|
| `Unit k3s-agent.service not found` | K3s не установлен | [Переустановка](#шаг-4-переустановка-k3s-agent) |
| `Node password rejected` | Конфликт паролей | [Очистка credentials](#шаг-3-очистка-credentials) |
| `connection refused` | Нет связи с server | Проверить сеть и server |

### 2.2 Проверить логи

```bash
ssh <имя-ноды> 'sudo journalctl -u k3s-agent -n 50 --no-pager'
```

---

## Шаг 3: Очистка credentials

Если ошибка `Node password rejected, duplicate hostname`:

```bash
# На проблемной ноде
ssh <имя-ноды> 'sudo rm -rf /etc/rancher/node/password /var/lib/rancher/k3s/agent'
ssh <имя-ноды> 'sudo systemctl restart k3s-agent'
```

---

## Шаг 4: Переустановка K3s Agent

### 4.1 Получить токен с сервера

```bash
ssh sema 'sudo cat /var/lib/rancher/k3s/server/node-token'
```

### 4.2 Установить агент

```bash
# Заменить <ТОКЕН> на токен из предыдущего шага
ssh <имя-ноды> "curl -sfL https://get.k3s.io | K3S_URL=https://10.0.1.33:6443 K3S_TOKEN=<ТОКЕН> sh -s - --node-name <имя-ноды>"
```

### 4.3 Если после установки ошибка пароля

```bash
ssh <имя-ноды> 'sudo rm -rf /etc/rancher/node/password /var/lib/rancher/k3s/agent && sudo systemctl restart k3s-agent'
```

---

## Шаг 5: Проверка результата

```bash
# Подождать 20-30 секунд
sleep 20

# Проверить статус
make k3s-status
```

---

## Типичные сценарии

### Сценарий 1: Нода перезагружалась, время сбилось

Raspberry Pi без RTC теряет время при перезагрузке.

```bash
ssh <имя-ноды> 'timedatectl status'
ssh <имя-ноды> 'sudo systemctl restart systemd-timesyncd'
ssh <имя-ноды> 'sudo systemctl restart k3s-agent'
```

### Сценарий 2: SD карта повреждена, система переустановлена

Нода регистрируется с новым паролем, но старая запись на сервере.

**Решение:** Очистка credentials (Шаг 3)

### Сценарий 3: K3s agent удалён или повреждён

**Решение:** Полная переустановка (Шаг 4)

---

## Полезные команды

```bash
# Удалить ноду из кластера (если нужно)
ssh sema 'kubectl delete node <имя-ноды>'

# Полностью удалить K3s agent с ноды
ssh <имя-ноды> 'sudo /usr/local/bin/k3s-agent-uninstall.sh'

# Перезапустить агент
ssh <имя-ноды> 'sudo systemctl restart k3s-agent'

# Проверить версию K3s
ssh <имя-ноды> 'k3s --version'
```

---

## Краткий чеклист

1. [ ] `kubectl describe node` — найти причину
2. [ ] Проверить SSH доступ
3. [ ] `systemctl status k3s-agent` — статус сервиса
4. [ ] `journalctl -u k3s-agent` — логи
5. [ ] Очистить credentials если `password rejected`
6. [ ] Переустановить агент если сервис не найден
7. [ ] `make k3s-status` — проверить результат
