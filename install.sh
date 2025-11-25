#!/bin/bash

BASE_DIR="$HOME/docker-wp"

mkdir -p "$BASE_DIR"

# ===========================
#  Перевірка зайнятості порту
# ===========================
check_port() {
    local PORT="$1"

    if [[ -z "$PORT" ]]; then
        echo "❌ Порт не може бути порожнім!"
        return 1
    fi

    if lsof -i :"$PORT" >/dev/null 2>&1; then
        echo "❌ Порт $PORT вже зайнятий!"
        return 1
    fi
    return 0
}

# ===========================
#  Перевірка існування сайту
# ===========================
site_exists() {
    local NAME="$1"

    if [[ -d "$BASE_DIR/$NAME" ]]; then
        echo "❌ Сайт '$NAME' вже існує!"
        return 1
    fi

    if docker ps -a --format '{{.Names}}' | grep -q "^${NAME}_" ; then
        echo "❌ Контейнери з назвою '$NAME' вже існують!"
        return 1
    fi
    return 0
}

# ===========================
#  Створення сайту
# ===========================
create_site() {
    read -rp "Назва сайту: " NAME
    [[ -z "$NAME" ]] && echo "❌ Назва не може бути порожня!" && return

    site_exists "$NAME" || return

    read -rp "Порт (напр. 8081): " PORT
    check_port "$PORT" || return

    echo "➡ Створюю сайт '$NAME'..."
    SITE_DIR="$BASE_DIR/$NAME"
    mkdir -p "$SITE_DIR"

    cat > "$SITE_DIR/docker-compose.yml" <<EOF
services:
  db:
    image: mysql:8.0
    container_name: ${NAME}_db
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: rootpass
      MYSQL_DATABASE: ${NAME}
      MYSQL_USER: ${NAME}
      MYSQL_PASSWORD: pass
    volumes:
      - ${NAME}_db_data:/var/lib/mysql

  wp:
    image: wordpress:php8.2-apache
    container_name: ${NAME}_wp
    restart: always
    ports:
      - "${PORT}:80"
    environment:
      WORDPRESS_DB_HOST: db
      WORDPRESS_DB_NAME: ${NAME}
      WORDPRESS_DB_USER: ${NAME}
      WORDPRESS_DB_PASSWORD: pass
    volumes:
      - ${NAME}_wp_data:/var/www/html

volumes:
  ${NAME}_db_data:
  ${NAME}_wp_data:
EOF

    cd "$SITE_DIR" || return

    echo "➡ Запускаю контейнери..."
    if ! docker compose up -d; then
        echo "❌ Помилка під час запуску! Очищаю..."
        docker compose down -v 2>/dev/null
        cd "$BASE_DIR" && rm -rf "$SITE_DIR"
        return
    fi

    echo "✅ Сайт '$NAME' створено!"
    echo "🌐 URL: http://localhost:${PORT}"
}

# ===========================
#  Запуск сайту
# ===========================
start_site() {
    read -rp "Назва сайту: " NAME
    [[ ! -d "$BASE_DIR/$NAME" ]] && echo "❌ Сайт не знайдено!" && return
    cd "$BASE_DIR/$NAME"
    docker compose up -d
    echo "✅ Сайт '$NAME' запущено!"
}

# ===========================
#  Зупинка сайту
# ===========================
stop_site() {
    read -rp "Назва сайту: " NAME
    [[ ! -d "$BASE_DIR/$NAME" ]] && echo "❌ Сайт не знайдено!" && return
    cd "$BASE_DIR/$NAME"
    docker compose down
    echo "⏹ Сайт '$NAME' зупинено!"
}

# ===========================
#  Повне видалення сайту
# ===========================
delete_site() {
    read -rp "Назва сайту: " NAME
    SITE_DIR="$BASE_DIR/$NAME"

    [[ ! -d "$SITE_DIR" ]] && echo "❌ Сайт не знайдено!" && return

    echo "⚠ Увага: все буде видалено остаточно!"
    read -rp "Впевнені? (y/N): " CONFIRM
    [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && echo "❌ Скасовано." && return

    cd "$SITE_DIR"

    echo "➡ Зупиняю та видаляю контейнери..."
    docker compose down -v 2>/dev/null

    echo "➡ Видаляю volumes..."
    docker volume rm ${NAME}_db_data ${NAME}_wp_data 2>/dev/null

    echo "➡ Видаляю директорію..."
    rm -rf "$SITE_DIR"

    echo "➡ Перевіряю orphan volumes..."
    docker volume ls --format '{{.Name}}' | grep "^${NAME}_" | xargs -r docker volume rm

    echo "✅ Сайт '$NAME' ПОВНІСТЮ видалено!"
}

# ===========================
#  Список сайтів
# ===========================
list_sites() {
    echo "📌 Сайти:"
    ls "$BASE_DIR"
    echo ""
}

# ===========================
#  Меню
# ===========================
while true; do
    echo ""
    echo "========== WP Manager =========="
    echo "1) Створити сайт"
    echo "2) Запустити сайт"
    echo "3) Зупинити сайт"
    echo "4) Видалити сайт"
    echo "5) Список сайтів"
    echo "6) Вихід"
    echo "================================"
    read -rp "Вибір: " CHOICE

    case "$CHOICE" in
        1) create_site ;;
        2) start_site ;;
        3) stop_site ;;
        4) delete_site ;;
        5) list_sites ;;
        6) exit 0 ;;
        *) echo "❌ Невірний вибір!" ;;
    esac
done
