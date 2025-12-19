#!/bin/bash

#═══════════════════════════════════════════════════════════════════
#  LOG ROTATION SCRIPT
#  Автоматична ротація та архівування логів Watchdog
#═══════════════════════════════════════════════════════════════════

LOG_DIR="/opt/watchdog/logs"
ARCHIVE_DIR="$LOG_DIR/archive"
MAX_SIZE=10485760  # 10MB в байтах
KEEP_DAYS=30       # Зберігати архіви 30 днів

# Створюємо директорію для архівів
mkdir -p "$ARCHIVE_DIR"

echo "========================================"
echo "  LOG ROTATION START"
echo "========================================"
echo "Дата: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Функція для ротації одного лог-файлу
rotate_log() {
    local log_file="$1"
    local filename=$(basename "$log_file")
    
    if [ ! -f "$log_file" ]; then
        return
    fi
    
    # Отримуємо розмір файлу
    local size=$(stat -c%s "$log_file" 2>/dev/null || stat -f%z "$log_file" 2>/dev/null)
    
    if [ -z "$size" ]; then
        echo "⚠️  Не вдалося визначити розмір: $filename"
        return
    fi
    
    # Конвертуємо в MB для виводу
    local size_mb=$(echo "scale=2; $size / 1048576" | bc)
    
    if [ "$size" -gt "$MAX_SIZE" ]; then
        echo "📦 Архівування: $filename (розмір: ${size_mb}MB)"
        
        # Створюємо архівну назву з timestamp
        local timestamp=$(date '+%Y%m%d_%H%M%S')
        local archive_name="${filename%.log}_${timestamp}.log.gz"
        
        # Архівуємо
        if gzip -c "$log_file" > "$ARCHIVE_DIR/$archive_name"; then
            echo "   ✓ Створено архів: $archive_name"
            
            # Очищуємо оригінальний файл
            > "$log_file"
            echo "   ✓ Очищено оригінальний файл"
        else
            echo "   ✗ Помилка архівування"
        fi
    else
        echo "✓ $filename (${size_mb}MB) - не потребує ротації"
    fi
}

# Ротація основних логів
echo "Перевірка логів для ротації:"
echo ""

rotate_log "$LOG_DIR/watchdog.log"
rotate_log "$LOG_DIR/systemd.log"
rotate_log "$LOG_DIR/systemd-error.log"
rotate_log "$LOG_DIR/cron.log"

echo ""
echo "──────────────────────────────────────"
echo "Очищення старих архівів (старіші за $KEEP_DAYS днів):"
echo ""

# Видаляємо старі архіви
deleted_count=0
while IFS= read -r archive; do
    if [ -n "$archive" ]; then
        echo "🗑️  Видалено: $(basename "$archive")"
        rm "$archive"
        deleted_count=$((deleted_count + 1))
    fi
done < <(find "$ARCHIVE_DIR" -name "*.gz" -mtime +$KEEP_DAYS)

if [ $deleted_count -eq 0 ]; then
    echo "✓ Немає архівів для видалення"
else
    echo ""
    echo "Видалено архівів: $deleted_count"
fi

echo ""
echo "──────────────────────────────────────"
echo "Статистика архівів:"
echo ""

# Підрахунок архівів
archive_count=$(find "$ARCHIVE_DIR" -name "*.gz" | wc -l)
total_size=$(du -sh "$ARCHIVE_DIR" 2>/dev/null | cut -f1)

echo "📊 Всього архівів: $archive_count"
echo "💾 Загальний розмір: $total_size"

echo ""
echo "========================================"
echo "  LOG ROTATION COMPLETE"
echo "========================================"

exit 0