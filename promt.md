# Розгортання виправлень VPN v2

## Контекст

Ти - Qwen Coder CLI, яка працює на сервері Termux (Android). Твоє завдання - безпечно оновити систему VPN v2 з виправленнями, які вже завантажені в git репозиторій.

## Поточна ситуація

- Сервер: Termux на Android
- Локація: `~/vpn_v2/`
- Git репозиторій: вже налаштований
- Статус: VPN v2 система частково працює (Tor OK, proxy та survey мають проблеми)
- Оновлення: доступні в git репозиторії (вже зроблено git push)

## Твої завдання (виконуй послідовно)

### КРОК 1: Перевірка поточного стану

```bash
cd ~/vpn_v2

# 1.1 Перевірити поточну гілку та статус
git status
git branch

# 1.2 Перевірити запущені процеси VPN
ps aux | grep -E "smart_proxy|survey_automation|tor" | grep -v grep

# 1.3 Перевірити які порти використовуються
netstat -tuln | grep -E ":(8888|8889|8090|9050)"

# 1.4 Вивести інформацію про поточний стан
echo "=== Поточний стан системи ==="
ls -lh *.py *.sh 2>/dev/null
echo ""
echo "=== Запущені процеси ==="
pgrep -fa "smart_proxy|survey|tor" || echo "Немає процесів VPN"
```

**Очікувана дія:** Збережи вивід для звіту. Якщо процеси запущені - продовжуй до КРОКУ 2.

---

### КРОК 2: Створення backup

```bash
cd ~/vpn_v2

# 2.1 Створити директорію для backup з timestamp
BACKUP_DIR=~/vpn_v2_backup_$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"

# 2.2 Копіювати всі важливі файли
cp -v *.py "$BACKUP_DIR/" 2>/dev/null
cp -v *.sh "$BACKUP_DIR/" 2>/dev/null
cp -v config.json "$BACKUP_DIR/" 2>/dev/null
cp -v torrc "$BACKUP_DIR/" 2>/dev/null
cp -v *.log "$BACKUP_DIR/" 2>/dev/null
cp -v *.pid "$BACKUP_DIR/" 2>/dev/null

# 2.3 Створити список файлів backup
ls -lh "$BACKUP_DIR/" > "$BACKUP_DIR/backup_manifest.txt"

# 2.4 Повідомити про успішний backup
echo "✅ Backup створено: $BACKUP_DIR"
ls -lh "$BACKUP_DIR/"
```

**Очікувана дія:** Переконайся, що backup створено успішно. Збережи шлях до backup.

---

### КРОК 3: Зупинка поточних сервісів

```bash
cd ~/vpn_v2

# 3.1 Зупинити всі процеси VPN (gracefully)
echo "🛑 Зупинка сервісів..."

# Знайти та зупинити процеси
for proc in "smart_proxy" "survey_automation"; do
    pids=$(pgrep -f "$proc")
    if [ ! -z "$pids" ]; then
        echo "Зупинка $proc (PIDs: $pids)"
        kill -15 $pids 2>/dev/null  # SIGTERM
        sleep 2
        # Force kill якщо ще працює
        kill -9 $pids 2>/dev/null
    fi
done

# Зупинити Tor окремо
tor_pid=$(pgrep -f "tor -f")
if [ ! -z "$tor_pid" ]; then
    echo "Зупинка Tor (PID: $tor_pid)"
    kill -15 $tor_pid 2>/dev/null
    sleep 2
    kill -9 $tor_pid 2>/dev/null
fi

# 3.2 Очистити PID файли
rm -f *.pid

# 3.3 Перевірити, що все зупинено
sleep 2
if pgrep -f "smart_proxy|survey_automation|tor -f" > /dev/null; then
    echo "❌ ПОМИЛКА: Деякі процеси ще працюють!"
    pgrep -fa "smart_proxy|survey_automation|tor -f"
    exit 1
else
    echo "✅ Всі сервіси зупинено"
fi
```

**Очікувана дія:** Переконайся, що всі процеси зупинені перед продовженням.

---

### КРОК 4: Отримання оновлень з Git

```bash
cd ~/vpn_v2

# 4.1 Перевірити поточні зміни
echo "📥 Перевірка оновлень..."
git fetch origin

# 4.2 Показати що буде оновлено
echo "=== Зміни які будуть застосовані ==="
git log HEAD..origin/master --oneline
echo ""
git diff HEAD..origin/master --stat

# 4.3 Виконати git pull
echo "🔄 Отримання оновлень..."
git pull origin master

# 4.4 Перевірити статус після pull
if [ $? -eq 0 ]; then
    echo "✅ Git pull успішний"
    git log -1 --oneline
else
    echo "❌ ПОМИЛКА: Git pull не вдався!"
    echo "Rollback до backup: $BACKUP_DIR"
    exit 1
fi

# 4.5 Перевірити які файли оновлено
echo ""
echo "=== Оновлені файли ==="
ls -lht --time-style=+"%Y-%m-%d %H:%M" *.py *.sh | head -10
```

**Очікувана дія:** Перевір що отримані файли:
- smart_proxy_v2_fixed.py
- survey_automation_v2_fixed.py
- manager_v2_fixed.sh
- diagnostic.sh
- quick_fix.sh

---

### КРОК 5: Встановлення залежностей

```bash
# 5.1 Перевірити та встановити Python пакети
echo "📦 Перевірка залежностей..."

missing_packages=()

for pkg in aiohttp aiohttp-socks requests beautifulsoup4 lxml; do
    pkg_import=$(echo $pkg | tr '-' '_')
    if ! python3 -c "import $pkg_import" 2>/dev/null; then
        missing_packages+=($pkg)
        echo "❌ Відсутній: $pkg"
    else
        echo "✅ Встановлено: $pkg"
    fi
done

# 5.2 Встановити відсутні пакети
if [ ${#missing_packages[@]} -gt 0 ]; then
    echo ""
    echo "🔧 Встановлення відсутніх пакетів: ${missing_packages[*]}"
    pip install --upgrade ${missing_packages[*]}
    
    if [ $? -eq 0 ]; then
        echo "✅ Залежності встановлено"
    else
        echo "❌ ПОМИЛКА: Не вдалося встановити залежності"
        exit 1
    fi
else
    echo "✅ Всі залежності вже встановлені"
fi

# 5.3 Перевірити остаточно
echo ""
echo "=== Фінальна перевірка залежностей ==="
python3 << 'EOF'
import sys
try:
    import aiohttp
    import aiohttp_socks
    import requests
    import bs4
    print("✅ Всі Python залежності доступні")
    sys.exit(0)
except ImportError as e:
    print(f"❌ ПОМИЛКА: {e}")
    sys.exit(1)
EOF
```

**Очікувана дія:** Переконайся що всі залежності встановлені.

---

### КРОК 6: Налаштування виконуваних прав

```bash
cd ~/vpn_v2

# 6.1 Зробити скрипти виконуваними
echo "🔑 Налаштування прав доступу..."

chmod +x manager_v2_fixed.sh 2>/dev/null && echo "✅ manager_v2_fixed.sh"
chmod +x diagnostic.sh 2>/dev/null && echo "✅ diagnostic.sh"
chmod +x quick_fix.sh 2>/dev/null && echo "✅ quick_fix.sh"
chmod +x test_routing.sh 2>/dev/null && echo "✅ test_routing.sh"

# 6.2 Перевірити права
echo ""
echo "=== Права виконання ==="
ls -lh *.sh | grep "x"
```

---

### КРОК 7: Діагностика перед запуском

```bash
cd ~/vpn_v2

# 7.1 Запустити діагностику
echo "🔍 Запуск діагностики..."

if [ -f diagnostic.sh ]; then
    ./diagnostic.sh all
    DIAG_EXIT=$?
    
    if [ $DIAG_EXIT -ne 0 ]; then
        echo "⚠️  ПОПЕРЕДЖЕННЯ: Діагностика виявила проблеми"
        echo "Продовжуємо з обережністю..."
    fi
else
    echo "⚠️  diagnostic.sh не знайдено, пропускаємо діагностику"
fi
```

---

### КРОК 8: Запуск оновленої системи

```bash
cd ~/vpn_v2

# 8.1 Запуск через manager
echo "🚀 Запуск оновленої системи..."

if [ -f manager_v2_fixed.sh ]; then
    ./manager_v2_fixed.sh start
    START_EXIT=$?
    
    if [ $START_EXIT -ne 0 ]; then
        echo "❌ ПОМИЛКА: Не вдалося запустити сервіси"
        echo "Перевір логи:"
        echo "  tail -n 50 ~/vpn_v2/proxy.log"
        echo "  tail -n 50 ~/vpn_v2/survey.log"
        echo "  tail -n 50 ~/vpn_v2/tor.log"
        exit 1
    fi
    
    # 8.2 Зачекати на ініціалізацію
    echo "⏳ Очікування ініціалізації (15 секунд)..."
    sleep 15
    
else
    echo "❌ ПОМИЛКА: manager_v2_fixed.sh не знайдено!"
    exit 1
fi
```

---

### КРОК 9: Тестування системи

```bash
cd ~/vpn_v2

echo "🧪 Тестування системи..."
echo ""

# 9.1 Перевірка статусу
echo "=== Статус сервісів ==="
./manager_v2_fixed.sh status
STATUS_EXIT=$?

# 9.2 Тестування роутингу
echo ""
echo "=== Тестування роутингу ==="
./manager_v2_fixed.sh test
TEST_EXIT=$?

# 9.3 Детальне тестування портів
echo ""
echo "=== Детальне тестування портів ==="

# Тест Tor
echo "Тест Tor (9050):"
tor_result=$(curl -s --connect-timeout 10 --socks5 127.0.0.1:9050 https://ipapi.co/json/)
if [ $? -eq 0 ]; then
    echo "$tor_result" | python3 -m json.tool | grep -E '"ip"|"country"'
    echo "✅ Tor працює"
else
    echo "❌ Tor не відповідає"
fi

echo ""

# Тест порту 8888
echo "Тест порту 8888 (Tailscale):"
port8888_result=$(curl -s --connect-timeout 10 -x http://127.0.0.1:8888 https://ipapi.co/json/)
if [ $? -eq 0 ]; then
    echo "$port8888_result" | python3 -m json.tool | grep -E '"ip"|"country"'
    echo "✅ Порт 8888 працює"
else
    echo "⚠️  Порт 8888 не відповідає (можливо інший порт вибрано)"
    # Перевірити лог для фактичного порту
    actual_port=$(grep -o "Port: [0-9]*" ~/vpn_v2/proxy.log | tail -1 | grep -o "[0-9]*")
    if [ ! -z "$actual_port" ]; then
        echo "Спроба з портом: $actual_port"
        curl -s --connect-timeout 10 -x http://127.0.0.1:$actual_port https://ipapi.co/json/ | python3 -m json.tool | grep -E '"ip"|"country"'
    fi
fi

echo ""

# Тест порту 8889
echo "Тест порту 8889 (Tor через proxy):"
port8889_result=$(curl -s --connect-timeout 10 -x http://127.0.0.1:8889 https://ipapi.co/json/)
if [ $? -eq 0 ]; then
    echo "$port8889_result" | python3 -m json.tool | grep -E '"ip"|"country"'
    echo "✅ Порт 8889 працює"
else
    echo "⚠️  Порт 8889 не відповідає (можливо інший порт вибрано)"
fi

echo ""

# 9.4 Тест Survey API
echo "=== Тест Survey API (8090) ==="
survey_status=$(curl -s --connect-timeout 5 http://127.0.0.1:8090/status)
if [ $? -eq 0 ]; then
    echo "$survey_status" | python3 -m json.tool
    echo "✅ Survey API працює"
else
    echo "⚠️  Survey API не відповідає"
fi
```

---

### КРОК 10: Фінальний звіт

```bash
cd ~/vpn_v2

echo ""
echo "════════════════════════════════════════════"
echo "📊 ФІНАЛЬНИЙ ЗВІТ РОЗГОРТАННЯ"
echo "════════════════════════════════════════════"
echo ""

# 10.1 Інформація про backup
echo "💾 Backup: $BACKUP_DIR"
echo "   Файли backup:"
ls -lh "$BACKUP_DIR/" | tail -n +2

echo ""

# 10.2 Оновлені файли
echo "📝 Оновлені файли:"
git log -1 --stat

echo ""

# 10.3 Статус сервісів
echo "🔄 Статус сервісів:"
./manager_v2_fixed.sh status 2>&1 | grep -E "✓|✗|Port|Country"

echo ""

# 10.4 Перевірка портів
echo "🔌 Активні порти:"
netstat -tuln 2>/dev/null | grep -E ":(8888|8889|8090|9050)" || echo "  Немає активних портів VPN"

echo ""

# 10.5 Останні логи (перевірка помилок)
echo "📋 Останні логи (помилки):"
echo "  Proxy:"
grep -i "error" ~/vpn_v2/proxy.log 2>/dev/null | tail -3 || echo "    Немає помилок"
echo "  Survey:"
grep -i "error" ~/vpn_v2/survey.log 2>/dev/null | tail -3 || echo "    Немає помилок"
echo "  Tor:"
grep -i "error\|warn" ~/vpn_v2/tor.log 2>/dev/null | tail -3 || echo "    Немає попереджень"

echo ""

# 10.6 Фінальний висновок
if [ $STATUS_EXIT -eq 0 ] && [ $TEST_EXIT -eq 0 ]; then
    echo "════════════════════════════════════════════"
    echo "✅ РОЗГОРТАННЯ УСПІШНЕ!"
    echo "════════════════════════════════════════════"
    echo ""
    echo "Система VPN v2 оновлена та працює."
    echo ""
    echo "Команди для управління:"
    echo "  ~/vpn_v2/manager_v2_fixed.sh status"
    echo "  ~/vpn_v2/manager_v2_fixed.sh test"
    echo "  ~/vpn_v2/manager_v2_fixed.sh logs proxy"
    echo "  ~/vpn_v2/diagnostic.sh all"
else
    echo "════════════════════════════════════════════"
    echo "⚠️  РОЗГОРТАННЯ З ПОПЕРЕДЖЕННЯМИ"
    echo "════════════════════════════════════════════"
    echo ""
    echo "Деякі сервіси можуть не працювати коректно."
    echo "Перевірте логи для деталей:"
    echo "  tail -n 100 ~/vpn_v2/proxy.log"
    echo "  tail -n 100 ~/vpn_v2/survey.log"
    echo "  tail -n 100 ~/vpn_v2/tor.log"
    echo ""
    echo "Rollback до попередньої версії:"
    echo "  cd ~/vpn_v2"
    echo "  ./manager_v2_fixed.sh stop"
    echo "  cp -v $BACKUP_DIR/* ."
    echo "  ./manager_v2.sh start  # або manager_v2_fixed.sh"
fi

echo ""
echo "════════════════════════════════════════════"
```

---

## Важливі примітки для Qwen CLI

### Якщо щось піде не так:

1. **Не паніку** - є backup у `~/vpn_v2_backup_TIMESTAMP/`
2. **Перевір логи** у `~/vpn_v2/*.log`
3. **Rollback:**
   ```bash
   cd ~/vpn_v2
   ./manager_v2_fixed.sh stop
   cp -v ~/vpn_v2_backup_TIMESTAMP/* .
   ```

### Очікувані результати:

- ✅ Всі 3 сервіси запущені (Tor, Proxy, Survey)
- ✅ Порти 8888, 8889 працюють (або інші автоматично вибрані)
- ✅ Різні IP для різних портів
- ✅ Обидва IP швейцарські (CH)

### Якщо тести не проходять:

1. Перевір `./diagnostic.sh all`
2. Прочитай `./manager_v2_fixed.sh logs proxy`
3. Перевір чи Tor підключений до Швейцарії
4. Перезапусти: `./manager_v2_fixed.sh restart`

---

## Формат звіту який ти маєш надати

```
ЗВІТ РОЗГОРТАННЯ VPN V2
========================

1. BACKUP: <шлях до backup>
2. GIT PULL: <успіх/помилка>
3. ОНОВЛЕНІ ФАЙЛИ: <список>
4. ЗАЛЕЖНОСТІ: <статус>
5. ЗАПУСК: <успіх/помилка>
6. СТАТУС СЕРВІСІВ:
   - Tor: <OK/FAILED>
   - Proxy: <OK/FAILED>
   - Survey: <OK/FAILED>
7. ТЕСТИ:
   - Tor connection: <OK/FAILED>
   - Port 8888: <OK/FAILED> - IP: <xxx> Country: <xx>
   - Port 8889: <OK/FAILED> - IP: <yyy> Country: <yy>
   - Survey API: <OK/FAILED>
8. ВИСНОВОК: <УСПІШНО/ПОМИЛКИ/ПОПЕРЕДЖЕННЯ>
9. ЛОГИ ПОМИЛОК: <якщо є>
```

---

## Виконання

Виконуй всі кроки послідовно. Після кожного кроку перевіряй статус виконання. У разі критичної помилки - зупинись та повідом про проблему з деталями логів.