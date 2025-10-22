# Промт для розгортання системи VPN v2 на хості 100.100.74.9

## Команди для клонування репозиторію:
```bash
git clone git@github.com:maxfraieho/vpn_v2.git
cd vpn_v2
```

## Оновлення з віддаленого репозиторію:
```bash
git pull origin master
```

## Інструкції з розгортання:
```bash
# Оновити пакети
pkg update && pkg upgrade -y

# Встановити необхідні пакети якщо не встановлені
pkg install -y tor python curl jq

# Встановити Python бібліотеки
pip install aiohttp aiohttp-socks requests

# Створити директорію для Tor
mkdir -p ~/vpn_v2/tor_data

# Запустити сервіси
bash manager_v2.sh start
```

## Тестування системи:
```bash
# Перевірити статус
bash manager_v2.sh status

# Тестування роутингу
bash test_routing.sh

# Діагностика
bash diagnostic.sh all

# Тестування API
bash test_api.sh
```

## Запуск системи:
```bash
# Старт
bash manager_v2.sh start

# Стоп
bash manager_v2.sh stop

# Перезапуск
bash manager_v2.sh restart

# Перевірка статусу
bash manager_v2.sh status
```