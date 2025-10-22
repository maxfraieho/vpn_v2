#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Markdown to Embeddings Service - ОНОВЛЕНА ВЕРСІЯ v4.0
Сервіс для перетворення markdown файлів в embeddings
Версія: 4.0.0 (З виключенням сервісних файлів та копіюванням)
"""

import os
import sys
import shutil
import subprocess
from pathlib import Path
import json
from datetime import datetime

# Список сервісних файлів, які НЕ включаємо в результат
SERVICE_FILES = {
    'codetomd.py',
    'codetomd.bat', 
    'drakon_converter.py',
    'md_to_embeddings_service.py',
    'md_to_embeddings_service_v4.py',
    'md-to-embeddings-service.bat',
    'run_md_service.bat',
    '.gitignore',
    'package-lock.json',
    'yarn.lock',
    '.DS_Store',
    'Thumbs.db'
}

# Сервісні директорії для ігнорування
SERVICE_DIRS = {
    '.git', 
    'node_modules', 
    'venv', 
    '__pycache__', 
    '.vscode',
    '.idea', 
    'dist', 
    'build', 
    'target', 
    '.pytest_cache',
    'env',
    '.env'
}

def show_menu():
    """Показує головне меню програми"""
    print("\n" + "="*60)
    print("    🔧 MD TO EMBEDDINGS SERVICE v4.0 🔧")
    print("="*60)
    print("Виберіть варіант функціоналу:")
    print("1. 🚀 Розгорнути шаблон проєкту")
    print("2. 🔄 Конвертувати DRAKON схеми (.json → .md)")
    print("3. 📄 Створити узагальнюючий .md файл з коду проєкту")
    print("4. 📤 Копіювати .md файл до Dropbox/іншої директорії")
    print("5. 🚪 Вихід")
    print("="*60)

def option_1_deploy_template():
    """Варіант 1: Розгорнути шаблон проєкту"""
    print("\n" + "🚀"*20)
    print("--- ВАРІАНТ 1: Розгортання шаблону ---")
    print("🚀"*20)
    
    try:
        # Створюємо директорії
        directories = ["code", "drn", "srv"]
        print("📁 Створюємо директорії:")
        for directory in directories:
            Path(directory).mkdir(exist_ok=True)
            print(f"   ✓ {directory}/")
        
        # Створюємо базові файли
        print("\n📄 Створюємо базові файли:")
        
        # codetomd.py - неінтерактивна версія
        print("   📄 codetomd.py...")
        create_codetomd_file()
        print("   ✓ codetomd.py")
        
        # drakon_converter.py
        print("   📄 drakon_converter.py...")
        create_drakon_converter_file()
        print("   ✓ drakon_converter.py")
        
        # Створюємо README для кожної папки
        create_readme_files()
        
        print("\n✅ Шаблон проєкту успішно розгорнуто!")
        print("📋 Створено:")
        print("   - 📁 Директорії: code/, drn/, srv/")
        print("   - 📄 Файли: codetomd.py, drakon_converter.py")
        print("   - 📖 README файли для кожної директорії")
        
        return True
        
    except Exception as e:
        print(f"❌ Помилка при розгортанні шаблону: {e}")
        return False

def option_2_convert_drakon():
    """Варіант 2: Конвертувати DRAKON схеми"""
    print("\n" + "🔄"*20)
    print("--- ВАРІАНТ 2: Конвертація DRAKON схем ---")
    print("🔄"*20)
    
    drn_dir = Path("drn")
    if not drn_dir.exists():
        print("❌ ПОМИЛКА: Директорія drn/ не існує!")
        print("💡 Спочатку виберіть варіант 1 для розгортання шаблону.")
        return False
    
    # Знаходимо всі .json файли в папці drn
    json_files = list(drn_dir.glob("*.json"))
    
    if not json_files:
        print("🔭 У папці drn/ не знайдено .json файлів.")
        print("💡 Помістіть DRAKON схеми (.json) в папку drn/ та спробуйте знову.")
        return False
    
    print(f"📋 Знайдено {len(json_files)} файл(ів) для конвертації:")
    for json_file in json_files:
        print(f"   📄 {json_file.name}")
    
    converted_count = 0
    errors = []
    
    for json_file in json_files:
        try:
            print(f"\n📄 Конвертуємо: {json_file.name}")
            
            # Визначаємо назву вихідного .md файлу
            md_file = json_file.with_suffix('.md')
            
            # Запускаємо drakon_converter.py
            result = subprocess.run([
                sys.executable, "drakon_converter.py", 
                str(json_file), "-o", str(md_file)
            ], capture_output=True, text=True)
            
            if md_file.exists():
                print(f"   ✓ {md_file.name}")
                size = md_file.stat().st_size
                print(f"   📏 Розмір: {size:,} байт")
                converted_count += 1
            else:
                errors.append(f"{json_file.name}: Не вдалося створити файл")
                print(f"   ❌ {json_file.name}: Помилка конвертації")
                
        except Exception as e:
            errors.append(f"{json_file.name}: {str(e)}")
            print(f"   ❌ {json_file.name}: {str(e)}")
    
    print(f"\n📊 Результат конвертації:")
    print(f"   ✅ Успішно: {converted_count}")
    print(f"   ❌ Помилки: {len(errors)}")
    
    return converted_count > 0

def option_3_create_md():
    """Варіант 3: Створити .md файл з коду проєкту (БЕЗ сервісних файлів)"""
    print("\n" + "📄"*20)
    print("--- ВАРІАНТ 3: Створення узагальнюючого .md файлу ---")
    print("📄"*20)
    
    # Отримуємо назву поточної директорії
    current_dir = Path.cwd()
    project_name = current_dir.name
    output_file = f"{project_name}.md"
    
    print(f"📁 Поточна директорія: {current_dir}")
    print(f"📋 Назва проєкту: {project_name}")
    print(f"📄 Вихідний файл: {output_file}")
    print("\n⚠️ УВАГА: Сервісні файли будуть виключені з результату")
    
    try:
        print("\n📄 Створюємо .md файл...")
        
        # Визначаємо розширення файлів для включення
        valid_extensions = {'.py', '.js', '.ts', '.html', '.css', '.md', '.txt', 
                           '.yml', '.yaml', '.json', '.xml', '.sql', '.sh', '.bat',
                           '.jsx', '.tsx', '.vue', '.svelte', '.php', '.java', '.cs',
                           '.cpp', '.c', '.h', '.hpp', '.rb', '.go', '.rs', '.swift'}
        
        processed_files = 0
        total_size = 0
        skipped_files = 0
        
        with open(output_file, 'w', encoding='utf-8') as out:
            # Заголовок
            out.write(f"# Код проєкту: {project_name}\n\n")
            out.write(f"**Згенеровано:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            out.write(f"**Директорія:** `{os.path.abspath(current_dir)}`\n\n")
            out.write("---\n\n")
            
            # Структура проєкту (без сервісних файлів)
            out.write("## Структура проєкту\n\n")
            out.write("```\n")
            write_tree_structure(out, str(current_dir), SERVICE_DIRS)
            out.write("```\n\n")
            out.write("---\n\n")
            
            # Файли
            out.write("## Файли проєкту\n\n")
            
            for root, dirs, files in os.walk(current_dir):
                # Фільтруємо директорії
                dirs[:] = [d for d in dirs if d not in SERVICE_DIRS and not d.startswith('.')]
                
                for file_name in files:
                    # Пропускаємо сервісні файли
                    if file_name in SERVICE_FILES:
                        skipped_files += 1
                        print(f"⏭️ Пропущено (сервісний): {file_name}")
                        continue
                    
                    # Пропускаємо файли, що починаються з крапки (крім .env)
                    if file_name.startswith('.') and file_name != '.env':
                        skipped_files += 1
                        continue
                    
                    # Перевіряємо розширення
                    _, extension = os.path.splitext(file_name)
                    if extension.lower() not in valid_extensions:
                        continue
                    
                    # Пропускаємо сам результуючий файл
                    if file_name == output_file:
                        continue
                    
                    full_path = os.path.join(root, file_name)
                    relative_path = os.path.relpath(full_path, current_dir)
                    
                    try:
                        file_size = os.path.getsize(full_path)
                        
                        out.write(f"### {relative_path}\n\n")
                        out.write(f"**Розмір:** {file_size:,} байт\n\n")
                        
                        # Визначення мови для підсвічування
                        lang_map = {
                            '.py': 'python', '.js': 'javascript', '.ts': 'typescript',
                            '.html': 'html', '.css': 'css', '.yml': 'yaml', 
                            '.yaml': 'yaml', '.json': 'json', '.xml': 'xml',
                            '.sql': 'sql', '.sh': 'bash', '.bat': 'batch',
                            '.jsx': 'jsx', '.tsx': 'tsx', '.vue': 'vue',
                            '.php': 'php', '.java': 'java', '.cs': 'csharp',
                            '.cpp': 'cpp', '.c': 'c', '.rb': 'ruby',
                            '.go': 'go', '.rs': 'rust', '.swift': 'swift'
                        }
                        lang = lang_map.get(extension.lower(), 'text')
                        
                        out.write(f"```{lang}\n")
                        
                        with open(full_path, 'r', encoding='utf-8') as f:
                            content = f.read()
                            out.write(content)
                            if not content.endswith('\n'):
                                out.write('\n')
                            processed_files += 1
                            total_size += file_size
                            print(f"✅ Додано: {relative_path} ({file_size:,} байт)")
                            
                    except UnicodeDecodeError:
                        out.write(f"[Неможливо прочитати файл у форматі UTF-8]")
                        print(f"⚠️ ПОПЕРЕДЖЕННЯ: {relative_path} - помилка кодування")
                    except Exception as e:
                        out.write(f"[Помилка: {str(e)}]")
                        print(f"❌ ПОМИЛКА: {relative_path} - {str(e)}")
                    
                    out.write("\n```\n\n")
            
            # Статистика
            out.write("---\n\n")
            out.write("## Статистика\n\n")
            out.write(f"- **Оброблено файлів:** {processed_files}\n")
            out.write(f"- **Пропущено сервісних файлів:** {skipped_files}\n")
            out.write(f"- **Загальний розмір:** {total_size:,} байт ({total_size/1024:.1f} KB)\n")
            out.write(f"- **Дата створення:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        
        print(f"\n✅ Файл {output_file} успішно створено!")
        print(f"📄 Вміст проєкту зібрано в один markdown файл.")
        print(f"📊 Оброблено: {processed_files} файлів")
        print(f"⏭️ Пропущено сервісних: {skipped_files} файлів")
        print(f"📏 Загальний розмір: {total_size:,} байт ({total_size/1024:.1f} KB)")
        
        if Path(output_file).exists():
            size = Path(output_file).stat().st_size
            print(f"📏 Розмір результату: {size:,} байт ({size/1024:.1f} KB)")
        
        return True
        
    except Exception as e:
        print(f"❌ Помилка: {e}")
        return False

def option_4_copy_md():
    """Варіант 4: Копіювати .md файл до Dropbox або іншої директорії"""
    print("\n" + "📤"*20)
    print("--- ВАРІАНТ 4: Копіювання .md файлу ---")
    print("📤"*20)
    
    # Знаходимо всі .md файли в поточній директорії
    md_files = list(Path.cwd().glob("*.md"))
    
    if not md_files:
        print("❌ У поточній директорії не знайдено .md файлів")
        print("💡 Спочатку створіть .md файл (варіант 3)")
        return False
    
    print("📋 Знайдені .md файли:")
    for i, md_file in enumerate(md_files, 1):
        size = md_file.stat().st_size
        print(f"   {i}. {md_file.name} ({size:,} байт)")
    
    # Вибір файлу для копіювання
    if len(md_files) == 1:
        selected_file = md_files[0]
        print(f"\n📄 Автоматично вибрано: {selected_file.name}")
    else:
        try:
            choice = input(f"\n🔢 Виберіть файл для копіювання (1-{len(md_files)}): ").strip()
            idx = int(choice) - 1
            if 0 <= idx < len(md_files):
                selected_file = md_files[idx]
            else:
                print("❌ Невірний вибір")
                return False
        except ValueError:
            print("❌ Введіть число")
            return False
    
    # Директорія за замовчуванням
    default_dir = Path(r"C:\Users\tukro\Dropbox\Приложения\remotely-save\olena")
    
    print(f"\n📁 Директорія за замовчуванням:")
    print(f"   {default_dir}")
    
    custom_path = input("\n📂 Введіть шлях для копіювання (Enter для використання за замовчуванням): ").strip()
    
    if custom_path:
        target_dir = Path(custom_path)
    else:
        target_dir = default_dir
    
    # Перевірка існування директорії
    if not target_dir.exists():
        print(f"⚠️ Директорія не існує: {target_dir}")
        create = input("❓ Створити директорію? (y/n): ").strip().lower()
        if create == 'y':
            try:
                target_dir.mkdir(parents=True, exist_ok=True)
                print(f"✅ Директорію створено: {target_dir}")
            except Exception as e:
                print(f"❌ Не вдалося створити директорію: {e}")
                return False
        else:
            print("❌ Копіювання скасовано")
            return False
    
    # Копіювання файлу
    target_file = target_dir / selected_file.name
    
    try:
        # Якщо файл вже існує
        if target_file.exists():
            print(f"⚠️ Файл вже існує: {target_file}")
            overwrite = input("❓ Перезаписати? (y/n): ").strip().lower()
            if overwrite != 'y':
                # Створюємо унікальне ім'я
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                target_file = target_dir / f"{selected_file.stem}_{timestamp}{selected_file.suffix}"
                print(f"📝 Новий файл: {target_file.name}")
        
        shutil.copy2(selected_file, target_file)
        
        print(f"\n✅ Файл успішно скопійовано!")
        print(f"📤 Джерело: {selected_file}")
        print(f"📥 Призначення: {target_file}")
        
        # Перевірка розміру
        if target_file.exists():
            size = target_file.stat().st_size
            print(f"📏 Розмір: {size:,} байт")
        
        return True
        
    except Exception as e:
        print(f"❌ Помилка копіювання: {e}")
        return False

def write_tree_structure(out, root_dir, ignore_dirs, prefix="", max_depth=3, current_depth=0):
    """Записує структуру дерева файлів (без сервісних файлів)"""
    if current_depth >= max_depth:
        return
    
    try:
        items = sorted(os.listdir(root_dir))
        
        # Фільтруємо директорії та файли
        dirs = []
        files = []
        
        for item in items:
            item_path = os.path.join(root_dir, item)
            
            # Пропускаємо приховані елементи
            if item.startswith('.'):
                continue
                
            if os.path.isdir(item_path):
                if item not in ignore_dirs:
                    dirs.append(item)
            else:
                # Пропускаємо сервісні файли
                if item not in SERVICE_FILES:
                    files.append(item)
        
        # Виводимо директорії
        for i, directory in enumerate(dirs):
            is_last_dir = (i == len(dirs) - 1) and not files
            out.write(f"{prefix}{'└── ' if is_last_dir else '├── '}{directory}/\n")
            
            extension = "    " if is_last_dir else "│   "
            write_tree_structure(out, os.path.join(root_dir, directory), 
                                ignore_dirs, prefix + extension, max_depth, current_depth + 1)
        
        # Виводимо файли (максимум 10)
        display_files = files[:10]
        for i, file in enumerate(display_files):
            is_last = i == len(display_files) - 1
            out.write(f"{prefix}{'└── ' if is_last else '├── '}{file}\n")
        
        if len(files) > 10:
            out.write(f"{prefix}└── ... та ще {len(files) - 10} файлів\n")
            
    except PermissionError:
        out.write(f"{prefix}└── [Немає доступу]\n")

def create_codetomd_file():
    """Створює файл codetomd.py"""
    content = '''#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Code to Markdown Converter - Helper Script
"""

import os
import sys
from pathlib import Path
from datetime import datetime

# Список сервісних файлів для виключення
SERVICE_FILES = {
    'codetomd.py', 'codetomd.bat', 'drakon_converter.py',
    'md_to_embeddings_service.py', 'md_to_embeddings_service_v4.py',
    'md-to-embeddings-service.bat'
}

def main():
    root_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    project_name = Path(root_dir).resolve().name
    output_file = sys.argv[2] if len(sys.argv) > 2 else f"{project_name}.md"
    
    extensions = {'.py', '.js', '.ts', '.html', '.css', '.md', '.txt', '.json', '.yml', '.yaml'}
    ignore_dirs = {'.git', 'node_modules', 'venv', '__pycache__', '.vscode', '.idea'}
    
    with open(output_file, 'w', encoding='utf-8') as out:
        out.write(f"# {project_name}\\n\\n")
        out.write(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\\n\\n")
        
        count = 0
        for root, dirs, files in os.walk(root_dir):
            dirs[:] = [d for d in dirs if d not in ignore_dirs]
            for file in files:
                if file in SERVICE_FILES:
                    continue
                if Path(file).suffix in extensions:
                    filepath = os.path.join(root, file)
                    relpath = os.path.relpath(filepath, root_dir)
                    out.write(f"## {relpath}\\n\\n```\\n")
                    try:
                        with open(filepath, 'r', encoding='utf-8') as f:
                            out.write(f.read())
                            out.write("\\n```\\n\\n")
                            count += 1
                            print(f"Added: {relpath}")
                    except:
                        out.write("[Could not read file]\\n```\\n\\n")
        
        print(f"Processed {count} files")

if __name__ == "__main__":
    main()
'''
    
    with open("codetomd.py", "w", encoding="utf-8") as f:
        f.write(content)

def create_drakon_converter_file():
    """Створює файл drakon_converter.py"""
    content = '''#!/usr/bin/env python3
"""
DRAKON to Markdown Converter
"""

import json
import sys
from datetime import datetime

def convert_drakon_to_markdown(input_file, output_file=None):
    if not output_file:
        output_file = input_file.replace('.json', '.md')
    
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(f"# DRAKON Схема\\n\\n")
            f.write(f"**Джерело:** `{input_file}`\\n")
            f.write(f"**Конвертовано:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\\n\\n")
            
            nodes = data.get('nodes', {})
            f.write("## Вузли\\n\\n")
            for node_id, node_data in nodes.items():
                node_type = node_data.get('type', 'unknown')
                content = node_data.get('content', {})
                text = content.get('txt', '') if isinstance(content, dict) else str(content)
                f.write(f"- **{node_id}** ({node_type}): {text}\\n")
        
        print(f"Конвертовано: {output_file}")
        return True
        
    except Exception as e:
        print(f"Помилка: {e}")
        return False

def main():
    if len(sys.argv) < 2:
        print("Використання: python drakon_converter.py input.json [-o output.md]")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[3] if len(sys.argv) > 3 and sys.argv[2] == "-o" else None
    convert_drakon_to_markdown(input_file, output_file)

if __name__ == "__main__":
    main()
'''
    
    with open("drakon_converter.py", "w", encoding="utf-8") as f:
        f.write(content)

def create_readme_files():
    """Створює README файли для директорій"""
    
    readme_content = {
        "code": """# 📁 Code Directory

Директорія для збереження вихідного коду проєктів.

## Призначення
- Тимчасове збереження коду для аналізу
- Архівування версій коду
- Підготовка файлів для конвертації в markdown

## Використання
Помістіть сюди ваші проєкти для подальшого перетворення в markdown файли.
""",
        "drn": """# 📁 DRN Directory (DRAKON Files)

Директорія для DRAKON схем у форматі JSON.

## Призначення
- Збереження DRAKON схем (.json файли)
- Вхідні дані для конвертації в markdown

## Використання
1. Помістіть .json файли зі схемами в цю директорію
2. Запустіть варіант 2 в головному меню для конвертації
""",
        "srv": """# 📁 SRV Directory (Services)

Директорія для сервісних файлів та конфігурацій.

## Призначення
- Конфігураційні файли
- Допоміжні скрипти
- Логи та тимчасові файли
"""
    }
    
    for dirname, content in readme_content.items():
        readme_path = Path(dirname) / "README.md"
        try:
            with open(readme_path, "w", encoding="utf-8") as f:
                f.write(content)
            print(f"   ✓ {readme_path}")
        except Exception as e:
            print(f"   ❌ Помилка створення {readme_path}: {e}")

def main():
    """Головна функція програми"""
    print("🚀 Запуск MD to Embeddings Service v4.0")
    print("📅 Дата:", datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    print("📁 Робоча директорія:", Path.cwd())
    
    while True:
        try:
            show_menu()
            choice = input("\n👉 Введіть номер варіанту (1-5): ").strip()
            
            if choice == "1":
                success = option_1_deploy_template()
                if success:
                    input("\n✅ Натисніть Enter для продовження...")
                else:
                    input("\n❌ Натисніть Enter для продовження...")
            
            elif choice == "2":
                success = option_2_convert_drakon()
                if success:
                    input("\n✅ Натисніть Enter для продовження...")
                else:
                    input("\n❌ Натисніть Enter для продовження...")
            
            elif choice == "3":
                success = option_3_create_md()
                if success:
                    input("\n✅ Натисніть Enter для продовження...")
                else:
                    input("\n❌ Натисніть Enter для продовження...")
            
            elif choice == "4":
                success = option_4_copy_md()
                if success:
                    input("\n✅ Натисніть Enter для продовження...")
                else:
                    input("\n❌ Натисніть Enter для продовження...")
            
            elif choice == "5":
                print("\n👋 До побачення!")
                print("📊 Дякуємо за використання MD to Embeddings Service!")
                break
            
            else:
                print("\n❌ Неправильний вибір! Виберіть число від 1 до 5.")
                input("Натисніть Enter для продовження...")
        
        except KeyboardInterrupt:
            print("\n\n⚠️ Програму перервано користувачем.")
            print("👋 До побачення!")
            break
        except Exception as e:
            print(f"\n❌ Неочікувана помилка: {e}")
            input("Натисніть Enter для продовження...")

if __name__ == "__main__":
    main()