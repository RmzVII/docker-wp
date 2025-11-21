#!/bin/bash
set -e

echo "============================================"
echo " 🚀 Встановлення WSL WordPress Manager"
echo "============================================"

# Update system
sudo apt update -y
sudo apt install -y ca-certificates curl gnupg lsb-release lsof sudo

# Docker install
echo "➡ Встановлення Docker..."
sudo install -m 0755 -d /etc/apt/keyrings || true
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update -y
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker $USER || true

mkdir -p ~/projects
mkdir -p ~/.local/bin

# ----------------------------
# create_wp script
# ----------------------------
cat > ~/.local/bin/create_wp <<'EOF'
#!/bin/bash
set -e

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "❗ Використання: create_wp <ім'я_проєкту> <порт>"
    exit 1
fi

PROJECT="$1"
PORT="$2"
DIR="$HOME/projects/$PROJECT"

# Перевірка порта
if lsof -i TCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "❌ Порт $PORT вже використовується."
    exit 1
fi

# Перевірка назви проекту
if [ -d "$DIR" ]; then
    echo "❌ Проект '$PROJECT' вже існує."
    exit 1
fi

mkdir -p "$DIR/wp"
cd "$DIR"

# php.ini для WP
cat > php.ini <<EOT
file_uploads = On
memory_limit = 512M
upload_max_filesize = 512M
post_max_size = 256M
max_execution_time = 600
max_input_time = 600
EOT

# docker-compose.yml
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
      - "${PORT}:80"
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

# Запускаємо контейнер одразу
docker compose -f "$DIR/docker-compose.yml" up -d
echo "✅ Сайт '$PROJECT' створено та запущено: http://localhost:$PORT"
EOF

chmod +x ~/.local/bin/create_wp

# ----------------------------
# run script
# ----------------------------
cat > ~/.local/bin/run <<'EOF'
#!/bin/bash
set -e

PROJECT="$1"
CMD="$2"
DIR="$HOME/projects/$PROJECT"
YML="$DIR/docker-compose.yml"

if [ ! -f "$YML" ]; then
    echo "❌ Проект '$PROJECT' не знайдено."
    exit 1
fi

case "$CMD" in
  start) docker compose -f "$YML" up -d ;;
  stop) docker compose -f "$YML" down ;;
  restart) docker compose -f "$YML" down && docker compose -f "$YML" up -d ;;
  logs) docker compose -f "$YML" logs -f ;;
  open) xdg-open "http://localhost:$(grep -oP '[0-9]+(?=:80)' "$YML")" ;;
  *) echo "Команди: start | stop | restart | logs | open"; exit 1 ;;
esac
EOF

chmod +x ~/.local/bin/run

# ----------------------------
# wpmanager (menu)
# ----------------------------
cat > ~/.local/bin/wpmanager <<'EOF'
#!/bin/bash
while true; do
clear
echo "==============================="
echo "   WordPress Manager"
echo "==============================="
echo "1. Створити новий сайт"
echo "2. Запустити сайт"
echo "3. Зупинити сайт"
echo "4. Видалити сайт"
echo "5. Список сайтів"
echo "6. Статус Docker"
echo "7. Очистити всі контейнери"
echo "0. Вихід"
echo "-------------------------------"
read -p "Вибір: " CH

case $CH in
  1)
    read -p "Назва сайту: " NAME
    read -p "Порт (напр. 8081): " PORT
    create_wp "$NAME" "$PORT"
    read -p "Enter..."
    ;;
  2)
    read -p "Назва сайту: " NAME
    run "$NAME" start
    read -p "Enter..."
    ;;
  3)
    read -p "Назва сайту: " NAME
    run "$NAME" stop
    read -p "Enter..."
    ;;
  4)
    read -p "Назва сайту: " NAME
    DIR="$HOME/projects/$NAME"
    if [ ! -d "$DIR" ]; then
      echo "❌ Проект '$NAME' не існує."
      read -p "Enter..."
      continue
    fi
    echo "➡ Видаляємо '$NAME'..."
    docker compose -f "$DIR/docker-compose.yml" down 2>/dev/null || true
    docker rm -f "${NAME}_wp" "${NAME}_db" 2>/dev/null || true
    docker volume rm -f "${NAME}_db_data" 2>/dev/null || true
    sudo rm -rf "$DIR"
    echo "✅ '$NAME' видалено повністю."
    read -p "Enter..."
    ;;
  5)
    ls "$HOME/projects"
    read -p "Enter..."
    ;;
  6)
    docker ps -a
    read -p "Enter..."
    ;;
  7)
    docker stop $(docker ps -aq) 2>/dev/null || true
    docker rm -f $(docker ps -aq) 2>/dev/null || true
    read -p "Enter..."
    ;;
  0) exit 0 ;;
esac
done
EOF

chmod +x ~/.local/bin/wpmanager

echo "============================================"
echo " 🎉 Встановлення завершено!"
echo ""
echo "➡ Запуск менеджера сайтів:   wpmanager"
echo "➡ Створити новий сайт:       create_wp project 8081"
echo "➡ Запуск конкретного сайту:  run project start"
echo "============================================"
