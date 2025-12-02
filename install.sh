#!/usr/bin/env bash
set -euo pipefail

# ---------------------------
# Install / WP manager installer
# ---------------------------
# Default directory for sites (can be overridden by env SITES_DIR)
SITES_DIR="${SITES_DIR:-$HOME/projects}"
BIN_DIR="${HOME}/.local/bin"

echo "============================================"
echo "  WSL WordPress Manager installer"
echo "  Sites directory: $SITES_DIR"
echo "  Bin directory:    $BIN_DIR"
echo "============================================"

# ensure bin dir
mkdir -p "$BIN_DIR"
mkdir -p "$SITES_DIR"

# Install prerequisites (if missing)
command_exists() { command -v "$1" >/dev/null 2>&1; }

if ! command_exists docker; then
  echo "➡ Docker not found — installing (requires sudo)..."
  sudo apt update -y
  sudo apt install -y ca-certificates curl gnupg lsb-release lsof
  sudo install -m 0755 -d /etc/apt/keyrings || true
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt update -y
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  sudo usermod -aG docker "$USER" || true
  echo "✅ Docker installed. After install you may need to run: wsl --shutdown (in Windows) then re-open Ubuntu."
else
  echo "✅ Docker already installed."
fi

# Helper functions used by generated scripts (we'll embed versions in the scripts)
# ---------------------------
# create_wp (only asks name; port auto-chosen)
# ---------------------------
cat > "$BIN_DIR/create_wp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SITES_DIR="${SITES_DIR:-$HOME/projects}"

# find a free port in a range (tries 8000..8999)
find_free_port() {
  local p
  for p in $(seq 8000 8999); do
    # system-level check
    if ss -tulpn 2>/dev/null | grep -q ":${p} "; then
      continue
    fi
    # docker-level check: any container (running or stopped) with that published port
    if docker ps -a --format '{{.Ports}}' | grep -q ":${p}->"; then
      continue
    fi
    echo "$p"
    return 0
  done
  return 1
}

wait_db_ready() {
  local dbc="$1"
  local timeout=90
  local waited=0
  while true; do
    # try mysqladmin ping
    if docker exec "$dbc" sh -c "mysqladmin ping -uroot -proot >/dev/null 2>&1"; then
      return 0
    fi
    sleep 2
    waited=$((waited+2))
    if [ $waited -ge $timeout ]; then
      return 1
    fi
  done
}

if [ -z "${1:-}" ]; then
  echo "❗ Usage: create_wp <site_name>"
  exit 1
fi

SITE="$1"
if echo "$SITE" | grep -Eq '[^A-Za-z0-9_-]'; then
  echo "❌ Назва сайту може містити лише латинські літери, цифри, '_' або '-'"
  exit 1
fi

mkdir -p "$SITES_DIR"
SITE_DIR="$SITES_DIR/$SITE"
if [ -d "$SITE_DIR" ] && [ -f "$SITE_DIR/docker-compose.yml" ]; then
  echo "❌ Сайт '$SITE' вже існує."
  exit 1
fi

PORT=$(find_free_port) || { echo "❌ Не вдалось знайти вільний порт (8000-8999)"; exit 1; }

echo "➡ Створюю сайт '$SITE' на порту $PORT..."
mkdir -p "$SITE_DIR"

# create docker-compose.yml with unique volumes
cat > "$SITE_DIR/docker-compose.yml" <<YML
version: "3.9"
services:
  db:
    image: mysql:8.0
    container_name: ${SITE}_db
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: root
      MYSQL_DATABASE: ${SITE}
      MYSQL_USER: wpuser
      MYSQL_PASSWORD: wppass
    volumes:
      - ${SITE}_db_data:/var/lib/mysql

  wordpress:
    image: wordpress:php8.2-apache
    container_name: ${SITE}_wp
    depends_on:
      - db
    ports:
      - "${PORT}:80"
    volumes:
      - ./wp:/var/www/html
      - ./php.ini:/usr/local/etc/php/conf.d/custom.ini
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_USER: wpuser
      WORDPRESS_DB_PASSWORD: wppass
      WORDPRESS_DB_NAME: ${SITE}

volumes:
  ${SITE}_db_data:
YML

# create empty wp folder (WordPress will populate on first run)
mkdir -p "$SITE_DIR/wp"

# create custom php.ini for WordPress container
cat > "$SITE_DIR/php.ini" <<'PHPINI'
upload_max_filesize = 512M
post_max_size = 512M
memory_limit = 512M
max_execution_time = 300
PHPINI

echo "➡ Піднімаю контейнери..."
if docker compose -f "$SITE_DIR/docker-compose.yml" up -d; then
  echo "⏳ Чекаю, поки БД буде готова (timeout 90s)..."
  if wait_db_ready "${SITE}_db"; then
    echo "✅ Сайт '$SITE' створено і запущено: http://localhost:${PORT}"
  else
    echo "❗ БД не відповіла вчасно. Перевір логи: docker logs ${SITE}_db"
    echo "➡ Спробую прибрати частково створені ресурси..."
    docker compose -f "$SITE_DIR/docker-compose.yml" down -v --remove-orphans || true
  fi
else
  echo "❌ Помилка запуску контейнерів. Очищаю..."
  docker compose -f "$SITE_DIR/docker-compose.yml" down -v --remove-orphans || true
  rm -rf "$SITE_DIR"
  exit 1
fi
EOF
chmod +x "$BIN_DIR/create_wp"

# ---------------------------
# run (control) script
# ---------------------------
cat > "$BIN_DIR/run" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SITES_DIR="${SITES_DIR:-$HOME/projects}"

if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
  echo "❗ Usage: run <site_name> <start|stop|restart|logs|open>"
  exit 1
fi

SITE="$1"
CMD="$2"
SITE_DIR="$SITES_DIR/$SITE"
YML="$SITE_DIR/docker-compose.yml"

if [ ! -f "$YML" ]; then
  echo "❌ Site '$SITE' not found at $SITE_DIR"
  exit 1
fi

case "$CMD" in
  start)
    docker compose -f "$YML" up -d
    ;;
  stop)
    docker compose -f "$YML" down
    ;;
  restart)
    docker compose -f "$YML" down
    docker compose -f "$YML" up -d
    ;;
  logs)
    docker compose -f "$YML" logs -f
    ;;
  open)
    PORT=$(grep -oP '[0-9]+(?=:80)' "$YML" | head -n1)
    if [ -z "$PORT" ]; then
      echo "❗ Не вдалось визначити порт"
      exit 1
    fi
    xdg-open "http://localhost:$PORT" || echo "Відкрий у браузері: http://localhost:$PORT"
    ;;
  *)
    echo "Commands: start | stop | restart | logs | open"
    exit 1
    ;;
esac
EOF
chmod +x "$BIN_DIR/run"

# ---------------------------
# wpmanager menu
# ---------------------------
cat > "$BIN_DIR/wpmanager" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SITES_DIR="${SITES_DIR:-$HOME/projects}"

print_header() {
  echo "========================================"
  echo " WordPress Manager"
  echo " Sites dir: $SITES_DIR"
  echo "========================================"
}

list_sites() {
  mkdir -p "$SITES_DIR"
  echo "Projects in $SITES_DIR:"
  for d in "$SITES_DIR"/*/; do
    [ -d "$d" ] || continue
    dname="$(basename "$d")"
    if [ -f "$SITES_DIR/$dname/docker-compose.yml" ]; then
      echo " - $dname"
    fi
  done
}

delete_site_full() {
  read -r -p "Site name to delete: " SITE
  SITE_DIR="$SITES_DIR/$SITE"
  if [ ! -d "$SITE_DIR" ] || [ ! -f "$SITE_DIR/docker-compose.yml" ]; then
    echo "❌ Site not found: $SITE_DIR"
    return
  fi
  read -r -p "Are you SURE to permanently delete '$SITE'? (y/N): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Cancelled."
    return
  fi

  echo "➡ Stopping and removing containers (compose down -v)..."
  docker compose -f "$SITE_DIR/docker-compose.yml" down -v --remove-orphans || true

  echo "➡ Removing containers by name..."
  docker rm -f "${SITE}_wp" "${SITE}_db" 2>/dev/null || true

  echo "➡ Removing volumes by pattern..."
  docker volume ls --format '{{.Name}}' | grep -E "^${SITE}_" | xargs -r docker volume rm -f || true

  echo "➡ Removing site folder (may require sudo)..."
  sudo rm -rf "$SITE_DIR" || rm -rf "$SITE_DIR"

  echo "✅ Site '$SITE' fully removed."
}

print_menu() {
  echo ""
  echo "V1.1"
  echo "1) Create new site (no port input — auto-assigned)"
  echo "2) Start site"
  echo "3) Stop site"
  echo "4) Delete site (FULL remove)"
  echo "5) List sites"
  echo "6) Run cleanup (stop & remove all containers)  ⚠"
  echo "0) Exit"
  echo ""
}

while true; do
  print_header
  print_menu
  read -r -p "Choice: " CH
  case "$CH" in
    1)
      read -r -p "Site name (letters,digits,_,- only): " NAME
      "$HOME/.local/bin/create_wp" "$NAME" || true
      read -r -p "Press Enter..." _
      ;;
    2)
      read -r -p "Site name to start: " NAME
      "$HOME/.local/bin/run" "$NAME" start || true

      YML="$SITES_DIR/$NAME/docker-compose.yml"
      if [ -f "$YML" ]; then
        PORT=$(grep -oP '[0-9]+(?=:80)' "$YML" | head -n1)
        if [ -n "$PORT" ]; then
          echo "➡ Сайт запущено: http://localhost:$PORT"
        else
          echo "❗ Не можу знайти порт у $YML"
        fi
      fi

      read -r -p "Press Enter..." _
      ;;
    3)
      read -r -p "Site name to stop: " NAME
      "$HOME/.local/bin/run" "$NAME" stop || true
      read -r -p "Press Enter..." _
      ;;
    4)
      delete_site_full
      read -r -p "Press Enter..." _
      ;;
    5)
      list_sites
      read -r -p "Press Enter..." _
      ;;
    6)
      read -r -p "This will stop and remove ALL containers. Proceed? (y/N): " CONF
      if [[ "$CONF" == "y" || "$CONF" == "Y" ]]; then
        docker stop $(docker ps -aq) 2>/dev/null || true
        docker rm -f $(docker ps -aq) 2>/dev/null || true
      fi
      read -r -p "Press Enter..." _
      ;;
    0) exit 0 ;;
    *) echo "Invalid choice" ;;
  esac
done
EOF
chmod +x "$BIN_DIR/wpmanager"

echo "============================================"
echo " Installation complete!"
echo " - run: wpmanager"
echo " - create: create_wp <site_name>"
echo " - control: run <site_name> start|stop|restart|logs|open"
echo " Sites directory: $SITES_DIR"
echo "============================================"
