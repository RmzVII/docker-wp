#!/bin/bash
set -e

# =================================================
# WordPress Manager v4 (для WSL)
# =================================================

PROJECTS_DIR="$HOME/projects"
mkdir -p "$PROJECTS_DIR"

# ===================== FUNCTIONS =====================
create_wp() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo "❗ Використання: create_wp <ім'я_проєкту> <порт>"
        return 1
    fi

    PROJECT="$1"
    PORT="$2"
    DIR="$PROJECTS_DIR/$PROJECT"
    mkdir -p "$DIR/wp"

    echo "🚀 Створюємо сайт: $PROJECT на порту $PORT"
    echo "Директорія сайту: $DIR/wp"

    # php.ini
    cat > "$DIR/php.ini" <<EOT
file_uploads = On
memory_limit = 512M
upload_max_filesize = 512M
post_max_size = 256M
max_execution_time = 600
max_input_time = 600
EOT

    # docker-compose.yml
    cat > "$DIR/docker-compose.yml" <<EOT
version: "3.9"
services:
  db:
    image: mysql:8.0
    container_name: ${PROJECT}_db
    restart: always
    volumes:
      - ${PROJECT}_db_data:/var/lib/mysql
    environment:
      MYSQL_ROOT_PASSWORD: root
      MYSQL_DATABASE: wp_db
      MYSQL_USER: wpuser
      MYSQL_PASSWORD: Qwe1Asd2Zxc3
  wordpress:
    image: wordpress:php8.2-apache
    container_name: ${PROJECT}_wp
    depends_on:
      - db
    ports:
      - "$PORT:80"
    volumes:
      - ./wp:/var/www/html
      - ./php.ini:/usr/local/etc/php/conf.d/custom.ini
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_USER: wpuser
      WORDPRESS_DB_PASSWORD: Qwe1Asd2Zxc3
      WORDPRESS_DB_NAME: wp_db
volumes:
  ${PROJECT}_db_data:
EOT

    echo "✅ Сайт створено! Відкрий: http://localhost:$PORT"
}

run() {
    PROJECT="$1"
    CMD="$2"
    DIR="$PROJECTS_DIR/$PROJECT"
    YML="$DIR/docker-compose.yml"

    if [ ! -f "$YML" ]; then
        echo "❌ Проєкт $PROJECT не знайдено"
        return 1
    fi

    case "$CMD" in
        start) docker compose -f "$YML" up -d ;;
        stop) docker compose -f "$YML" down ;;
        restart)
            docker compose -f "$YML" down
            docker compose -f "$YML" up -d ;;
        logs) docker compose -f "$YML" logs -f ;;
        open)
            PORT=$(grep -oP '[0-9]+(?=:80)' "$YML")
            xdg-open "http://localhost:$PORT" ;;
        *) echo "Команди: start | stop | restart | logs | open"; return 1 ;;
    esac
}

list_sites() {
    echo "Список сайтів:"
    ls "$PROJECTS_DIR"
}

delete_site() {
    PROJECT="$1"
    DIR="$PROJECTS_DIR/$PROJECT"

    if [ -d "$DIR" ]; then
        echo "⚠️ Зупинка контейнерів сайту $PROJECT..."
        run "$PROJECT" stop 2>/dev/null || true

        echo "🗑 Видалення папки $DIR..."
        sudo rm -rf "$DIR"

        echo "✅ Сайт $PROJECT видалено"
    else
        echo "❌ Сайт $PROJECT не знайдено"
    fi
}

# ===================== MENU =====================
while true; do
    clear
    echo "==============================="
    echo "   WordPress Manager v4"
    echo "==============================="
    echo "1. Створити новий сайт"
    echo "2. Запустити сайт"
    echo "3. Зупинити сайт"
    echo "4. Видалити сайт"
    echo "5. Список сайтів"
    echo "6. Переглянути Docker статус"
    echo "7. Очистити всі контейнери"
    echo "0. Вихід"
    echo "-------------------------------"
    read -p "Вибір: " CH

    case $CH in
        1)
            read -p "Назва сайту: " NAME
            read -p "Порт (наприклад 8081): " PORT
            create_wp "$NAME" "$PORT"
            read -p "Натисніть Enter..."
            ;;
        2)
            read -p "Назва сайту: " NAME
            run "$NAME" start
            read -p "Натисніть Enter..."
            ;;
        3)
            read -p "Назва сайту: " NAME
            run "$NAME" stop
            read -p "Натисніть Enter..."
            ;;
        4)
            read -p "Назва сайту: " NAME
            delete_site "$NAME"
            read -p "Натисніть Enter..."
            ;;
        5)
            list_sites
            read -p "Натисніть Enter..."
            ;;
        6)
            docker ps -a
            read -p "Натисніть Enter..."
            ;;
        7)
            docker stop $(docker ps -aq) 2>/dev/null || true
            docker rm $(docker ps -aq) 2>/dev/null || true
            read -p "Натисніть Enter..."
            ;;
        0) exit 0 ;;
        *) echo "❌ Невірний вибір"; read -p "Натисніть Enter..." ;;
    esac
done
