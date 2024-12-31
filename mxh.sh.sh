#!/bin/bash

# === Cài đặt Mastodon với Docker ===

# Thư mục chứa cấu hình và dữ liệu
INSTALL_DIR="/opt/mastodon"
ENV_FILE="$INSTALL_DIR/.env"
DOCKER_COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"

# Kiểm tra và cài đặt Docker
check_docker() {
  if ! command -v docker &> /dev/null; then
    echo "Docker chưa được cài đặt. Đang cài đặt Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
  else
    DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
    MIN_DOCKER_VERSION="20.10"
    if [ "$(printf '%s\n' "$MIN_DOCKER_VERSION" "$DOCKER_VERSION" | sort -V | head -n1)" != "$MIN_DOCKER_VERSION" ]; then
      echo "Docker phiên bản thấp hơn $MIN_DOCKER_VERSION. Đang nâng cấp..."
      curl -fsSL https://get.docker.com -o get-docker.sh
      sh get-docker.sh
      rm get-docker.sh
    else
      echo "Docker đã được cài đặt và đạt yêu cầu."
    fi
  fi
}

# Kiểm tra và dừng/xóa các container khác
clean_existing_containers() {
  echo "Kiểm tra các container hiện có..."
  CONTAINERS=$(docker ps -aq)
  if [ -n "$CONTAINERS" ]; then
    echo "Dừng và xóa các container hiện có..."
    docker stop $CONTAINERS
    docker rm $CONTAINERS
  else
    echo "Không có container nào đang chạy."
  fi
}

# Kiểm tra điều kiện máy chủ
check_server_requirements() {
  echo "Kiểm tra điều kiện máy chủ..."
  REQUIRED_MEMORY=2000000 # Yêu cầu tối thiểu 2GB RAM (kB)
  AVAILABLE_MEMORY=$(grep MemTotal /proc/meminfo | awk '{print $2}')

  if [ "$AVAILABLE_MEMORY" -lt "$REQUIRED_MEMORY" ]; then
    echo "Không đủ RAM. Máy chủ cần tối thiểu 2GB RAM."
    exit 1
  fi

  REQUIRED_DISK_SPACE=10000 # Yêu cầu tối thiểu 10GB dung lượng đĩa trống (MB)
  AVAILABLE_DISK_SPACE=$(df / | tail -1 | awk '{print $4}')

  if [ "$AVAILABLE_DISK_SPACE" -lt "$REQUIRED_DISK_SPACE" ]; then
    echo "Không đủ dung lượng đĩa. Máy chủ cần tối thiểu 10GB dung lượng trống."
    exit 1
  fi

  echo "Máy chủ đạt yêu cầu."
}

# Hỏi thông tin cấu hình từ người dùng
get_user_input() {
  read -p "Nhập tên miền của bạn (vd: mastodon.example.com): " LOCAL_DOMAIN
  read -p "Nhập mật khẩu cho PostgreSQL: " DB_PASS
  read -p "Nhập máy chủ SMTP: " SMTP_SERVER
  read -p "Nhập cổng SMTP (mặc định: 587): " SMTP_PORT
  SMTP_PORT=${SMTP_PORT:-587}
  read -p "Nhập tài khoản SMTP: " SMTP_LOGIN
  read -p "Nhập mật khẩu SMTP: " SMTP_PASSWORD
  read -p "Nhập địa chỉ email gửi thông báo: " SMTP_FROM_ADDRESS
}

# Gọi hàm để lấy thông tin từ người dùng
get_user_input

# Tạo thư mục cài đặt
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR" || exit 1

# Tạo tệp .env
cat <<EOL > "$ENV_FILE"
# Federation
LOCAL_DOMAIN=$LOCAL_DOMAIN

# Redis
REDIS_HOST=redis
REDIS_PORT=6379

# PostgreSQL
DB_HOST=db
DB_USER=mastodon
DB_NAME=mastodon_production
DB_PASS=$DB_PASS
DB_PORT=5432

# Elasticsearch (optional)
ES_ENABLED=true
ES_HOST=es
ES_PORT=9200
ES_USER=elastic
ES_PASS=elastic_password

# Secrets
SECRET_KEY_BASE=$(openssl rand -hex 64)
OTP_SECRET=$(openssl rand -hex 64)

# Encryption secrets
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=$(openssl rand -hex 32)
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=$(openssl rand -hex 32)
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=$(openssl rand -hex 32)

# Web Push
VAPID_PRIVATE_KEY=$(openssl rand -hex 64)
VAPID_PUBLIC_KEY=$(openssl rand -hex 64)

# Sending mail
SMTP_SERVER=$SMTP_SERVER
SMTP_PORT=$SMTP_PORT
SMTP_LOGIN=$SMTP_LOGIN
SMTP_PASSWORD=$SMTP_PASSWORD
SMTP_FROM_ADDRESS=$SMTP_FROM_ADDRESS

# File storage (optional)
S3_ENABLED=false
S3_BUCKET=
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
S3_ALIAS_HOST=

# IP and session retention
IP_RETENTION_PERIOD=31556952
SESSION_RETENTION_PERIOD=31556952
EOL

# Tạo tệp docker-compose.yml
cat <<EOL > "$DOCKER_COMPOSE_FILE"
version: "3.8"
services:
  mastodon:
    image: lscr.io/linuxserver/mastodon:latest
    container_name: mastodon
    env_file:
      - .env
    volumes:
      - ./config:/config
    ports:
      - 80:80
      - 443:443
    restart: unless-stopped
  redis:
    image: redis:alpine
    container_name: redis
    volumes:
      - ./redis:/data
    restart: unless-stopped
  db:
    image: postgres:13
    container_name: db
    environment:
      POSTGRES_USER: mastodon
      POSTGRES_PASSWORD: $DB_PASS
      POSTGRES_DB: mastodon_production
    volumes:
      - ./postgres:/var/lib/postgresql/data
    restart: unless-stopped
  es:
    image: docker.elastic.co/elasticsearch/elasticsearch:7.17.6
    container_name: es
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
    volumes:
      - ./elasticsearch:/usr/share/elasticsearch/data
    restart: unless-stopped
EOL

# Thực hiện kiểm tra và cài đặt
check_docker
clean_existing_containers
check_server_requirements

# Tải và khởi chạy container
docker-compose pull
docker-compose up -d

# Hiển thị trạng thái
docker-compose ps

# Kết thúc
echo "Cài đặt hoàn tất! Bạn có thể truy cập Mastodon tại http://$LOCAL_DOMAIN"
