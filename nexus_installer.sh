#!/bin/bash

# Nexus Prover Node Installation Script (Private Version)
# Этот скрипт автоматизирует установку и управление prover node для Nexus Network с настройкой node-id.
# Используется только авторизованными пользователями с доступом к приватному GitHub-репозиторию.

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
    echo "Просто о сложных нодах (💸) — Приватная версия"
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
    sudo apt update
    check_status "Не удалось обновить систему"
    sudo apt install -y curl git screen build-essential pkg-config libssl-dev psmisc
    check_status "Не удалось установить базовые пакеты"
    
    # Проверка и установка Rust
    if ! command -v rustc &> /dev/null; then
        echo "Rust не установлен. Устанавливаем..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        check_status "Не удалось установить Rust"
        source "$HOME/.cargo/env"
    fi
    rustup update
    check_status "Не удалось обновить Rust"

    # Проверка и создание файла подкачки (swap)
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

    # Проверка зависимостей
    for cmd in pkg-config screen git curl rustc; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Ошибка: $cmd не установлен после попытки установки."
            exit 1
        fi
    done
    echo "Зависимости и swap-файл установлены."
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
    
    # Сборка проекта в режиме release
    cd "$project_dir/clients/cli"
    cargo build --release
    check_status "Не удалось собрать проект"
    echo "Проект установлен."
}

# Функция для запуска ноды
start_node() {
    echo "Создание сессии screen для ручного запуска ноды..."
    
    # Очистка старой сессии, если она существует
    if screen -list | grep -q "nexus_node"; then
        echo "Закрываем существующую сессию screen 'nexus_node'..."
        screen -X -S nexus_node quit
        sleep 2  # Короткая задержка перед созданием новой сессии
    fi
    
    # Создание новой сессии screen с увеличенным буфером
    screen -h 5000 -dmS nexus_node
    sleep 5  # Задержка, чтобы сессия стабилизировалась
    if ! screen -list | grep -q "nexus_node"; then
        echo "Ошибка: не удалось создать сессию screen."
        exit 1
    else
        echo "Сессия screen 'nexus_node' создана. Подождите 5-10 секунд, затем подключитесь через опцию 4 и выполните следующие команды:"
        echo "Выделите и скопируйте команды ниже, затем вставьте их в сессию screen (нажмите Ctrl+Shift+V или правую кнопку мыши):"
        echo "cd /root/.nexus/network_api/clients/cli"
        echo "source /root/.cargo/env"
        echo "cargo run --release -- start --env beta"
        echo "Затем введите '2' и ваш node-id (например, 'dEfAuLT1') для продолжения."
        echo "Логи доступны в сессии screen. Для отладки можно сохранить вывод в /tmp/nexus_node.log, запустив:"
        echo "cargo run --release -- start --env beta > /tmp/nexus_node.log 2>&1"
        echo "Используйте опцию 4 для подключения и ручного ввода."
        echo "Примечание: Этот скрипт доступен только авторизованным пользователям через приватный GitHub-репозиторий."
    fi
}

# Функция для получения информации о ноде
node_info() {
    echo "Проверка статуса ноды..."
    if screen -list | grep -q "nexus_node"; then
        echo "Нода запущена. Подключитесь с помощью опции 4 для просмотра логов."
        screen_pid=$(screen -ls | grep nexus_node | awk '{print $1}' | sed 's/\.//')
        if [ -n "$screen_pid" ]; then
            echo "PID сессии screen: $screen_pid"
            pstree -p "$screen_pid" | grep nexus-network >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                echo "Процесс nexus-network привязан к screen."
            else
                echo "Предупреждение: процесс nexus-network не найден в сессии screen. Проверьте 'ps aux | grep nexus-network'."
            fi
        fi
    else
        echo "Нода не запущена."
    fi
}

# Функция для удаления ноды
remove_node() {
    echo "Удаление ноды и всех данных..."
    if screen -list | grep -q "nexus_node"; then
        echo "Останавливаем сессию screen 'nexus_node'..."
        screen -S nexus_node -X quit
    fi
    sudo rm -rf /root/.nexus/network_api
    sudo rm -rf /root/.nexus
    sudo rm -f /swapfile
    if grep -q "/swapfile" /etc/fstab; then
        sudo sed -i '/\/swapfile/d' /etc/fstab
    fi
    check_status "Не удалось удалить директории, swap-файл или настройки"
    echo "Нода, конфигурация и swap-файл удалены."
}

# Основная функция установки ноды
install_node() {
    install_dependencies
    install_project
}

# Основной цикл с меню
print_welcome
while true; do
    echo ""
    echo -e "${GOLD}=== Меню установщика Nexus Prover Node ===${NC}"
    echo "1) 🚀 Установить ноду (зависимости, swap, проект)"
    echo "2) ▶ Создать сессию screen для ручного запуска ноды"
    echo "3) 📜 Проверить статус ноды"
    echo "4) 🔍 Подключиться к сессии screen для просмотра логов"
    echo "5) ⏏ Выйти из сессии screen, оставив ноду работать"
    echo "6) 🗑 Полностью удалить ноду и данные"
    echo "7) ❌ Выйти из скрипта"
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
            node_info
            ;;
        4)
            echo "Подключение к сессии screen для просмотра логов..."
            echo "Для выхода из сессии и возврата в меню нажмите Ctrl+A D."
            read -p "Нажмите Enter, чтобы подключиться к сессии screen..." -n 1 -s
            screen -r nexus_node
            ;;
        5)
            echo "Отсоединение от сессии screen, нода продолжит работать в фоновом режиме..."
            screen -d nexus_node
            echo "Сессия отсоединена. Вы можете выбрать другую опцию."
            ;;
        6)
            remove_node
            ;;
        7)
            echo "Выход из скрипта. До встречи!"
            exit 0
            ;;
        *)
            echo "Неверный выбор. Пожалуйста, введите число от 1 до 7."
            ;;
    esac
done
