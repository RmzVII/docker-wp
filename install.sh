#!/bin/bash
set -e

echo "============================================"
echo " 🚀 WSL WordPress Manager Installer"
echo "============================================"

# Update & install dependencies
sudo apt update -y
sudo apt install -y ca-certificates curl gnupg lsb-release lsof

# Docker install
echo "➡ Installing Docker..."
sudo install -m 0755 -d /etc/apt/keyrings || true
curl -fsSL https://download.docker.com/linux/ubuntu/gpg |
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update -y
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

sudo usermod -aG docker $USER || true

mkdir -p ~/projects
mkdir -p ~/.local/bin

# ---------------------------
# create_wp
# ---------------------------
cat > ~/.local/bin/create_wp <<'EOF'
#!/bin/bash
set -e

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "❗ Usage: create_wp <project_name> <port>"
    exit 1
fi

PROJECT="$1"
PORT="$2"
DIR="$HOME/projects/$PROJECT"

# Check if project exists
if [ -d "$DIR" ]; then
    echo "❌ Project '$PROJECT' already exists."
    exit 1
fi

# Check if port is free
if lsof -i :"$PORT" >/dev/null 2>&1; then
    echo "❌ Port $PORT is already in use."
    exit 1
fi

mkdir -p "$DIR/wp"
cd "$DIR"

# PHP config
cat > php.ini <<EOT
file_uploads = On
memory_limit = 512M
upload_max_filesize = 512M
post_max_size = 256M
max_execution_time = 600
max_input_time = 600
EOT

# Docker Compose
cat > docker-compose.yml <<EOT
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

echo "✅ Project '$PROJECT' created in $DIR"
echo "➡ Starting containers..."
docker compose up -d
echo "🌐 Visit: http://localhost:$PORT"
EOF
chmod +x ~/.local/bin/create_wp

# ---------------------------
# run
# ---------------------------
cat > ~/.local/bin/run <<'EOF'
#!/bin/bash
set -e

PROJECT="$1"
CMD="$2"
DIR="$HOME/projects/$PROJECT"
YML="$DIR/docker-compose.yml"

if [ ! -f "$YML" ]; then
    echo "❌ Project '$PROJECT' does not exist."
    exit 1
fi

case "$CMD" in
  start)
    echo "➡ Starting '$PROJECT'..."
    docker compose -f "$YML" up -d ;;
  stop)
    echo "➡ Stopping '$PROJECT'..."
    docker compose -f "$YML" down ;;
  restart)
    echo "➡ Restarting '$PROJECT'..."
    docker compose -f "$YML" down
    docker compose -f "$YML" up -d ;;
  logs)
    docker compose -f "$YML" logs -f ;;
  open)
    PORT=$(grep -oP '[0-9]+(?=:80)' "$YML")
    xdg-open "http://localhost:$PORT" ;;
  *)
    echo "Commands: start | stop | restart | logs | open"
    exit 1 ;;
esac
EOF
chmod +x ~/.local/bin/run

# ---------------------------
# wpmanager menu
# ---------------------------
cat > ~/.local/bin/wpmanager <<'EOF'
#!/bin/bash
while true; do
clear
echo "==============================="
echo "   WordPress Manager"
echo "==============================="
echo "1. Create new site"
echo "2. Start site"
echo "3. Stop site"
echo "4. Restart site"
echo "5. Delete site"
echo "6. List sites"
echo "7. Docker status"
echo "8. Cleanup all containers"
echo "0. Exit"
echo "-------------------------------"
read -p "Choice: " CH

case $CH in
  1)
    read -p "Project name: " NAME
    read -p "Port (e.g., 8081): " PORT
    create_wp "$NAME" "$PORT"
    read -p "Press Enter..." ;;
  2)
    read -p "Project name: " NAME
    run "$NAME" start
    read -p "Press Enter..." ;;
  3)
    read -p "Project name: " NAME
    run "$NAME" stop
    read -p "Press Enter..." ;;
  4)
    read -p "Project name: " NAME
    run "$NAME" restart
    read -p "Press Enter..." ;;
  5)
  read -p "Project name: " NAME
  DIR="$HOME/projects/$NAME"
  if [ ! -d "$DIR" ]; then
    echo "❌ Project '$NAME' does not exist."
    read -p "Press Enter..."
    continue
  fi
  echo "➡ Stopping and removing project '$NAME'..."
  
  # stop containers if exist
  docker compose -f "$DIR/docker-compose.yml" down 2>/dev/null || true
  
  # remove containers by name just in case
  docker rm -f "${NAME}_wp" "${NAME}_db" 2>/dev/null || true
  
  # remove volumes forcefully
  docker volume rm -f "${NAME}_db_data" 2>/dev/null || true
  
  # remove project folder (sudo to remove root-owned files)
  sudo rm -rf "$DIR"
  
  echo "✅ Project '$NAME' completely deleted."
  read -p "Press Enter..."
  ;;
  6)
    echo "📂 Projects:"
    ls "$HOME/projects"
    read -p "Press Enter..." ;;
  7)
    docker ps -a
    read -p "Press Enter..." ;;
  8)
    read -p "⚠ This will stop and remove ALL containers! Are you sure? (y/N): " CONF
    if [[ "$CONF" == "y" || "$CONF" == "Y" ]]; then
      docker stop $(docker ps -aq) 2>/dev/null || true
      docker rm $(docker ps -aq) 2>/dev/null || true
    fi
    read -p "Press Enter..." ;;
  0) exit 0 ;;
esac
done
EOF
chmod +x ~/.local/bin/wpmanager

echo "============================================"
echo " 🎉 Installation complete!"
echo ""
echo "➡ Run manager: wpmanager"
echo "➡ Create new site: create_wp project 8081"
echo "➡ Start/Stop site: run project start|stop|restart|logs|open"
echo "============================================"
