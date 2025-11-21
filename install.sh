#!/bin/bash
set -euo pipefail

SITES_DIR="$HOME/wordpress_sites"
mkdir -p "$SITES_DIR"

check_port() {
  local PORT=$1
  if ss -tulpn 2>/dev/null | grep -q ":${PORT} "; then
    return 1
  else
    return 0
  fi
}

wait_db_healthy() {
  local DB_CONTAINER="$1"
  local MAX_SECS=120
  local INTERVAL=2
  local waited=0

  echo "⏳ Чекаю, поки БД стане ready (max ${MAX_SECS}s)..."
  while true; do
    # перевіряємо статус health (якщо є)
    status=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$DB_CONTAINER" 2>/dev/null || true)
    if [[ "$status" == "healthy" ]]; then
      echo "✅ БД готова (healthy)."
      return 0
    fi

    # якщо немає health info — пробуємо mysqladmin ping
    if docker exec "$DB_CONTAINER" mysqladmin ping -uroot -prootpass --silent >/dev/null 2>&1; then
      echo "✅ БД відповідає на ping."
      return 0
    fi

    sleep $INTERVAL
    waited=$((waited + INTERVAL))
    if (( waited >= MAX_SECS )); then
      echo "❌ Таймаут очікування БД ($MAX_SECS s)."
      echo "Подивись логи БД: docker logs $DB_CONTAINER"
      return 1
    fi
  done
}

create_site() {
  read -p "Введи ім'я сайту (латиницею, без пробілів): " SITENAME
  if [[ -z "$SITENAME" ]]; then
    echo "❗ Ім'я не може бути пустим."
    return
  fi

  SITE_PATH="$SITES_DIR/$SITENAME"
  if [[ -d "$SITE_PATH" ]]; then
    echo "❗ Сайт '$SITENAME' вже існує у $SITE_PATH."
    return
  fi

  read -p "Введи порт (наприклад 8081): " PORT
  if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
    echo "❗ Порт має бути числом."
    return
  fi

  if ! check_port "$PORT"; then
    echo "❗ Порт $PORT вже зайнятий. Обери інший."
    return
  fi

  echo "📁 Створюю папку сайту: $SITE_PATH"
  mkdir -p "$SITE_PATH"

  echo "✍ Генерую docker-compose.yml ..."
  cat > "$SITE_PATH/docker-compose.yml" <<EOF
version: "3.9"
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
      - ${SITENAME}_db_data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-uroot", "-prootpass"]
      interval: 5s
      timeout: 3s
      retries: 10

  wordpress:
    image: wordpress:php8.2-fpm
    container_name: ${SITENAME}_wp
    restart: always
    depends_on:
      - db
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_USER: wpuser
      WORDPRESS_DB_PASSWORD: wppass
      WORDPRESS_DB_NAME: wpdb
    volumes:
      - ${SITENAME}_wp_data:/var/www/html

  nginx:
    image: nginx:alpine
    container_name: ${SITENAME}_nginx
    ports:
      - "${PORT}:80"
    volumes:
      - ${SITENAME}_wp_data:/var/www/html
      - ./nginx.conf:/etc/nginx/conf.d/default.conf
    depends_on:
      - wordpress

volumes:
  ${SITENAME}_db_data:
  ${SITENAME}_wp_data:
EOF

  cat > "$SITE_PATH/nginx.conf" <<'EOF'
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

  pushd "$SITE_PATH" >/dev/null
  echo "⬆ Піднімаю контейнери (docker compose up -d)..."
  docker compose up -d

  # Чекаємо, поки БД стане готовою
  if wait_db_healthy "${SITENAME}_db"; then
    echo "✅ Сайт створено і БД готова."
    echo "Відкрий: http://localhost:${PORT}"
  else
    echo "❗ Помилка: БД не стала ready. Подивись логи:"
    echo "docker compose -f $SITE_PATH/docker-compose.yml logs db --tail=200"
    echo "docker compose -f $SITE_PATH/docker-compose.yml logs wordpress --tail=200"
  fi
  popd >/dev/null
}

start_site() {
  read -p "Назва сайту для запуску: " SITENAME
  SITE_PATH="$SITES_DIR/$SITENAME"
  if [[ ! -f "$SITE_PATH/docker-compose.yml" ]]; then
    echo "❗ Сайт не знайдено: $SITE_PATH"
    return
  fi
  pushd "$SITE_PATH" >/dev/null
  echo "⬆ Запускаю контейнери..."
  docker compose up -d
  wait_db_healthy "${SITENAME}_db" || echo "❗ DB може бути не готова — перевір логи"
  popd >/dev/null
  echo "✅ Done."
}

stop_site() {
  read -p "Назва сайту для зупинки: " SITENAME
  SITE_PATH="$SITES_DIR/$SITENAME"
  if [[ ! -f "$SITE_PATH/docker-compose.yml" ]]; then
    echo "❗ Сайт не знайдено."
    return
  fi
  pushd "$SITE_PATH" >/dev/null
  echo "⬇ Зупиняю контейнери..."
  docker compose down
  popd >/dev/null
  echo "✅ Сайт зупинено."
}

delete_site() {
  read -p "Назва сайту для видалення: " SITENAME
  SITE_PATH="$SITES_DIR/$SITENAME"
  if [[ ! -d "$SITE_PATH" ]]; then
    echo "❗ Такого сайту немає."
    return
  fi

  pushd "$SITE_PATH" >/dev/null
  echo "⏳ Зупиняю і видаляю контейнери та томи..."
  docker compose down --volumes --remove-orphans || true

  popd >/dev/null
  echo "⏳ Видаляю папку сайту (якщо потрібні права, буде використано sudo)..."
  sudo rm -rf "$SITE_PATH" || { echo "❗ Не вдалося видалити папку без sudo. Спробуйте вручну."; return; }

  # також на підстраховку підчищаємо можливі залишкові томи з таким префіксом
  echo "🔎 Додатково очищаю томи з префіксом ${SITENAME}_..."
  docker volume ls -q | grep "^${SITENAME}_" | xargs -r docker volume rm

  echo "✅ Сайт $SITENAME повністю видалено."
}

list_sites() {
  echo "📂 Сайти у $SITES_DIR:"
  ls -1 "$SITES_DIR" || echo "(пусто)"
}

show_help() {
  echo ""
  echo "Меню: "
  echo "1) Створити сайт"
  echo "2) Запустити сайт"
  echo "3) Зупинити сайт"
  echo "4) Видалити сайт"
  echo "5) Список сайтів"
  echo "6) Вихід"
  echo ""
}

# Головне меню
while true; do
  show_help
  read -p "Вибір: " CHOICE
  case "$CHOICE" in
    1) create_site ;;
    2) start_site ;;
    3) stop_site ;;
    4) delete_site ;;
    5) list_sites ;;
    6) echo "Вихід."; exit 0 ;;
    *) echo "Невірний вибір." ;;
  esac
done
