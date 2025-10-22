# Міграція на VPN v2 (Multi-IP Routing)

## Що змінилось

- **2 різні IP** для 2х акаунтів
- **Акаунт сина (arsen)**: Tailscale IP (100.100.74.9) як раніше
- **Акаунт дружини (lena)**: Tor exit IP (Швейцарія)
- **Автоматичний вибір** proxy на основі email

## Встановлення

### 1. Встановити Tor
```bash
pkg install tor
```

### 2. Встановити Python залежності
```bash
pip install aiohttp-socks
```

### 3. Налаштувати config.json
Відредагувати ~/vpn_v2/config.json:
- Вставити паролі для акаунтів
- Перевірити Tailscale IP

### 4. Тестування
```bash
cd ~/vpn_v2
chmod +x *.sh
./manager_v2.sh start
./test_routing.sh
```

## Міграція з v1 → v2

### Крок 1: Зупинити старий сервіс
```bash
cd ~/vpn
./manager.sh stop
```

### Крок 2: Запустити новий сервіс
```bash
cd ~/vpn_v2
./manager_v2.sh start
```

### Крок 3: Перевірити
```bash
./manager_v2.sh status
./test_routing.sh
```

## Rollback (якщо щось не так)

```bash
cd ~/vpn_v2
./manager_v2.sh stop

cd ~/vpn
./manager.sh start
```

## Очікуваний результат

```
Account 1 (arsen) - Tailscale:
  IP: 100.100.74.9
  Country: CH

Account 2 (lena) - Tor:
  IP: 185.xxx.xxx.xxx  (інший IP!)
  Country: CH
```

Portal meinungsplatz.ch побачить 2 різні пристрої!

