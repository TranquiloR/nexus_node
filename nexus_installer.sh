#!/bin/bash

# Цвета для вывода
GOLD='\033[1;33m' # Золотистый цвет для текста
NC='\033[0m'      # Сброс цвета

# Функция для вывода приветственного ASCII-арта "NEXUS NODE"
print_welcome() {
    clear
    echo -e "\033[40m\033[33m███████╗ █████╗ ███████╗██╗   ██╗    ███╗   ██║ ██████╗ ██████╗ ███████╗\033[0m"
    echo -e "\033[40m\033[33m██╔════╝██╔══██╗СС╔════╝╚СС╗ СС╔╝    СССС╗  СС║СС╔═══СС╗СС╔══СС╗СС╔════╝\033[0m"
    echo -e "\033[40m\033[33m█████╗  ███████║███████╗ ╚████╔╝     СС╔СС╗ СС║СС║   СС║СС║  СС║█████╗  \033[0m"
    echo -e "\033[40m\033[33mСС╔══╝  СС╔══СС║╚════СС║  ╚СС╔╝      СС║╚СС╗СС║СС║   СС║СС║  СС║СС╔══╝  \033[0m"
    echo -e "\033[40m\033[33m███████╗СС║  СС║███████║   СС║       СС║ ╚████║╚██████╔╝██████╔╝███████╗\033[0m"
    echo -e "\033[40m\033[33m╚══════╝╚═╝  ╚═╝╚══════╝   ╚═╝       ╚═╝  ╚═══╝ ╚═════╝ ╚═════╝ ╚══════╝\033[0m"
    echo ""
    echo "Просто о сложных нодах (💸) — Лучшая версия"
    sleep 2
}

# Функция для проверки успешности выполнения команды
check_status() {
    if [ $? -ne 0 ]; then
        echo "Ошибка: $1"
        exit 1
    fi
}

# Функция для установки зависимостей
install_dependencies() {
    echo "Установка зависимостей для Nexus Prover Node..."
    
    # Обновление списка пакетов
    sudo DEBIAN_FRONTEND=noninteractive apt update -y
    check_status "Не удалось обновить систему"
    
    # Проверка и установка needrestart
    if ! command -v needrestart &> /dev/null; then
        echo "Утилита needrestart не установлена. Устанавливаем..."
        sudo DEBIAN_FRONTEND=noninteractive apt install -y needrestart
        check_status "Не удалось установить needrestart"
    else
        echo "Утилита needrestart уже установлена."
    fi
    
    # Установка базовых пакетов
    sudo DEBIAN_FRONTEND=noninteractive apt install -y curl git screen build-essential pkg-config libssl-dev psmisc
    check_status "Не удалось установить базовые пакеты"
    
    # Установка Rust, если он не установлен
    if ! command -v rustc &> /dev/null; then
        echo "Rust не установлен. Устанавливаем..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        check_status "Не удалось установить Rust"
        source "$HOME/.cargo/env"
    fi
    rustup update
    check_status "Не удалось обновить Rust"
    
    # Автоматический перезапуск сервисов
    echo "Перезапуск сервисов, использующих устаревшие библиотеки..."
    sudo needrestart -r a
    check_status "Не удалось выполнить автоматический перезапуск сервисов"
    
    # Настройка swap-файла
    echo "Настройка файла подкачки (swap)..."
    if ! swapon --show | grep -q "/swapfile"; then
        echo "Создаем swap-файл размером 8 ГБ..."
        sudo fallocate -l 8G /swapfile
        check_status "Не удалось выделить место для swap-файла"
        sudo chmod 600 /swapfile
        check_status "Не удалось установить права на swap-файл"
        sudo mkswap /swapfile
        check_status "Не удалось настроить swap-файл"
        sudo swapon /swapfile
        check_status "Не удалось активировать swap-файл"
        if ! grep -q "/swapfile" /etc/fstab; then
            echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab
            check_status "Не удалось добавить swap в /etc/fstab"
        fi
        echo "Swap-файл размером 8 ГБ успешно создан и активирован."
    else
        echo "Swap-файл уже существует. Пропускаем создание."
    fi
    
    # Проверка установленных зависимостей
    for cmd in pkg-config screen git curl rustc needrestart; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Ошибка: $cmd не установлен после попытки установки."
            exit 1
        fi
    done
    echo "Все зависимости и swap-файл успешно установлены."
}

# Функция для установки проекта Nexus Network
install_project() {
    echo "Установка проекта Nexus Network..."
    local project_dir="/root/.nexus/network_api"
    
    if [ -d "$project_dir" ]; then
        if [ -d "$project_dir/.git" ]; then
            echo "Репозиторий уже существует. Обновляем с помощью git pull..."
            cd "$project_dir"
            git pull
            check_status "Не удалось обновить репозиторий"
        else
            echo "Директория существует, но не является репозиторием. Удаляем и клонируем заново..."
            sudo rm -rf "$project_dir"
            check_status "Не удалось удалить директорию"
            mkdir -p "$project_dir"
            cd "$project_dir"
            git clone https://github.com/nexus-xyz/network-api.git .
            check_status "Не удалось клонировать репозиторий"
        fi
    else
        echo "Директория не существует. Клонируем репозиторий..."
        mkdir -p "$project_dir"
        cd "$project_dir"
        git clone https://github.com/nexus-xyz/network-api.git .
        check_status "Не удалось клонировать репозиторий"
    fi
    
    # Сборка проекта
    cd "$project_dir/clients/cli"
    cargo build --release
    check_status "Не удалось собрать проект"
    echo "Проект успешно установлен."
}

# Функция для запуска ноды
start_node() {
    echo "Создание сессии screen для запуска ноды..."
    
    # Запрос node ID
    read -p "Введите ваш node ID (например, 'dEfAuLT1'): " node_id
    if [ -z "$node_id" ]; then
        echo "Ошибка: node ID не может быть пустым."
        exit 1
    fi
    
    # Сохранение node ID в правильный файл конфигурации
    mkdir -p /root/.nexus
    echo "$node_id" > /root/.nexus/node-id
    check_status "Не удалось сохранить node ID в /root/.nexus/node-id"
    echo "node ID сохранен в /root/.nexus/node-id"
    
    # Очистка старой сессии screen
    if screen -list | grep -q "nexus_node"; then
        echo "Закрываем существующую сессию screen 'nexus_node'..."
        screen -X -S nexus_node quit
        sleep 2
    fi
    
    # Создание новой сессии screen с неинтерактивным запуском
    screen -h 5000 -dmS nexus_node bash -c "cd /root/.nexus/network_api/clients/cli && source /root/.cargo/env && NONINTERACTIVE=1 cargo run --release -- start --env beta"
    sleep 5
    if ! screen -list | grep -q "nexus_node"; then
        echo "Ошибка: не удалось создать сессию screen."
        exit 1
    else
        echo "Нода запущена в сессии screen 'nexus_node'. Подключитесь через опцию 3 для просмотра логов."
    fi
}

# Функция для проверки статуса ноды
node_info() {
    echo "Проверка статуса ноды..."
    if screen -list | grep -q "nexus_node"; then
        echo "Нода запущена. Подключитесь с помощью опции 3 для просмотра логов."
    else
        echo "Нода не запущена."
    fi
}

# Функция для удаления ноды
remove_node() {
    echo "Удаление ноды и всех данных..."
    
    # Остановка сессии screen, если она активна
    if screen -list | grep -q "nexus_node"; then
        echo "Останавливаем сессию screen 'nexus_node'..."
        screen -S nexus_node -X quit
        sleep 2
    fi
    
    # Удаление директорий ноды
    sudo rm -rf /root/.nexus/network_api
    sudo rm -rf /root/.nexus
    
    # Отключение и удаление swap-файла
    if swapon --show | grep -q "/swapfile"; then
        echo "Отключаем swap-файл..."
        sudo swapoff /swapfile
        check_status "Не удалось отключить swap-файл"
    fi
    if [ -f "/swapfile" ]; then
        echo "Удаляем swap-файл..."
        sudo rm -f /swapfile
        check_status "Не удалось удалить swap-файл"
    fi
    
    # Удаление записи о swap из /etc/fstab
    if grep -q "/swapfile" /etc/fstab; then
        echo "Удаляем запись о swap-файле из /etc/fstab..."
        sudo sed -i '/\/swapfile/d' /etc/fstab
        check_status "Не удалось обновить /etc/fstab"
    fi
    
    echo "Нода и все данные успешно удалены."
}

# Основная функция установки
install_node() {
    install_dependencies
    install_project
}

# Основной цикл меню
print_welcome
echo -e "${GOLD}Для начала работы скрипта выберите пункт 1 и нажмите Enter${NC}"
while true; do
    echo ""
    echo -e "${GOLD}=== Меню установщика Nexus Prover Node ===${NC}"
    echo "1) 🚀 Установить ноду (зависимости, swap, проект)"
    echo "2) ▶ Запустить ноду с вашим node ID"
    echo "3) 🔍 Подключиться к сессии screen для просмотра логов"
    echo "4) 📜 Проверить статус ноды"
    echo "5) ⏏ Выйти из сессии screen, оставив ноду работать"
    echo "6) ❌ Выйти из скрипта"
    echo "7) 🗑 Полностью удалить ноду и данные"
    read -p "Выберите опцию: " choice
    echo ""
    
    case $choice in
        1)
            install_node
            ;;
        2)
            start_node
            ;;
        3)
            echo "Подключение к сессии screen. Для выхода нажмите Ctrl+A D."
            read -p "Нажмите Enter для подключения..." -n 1 -s
            screen -r nexus_node
            ;;
        4)
            node_info
            ;;
        5)
            echo "Отсоединение от сессии screen..."
            screen -d nexus_node
            echo "Сессия отсоединена."
            ;;
        6)
            echo "Выход из скрипта."
            exit 0
            ;;
        7)
            remove_node
            ;;
        *)
            echo "Неверный выбор. Введите число от 1 до 7."
            ;;
    esac
done
