#!/bin/bash

SITES_DIR="$HOME/wordpress_sites"

mkdir -p "$SITES_DIR"

check_port() {
    local PORT=$1
    if ss -tulpn 2>/dev/null | grep -q ":$PORT "; then
        return 1
    else
        return 0
    fi
}

create_site() {
    echo "Введи ім'я сайту (латиниця, без пробілів):"
    read SITENAME

    if [[ -z "$SITENAME" ]]; then
        echo "❌ Ім'я не може бути порожнім."
        return
    fi

    SITE_PATH="$SITES_DIR/$SITENAME"

    if [[ -d "$SITE_PATH" ]]; then
        echo "❌ Такий сайт вже існує."
        return
    fi

    echo "Введи порт (наприклад 8081):"
    read PORT

    if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
        echo "❌ Порт має бути числом."
        return
    fi

    if ! check_port "$PORT"; then
        echo "❌ Порт $PORT вже зайнятий!"
        return
    fi

    mkdir -p "$SITE_PATH"

    # Docker Compose
    cat > "$SITE_PATH/docker-compose.yml" <<EOF
services:
  db:
    image: mariadb:10.6
    container_name: ${SITENAME}_db
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: rootpass
      MYSQL_DATABASE: wpdb
      MYSQL_USER: wpuser
      MYSQL_PASSWORD: wppass
    volumes:
      - db_data:/var/lib/mysql

  wordpress:
    image: wordpress:php8.2-fpm
    container_name: ${SITENAME}_wp
    restart: always
    depends_on:
      - db
    environment:
      WORDPRESS_DB_HOST: db
      WORDPRESS_DB_USER: wpuser
      WORDPRESS_DB_PASSWORD: wppass
      WORDPRESS_DB_NAME: wpdb
    volumes:
      - wp_data:/var/www/html

  nginx:
    image: nginx:alpine
    container_name: ${SITENAME}_nginx
    ports:
      - "${PORT}:80"
    volumes:
      - wp_data:/var/www/html
      - ./nginx.conf:/etc/nginx/conf.d/default.conf

volumes:
  db_data:
  wp_data:
EOF

    # NGINX
    cat > "$SITE_PATH/nginx.conf" <<EOF
server {
    listen 80;
    root /var/www/html;

    index index.php index.html;

    location / {
        try_files \$uri /index.php?q=\$uri&\$args;
    }

    location ~ \.php$ {
        fastcgi_pass wordpress:9000;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOF

    cd "$SITE_PATH"
    docker compose up -d

    echo "✅ Сайт створено: http://localhost:${PORT}"
}

start_site() {
    echo "Вибери сайт для запуску:"
    ls "$SITES_DIR"
    read SITENAME
    SITE_PATH="$SITES_DIR/$SITENAME"

    if [[ ! -d "$SITE_PATH" ]]; then
        echo "❌ Немає такого сайту."
        return
    fi

    cd "$SITE_PATH"
    docker compose up -d
    echo "🚀 Сайт запущено."
}

stop_site() {
    echo "Вибери сайт для зупинки:"
    ls "$SITES_DIR"
    read SITENAME
    SITE_PATH="$SITES_DIR/$SITENAME"

    if [[ ! -d "$SITE_PATH" ]]; then
        echo "❌ Немає такого сайту."
        return
    fi

    cd "$SITE_PATH"
    docker compose stop
    echo "🛑 Сайт зупинено."
}

delete_site() {
    echo "Вибери сайт для видалення:"
    ls "$SITES_DIR"
    read SITENAME
    SITE_PATH="$SITES_DIR/$SITENAME"

    if [[ ! -d "$SITE_PATH" ]]; then
        echo "❌ Немає такого сайту."
        return
    fi

    cd "$SITE_PATH"
    docker compose down --volumes

    sudo rm -rf "$SITE_PATH"

    echo "🗑 Сайт видалено."
}

list_sites() {
    echo "📂 Сайти:"
    ls "$SITES_DIR"
}

while true; do
    echo ""
    echo "========== WordPress Manager =========="
    echo "1) Створити сайт"
    echo "2) Запустити сайт"
    echo "3) Зупинити сайт"
    echo "4) Видалити сайт"
    echo "5) Переглянути список сайтів"
    echo "6) Вихід"
    echo "========================================"
    read CHOICE

    case $CHOICE in
        1) create_site ;;
        2) start_site ;;
        3) stop_site ;;
        4) delete_site ;;
        5) list_sites ;;
        6) exit ;;
        *) echo "❌ Невірний вибір" ;;
    esac
done
