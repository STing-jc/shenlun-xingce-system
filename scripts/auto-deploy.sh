#!/bin/bash
# 申论行测学习系统 - 自动化部署脚本
# 版本: v2.0.0
# 描述: 一键自动化部署脚本

set -e

# ============================================================================
# 配置变量
# ============================================================================

# 应用配置
APP_NAME="${APP_NAME:-shenlun-xingce-system}"
APP_VERSION="${APP_VERSION:-2.0.0}"
APP_PORT="${APP_PORT:-3000}"
APP_HOME="${APP_HOME:-/app}"
DATA_PATH="${DATA_PATH:-/app/data}"
LOG_PATH="${LOG_PATH:-/app/logs}"
BACKUP_PATH="${BACKUP_PATH:-/app/backups}"

# 部署配置
DEPLOY_ENV="${DEPLOY_ENV:-production}"
DEPLOY_USER="${DEPLOY_USER:-app}"
DEPLOY_GROUP="${DEPLOY_GROUP:-app}"
DOMAIN_NAME="${DOMAIN_NAME:-localhost}"
SSL_ENABLED="${SSL_ENABLED:-false}"
SSL_EMAIL="${SSL_EMAIL:-admin@example.com}"

# 数据库配置
DB_TYPE="${DB_TYPE:-file}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-shenlun_system}"
DB_USER="${DB_USER:-app_user}"
DB_PASSWORD="${DB_PASSWORD:-}"
DB_INSTALL="${DB_INSTALL:-false}"

# Redis配置
REDIS_ENABLED="${REDIS_ENABLED:-false}"
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"
REDIS_INSTALL="${REDIS_INSTALL:-false}"

# 监控配置
MONITORING_ENABLED="${MONITORING_ENABLED:-true}"
PROMETHEUS_ENABLED="${PROMETHEUS_ENABLED:-false}"
GRAFANA_ENABLED="${GRAFANA_ENABLED:-false}"

# 备份配置
BACKUP_ENABLED="${BACKUP_ENABLED:-true}"
BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-0 2 * * *}"
BACKUP_RETENTION="${BACKUP_RETENTION:-7}"

# 安全配置
SECURITY_HARDENING="${SECURITY_HARDENING:-true}"
FIREWALL_ENABLED="${FIREWALL_ENABLED:-true}"
FAIL2BAN_ENABLED="${FAIL2BAN_ENABLED:-true}"

# 性能优化
PERFORMANCE_OPTIMIZATION="${PERFORMANCE_OPTIMIZATION:-true}"
AUTO_SCALING="${AUTO_SCALING:-false}"

# 部署选项
SKIP_DEPENDENCIES="${SKIP_DEPENDENCIES:-false}"
SKIP_SECURITY="${SKIP_SECURITY:-false}"
SKIP_OPTIMIZATION="${SKIP_OPTIMIZATION:-false}"
SKIP_MONITORING="${SKIP_MONITORING:-false}"
FORCE_REINSTALL="${FORCE_REINSTALL:-false}"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================================================
# 工具函数
# ============================================================================

# 日志函数
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_PATH/deploy.log"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    log "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

log_deploy() {
    log "${PURPLE}[DEPLOY]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [ "$(id -u)" != "0" ]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
}

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 检查操作系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
        DISTRO=$ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si)
        VER=$(lsb_release -sr)
        DISTRO=$(echo "$OS" | tr '[:upper:]' '[:lower:]')
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        OS=$DISTRIB_ID
        VER=$DISTRIB_RELEASE
        DISTRO=$(echo "$OS" | tr '[:upper:]' '[:lower:]')
    elif [ -f /etc/debian_version ]; then
        OS=Debian
        VER=$(cat /etc/debian_version)
        DISTRO="debian"
    elif [ -f /etc/redhat-release ]; then
        OS=RedHat
        DISTRO="rhel"
    else
        OS=$(uname -s)
        VER=$(uname -r)
        DISTRO="unknown"
    fi
    
    log_info "检测到操作系统: $OS $VER ($DISTRO)"
}

# 获取包管理器
get_package_manager() {
    if command_exists apt-get; then
        PKG_MANAGER="apt-get"
        PKG_UPDATE="apt-get update"
        PKG_INSTALL="apt-get install -y"
    elif command_exists yum; then
        PKG_MANAGER="yum"
        PKG_UPDATE="yum update -y"
        PKG_INSTALL="yum install -y"
    elif command_exists dnf; then
        PKG_MANAGER="dnf"
        PKG_UPDATE="dnf update -y"
        PKG_INSTALL="dnf install -y"
    elif command_exists pacman; then
        PKG_MANAGER="pacman"
        PKG_UPDATE="pacman -Sy"
        PKG_INSTALL="pacman -S --noconfirm"
    else
        log_error "不支持的包管理器"
        exit 1
    fi
    
    log_info "使用包管理器: $PKG_MANAGER"
}

# 创建用户和组
create_app_user() {
    if ! id "$DEPLOY_USER" &>/dev/null; then
        log_info "创建应用用户: $DEPLOY_USER"
        useradd -r -s /bin/bash -d "$APP_HOME" -m "$DEPLOY_USER"
    else
        log_info "应用用户已存在: $DEPLOY_USER"
    fi
    
    if ! getent group "$DEPLOY_GROUP" &>/dev/null; then
        log_info "创建应用组: $DEPLOY_GROUP"
        groupadd "$DEPLOY_GROUP"
    else
        log_info "应用组已存在: $DEPLOY_GROUP"
    fi
    
    usermod -a -G "$DEPLOY_GROUP" "$DEPLOY_USER"
}

# 创建目录结构
create_directories() {
    log_info "创建目录结构..."
    
    local directories=(
        "$APP_HOME"
        "$DATA_PATH"
        "$LOG_PATH"
        "$BACKUP_PATH"
        "$APP_HOME/config"
        "$APP_HOME/scripts"
        "$APP_HOME/tmp"
        "/etc/$APP_NAME"
        "/var/log/$APP_NAME"
    )
    
    for dir in "${directories[@]}"; do
        mkdir -p "$dir"
        chown "$DEPLOY_USER:$DEPLOY_GROUP" "$dir"
        chmod 755 "$dir"
        log_info "创建目录: $dir"
    done
}

# 等待服务启动
wait_for_service() {
    local service_name="$1"
    local port="$2"
    local timeout="${3:-60}"
    local count=0
    
    log_info "等待服务启动: $service_name (端口: $port)"
    
    while [ $count -lt $timeout ]; do
        if netstat -tln | grep -q ":$port "; then
            log_success "服务 $service_name 已启动"
            return 0
        fi
        
        sleep 1
        count=$((count + 1))
        
        if [ $((count % 10)) -eq 0 ]; then
            log_info "等待服务启动... ($count/$timeout)"
        fi
    done
    
    log_error "服务 $service_name 启动超时"
    return 1
}

# ============================================================================
# 依赖安装函数
# ============================================================================

# 更新系统
update_system() {
    log_info "更新系统包..."
    $PKG_UPDATE
    log_success "系统包更新完成"
}

# 安装基础依赖
install_base_dependencies() {
    log_info "安装基础依赖..."
    
    local base_packages=()
    
    if [ "$DISTRO" = "ubuntu" ] || [ "$DISTRO" = "debian" ]; then
        base_packages=(
            "curl" "wget" "git" "unzip" "tar" "gzip"
            "build-essential" "software-properties-common"
            "apt-transport-https" "ca-certificates" "gnupg" "lsb-release"
            "htop" "iotop" "netstat-nat" "tcpdump" "strace"
            "logrotate" "cron" "rsync" "bc"
        )
    elif [ "$DISTRO" = "centos" ] || [ "$DISTRO" = "rhel" ] || [ "$DISTRO" = "fedora" ]; then
        base_packages=(
            "curl" "wget" "git" "unzip" "tar" "gzip"
            "gcc" "gcc-c++" "make" "epel-release"
            "htop" "iotop" "net-tools" "tcpdump" "strace"
            "logrotate" "cronie" "rsync" "bc"
        )
    fi
    
    for package in "${base_packages[@]}"; do
        $PKG_INSTALL "$package"
    done
    
    log_success "基础依赖安装完成"
}

# 安装Node.js
install_nodejs() {
    if command_exists node && command_exists npm; then
        local node_version=$(node --version)
        log_info "Node.js已安装: $node_version"
        return 0
    fi
    
    log_info "安装Node.js..."
    
    # 安装NodeSource仓库
    if [ "$DISTRO" = "ubuntu" ] || [ "$DISTRO" = "debian" ]; then
        curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
        $PKG_INSTALL nodejs
    elif [ "$DISTRO" = "centos" ] || [ "$DISTRO" = "rhel" ] || [ "$DISTRO" = "fedora" ]; then
        curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
        $PKG_INSTALL nodejs
    else
        # 使用二进制安装
        local node_version="18.17.0"
        local node_arch="linux-x64"
        local node_url="https://nodejs.org/dist/v$node_version/node-v$node_version-$node_arch.tar.xz"
        
        cd /tmp
        wget "$node_url"
        tar -xf "node-v$node_version-$node_arch.tar.xz"
        mv "node-v$node_version-$node_arch" /opt/nodejs
        
        # 创建符号链接
        ln -sf /opt/nodejs/bin/node /usr/local/bin/node
        ln -sf /opt/nodejs/bin/npm /usr/local/bin/npm
        ln -sf /opt/nodejs/bin/npx /usr/local/bin/npx
    fi
    
    # 安装PM2
    npm install -g pm2
    
    # 配置PM2开机启动
    pm2 startup
    
    log_success "Node.js安装完成"
}

# 安装Nginx
install_nginx() {
    if command_exists nginx; then
        log_info "Nginx已安装"
        return 0
    fi
    
    log_info "安装Nginx..."
    
    if [ "$DISTRO" = "ubuntu" ] || [ "$DISTRO" = "debian" ]; then
        $PKG_INSTALL nginx
    elif [ "$DISTRO" = "centos" ] || [ "$DISTRO" = "rhel" ] || [ "$DISTRO" = "fedora" ]; then
        $PKG_INSTALL nginx
    fi
    
    # 启用并启动Nginx
    systemctl enable nginx
    systemctl start nginx
    
    log_success "Nginx安装完成"
}

# 安装PostgreSQL
install_postgresql() {
    if [ "$DB_TYPE" != "postgresql" ] || [ "$DB_INSTALL" != "true" ]; then
        log_info "跳过PostgreSQL安装"
        return 0
    fi
    
    if command_exists psql; then
        log_info "PostgreSQL已安装"
        return 0
    fi
    
    log_info "安装PostgreSQL..."
    
    if [ "$DISTRO" = "ubuntu" ] || [ "$DISTRO" = "debian" ]; then
        $PKG_INSTALL postgresql postgresql-contrib
    elif [ "$DISTRO" = "centos" ] || [ "$DISTRO" = "rhel" ] || [ "$DISTRO" = "fedora" ]; then
        $PKG_INSTALL postgresql-server postgresql-contrib
        postgresql-setup initdb
    fi
    
    # 启用并启动PostgreSQL
    systemctl enable postgresql
    systemctl start postgresql
    
    # 等待PostgreSQL启动
    wait_for_service "postgresql" "5432"
    
    # 创建数据库和用户
    if [ -n "$DB_PASSWORD" ]; then
        sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';"
        sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
        sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
        log_info "已创建数据库: $DB_NAME，用户: $DB_USER"
    fi
    
    log_success "PostgreSQL安装完成"
}

# 安装Redis
install_redis() {
    if [ "$REDIS_ENABLED" != "true" ] || [ "$REDIS_INSTALL" != "true" ]; then
        log_info "跳过Redis安装"
        return 0
    fi
    
    if command_exists redis-server; then
        log_info "Redis已安装"
        return 0
    fi
    
    log_info "安装Redis..."
    
    if [ "$DISTRO" = "ubuntu" ] || [ "$DISTRO" = "debian" ]; then
        $PKG_INSTALL redis-server
    elif [ "$DISTRO" = "centos" ] || [ "$DISTRO" = "rhel" ] || [ "$DISTRO" = "fedora" ]; then
        $PKG_INSTALL redis
    fi
    
    # 启用并启动Redis
    systemctl enable redis
    systemctl start redis
    
    # 等待Redis启动
    wait_for_service "redis" "6379"
    
    log_success "Redis安装完成"
}

# 安装监控工具
install_monitoring() {
    if [ "$MONITORING_ENABLED" != "true" ]; then
        log_info "跳过监控工具安装"
        return 0
    fi
    
    log_info "安装监控工具..."
    
    # 安装基础监控工具
    local monitoring_packages=()
    
    if [ "$DISTRO" = "ubuntu" ] || [ "$DISTRO" = "debian" ]; then
        monitoring_packages=("htop" "iotop" "nethogs" "iftop" "sysstat")
    elif [ "$DISTRO" = "centos" ] || [ "$DISTRO" = "rhel" ] || [ "$DISTRO" = "fedora" ]; then
        monitoring_packages=("htop" "iotop" "nethogs" "iftop" "sysstat")
    fi
    
    for package in "${monitoring_packages[@]}"; do
        $PKG_INSTALL "$package"
    done
    
    # 安装Prometheus（如果启用）
    if [ "$PROMETHEUS_ENABLED" = "true" ]; then
        install_prometheus
    fi
    
    # 安装Grafana（如果启用）
    if [ "$GRAFANA_ENABLED" = "true" ]; then
        install_grafana
    fi
    
    log_success "监控工具安装完成"
}

# 安装Prometheus
install_prometheus() {
    log_info "安装Prometheus..."
    
    local prometheus_version="2.45.0"
    local prometheus_user="prometheus"
    
    # 创建用户
    if ! id "$prometheus_user" &>/dev/null; then
        useradd -r -s /bin/false "$prometheus_user"
    fi
    
    # 下载和安装
    cd /tmp
    wget "https://github.com/prometheus/prometheus/releases/download/v$prometheus_version/prometheus-$prometheus_version.linux-amd64.tar.gz"
    tar -xf "prometheus-$prometheus_version.linux-amd64.tar.gz"
    
    # 安装文件
    cp "prometheus-$prometheus_version.linux-amd64/prometheus" /usr/local/bin/
    cp "prometheus-$prometheus_version.linux-amd64/promtool" /usr/local/bin/
    
    # 创建目录
    mkdir -p /etc/prometheus /var/lib/prometheus
    chown "$prometheus_user:$prometheus_user" /etc/prometheus /var/lib/prometheus
    
    # 复制配置文件
    if [ -f "$APP_HOME/monitoring/prometheus.yml" ]; then
        cp "$APP_HOME/monitoring/prometheus.yml" /etc/prometheus/
    fi
    
    # 创建systemd服务
    cat > /etc/systemd/system/prometheus.service << EOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=$prometheus_user
Group=$prometheus_user
Type=simple
ExecStart=/usr/local/bin/prometheus \\
    --config.file /etc/prometheus/prometheus.yml \\
    --storage.tsdb.path /var/lib/prometheus/ \\
    --web.console.templates=/etc/prometheus/consoles \\
    --web.console.libraries=/etc/prometheus/console_libraries \\
    --web.listen-address=0.0.0.0:9090 \\
    --web.enable-lifecycle

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable prometheus
    systemctl start prometheus
    
    log_success "Prometheus安装完成"
}

# 安装Grafana
install_grafana() {
    log_info "安装Grafana..."
    
    if [ "$DISTRO" = "ubuntu" ] || [ "$DISTRO" = "debian" ]; then
        wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -
        echo "deb https://packages.grafana.com/oss/deb stable main" | tee -a /etc/apt/sources.list.d/grafana.list
        apt-get update
        $PKG_INSTALL grafana
    elif [ "$DISTRO" = "centos" ] || [ "$DISTRO" = "rhel" ] || [ "$DISTRO" = "fedora" ]; then
        cat > /etc/yum.repos.d/grafana.repo << EOF
[grafana]
name=grafana
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
EOF
        $PKG_INSTALL grafana
    fi
    
    systemctl enable grafana-server
    systemctl start grafana-server
    
    log_success "Grafana安装完成"
}

# ============================================================================
# 应用部署函数
# ============================================================================

# 部署应用代码
deploy_application() {
    log_info "部署应用代码..."
    
    # 如果应用目录不存在源代码，从当前目录复制
    if [ ! -f "$APP_HOME/package.json" ]; then
        log_info "复制应用代码到 $APP_HOME"
        
        # 复制应用文件
        local current_dir=$(pwd)
        if [ -f "$current_dir/package.json" ]; then
            cp -r "$current_dir"/* "$APP_HOME/"
        else
            log_error "未找到应用源代码"
            return 1
        fi
    fi
    
    # 设置文件权限
    chown -R "$DEPLOY_USER:$DEPLOY_GROUP" "$APP_HOME"
    
    # 安装依赖
    log_info "安装应用依赖..."
    cd "$APP_HOME"
    sudo -u "$DEPLOY_USER" npm install --production
    
    log_success "应用代码部署完成"
}

# 配置应用
configure_application() {
    log_info "配置应用..."
    
    # 创建环境配置文件
    local env_file="$APP_HOME/.env"
    
    cat > "$env_file" << EOF
# 申论行测学习系统 - 环境配置
# 生成时间: $(date)

# 基础配置
APP_NAME=$APP_NAME
APP_VERSION=$APP_VERSION
NODE_ENV=$DEPLOY_ENV
PORT=$APP_PORT
DATA_PATH=$DATA_PATH
LOG_PATH=$LOG_PATH

# 域名配置
DOMAIN_NAME=$DOMAIN_NAME
SSL_ENABLED=$SSL_ENABLED

# 数据库配置
DB_TYPE=$DB_TYPE
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD

# Redis配置
REDIS_ENABLED=$REDIS_ENABLED
REDIS_HOST=$REDIS_HOST
REDIS_PORT=$REDIS_PORT
REDIS_PASSWORD=$REDIS_PASSWORD

# 安全配置
JWT_SECRET=$(openssl rand -base64 32)
SESSION_SECRET=$(openssl rand -base64 32)
ENCRYPTION_KEY=$(openssl rand -base64 32)

# 监控配置
MONITORING_ENABLED=$MONITORING_ENABLED
METRICS_ENABLED=true
HEALTH_CHECK_ENABLED=true

# 日志配置
LOG_LEVEL=info
LOG_MAX_SIZE=10M
LOG_MAX_FILES=5

# 性能配置
CLUSTER_MODE=true
CACHE_ENABLED=true
COMPRESSION_ENABLED=true

# 备份配置
BACKUP_ENABLED=$BACKUP_ENABLED
BACKUP_PATH=$BACKUP_PATH
BACKUP_RETENTION=$BACKUP_RETENTION
EOF
    
    # 设置文件权限
    chown "$DEPLOY_USER:$DEPLOY_GROUP" "$env_file"
    chmod 600 "$env_file"
    
    # 创建PM2配置
    local pm2_config="$APP_HOME/ecosystem.config.js"
    cat > "$pm2_config" << EOF
module.exports = {
  apps: [{
    name: '$APP_NAME',
    script: './app.js',
    instances: 'max',
    exec_mode: 'cluster',
    env: {
      NODE_ENV: '$DEPLOY_ENV',
      PORT: $APP_PORT
    },
    max_memory_restart: '2G',
    min_uptime: '10s',
    max_restarts: 10,
    log_file: '$LOG_PATH/app.log',
    error_file: '$LOG_PATH/error.log',
    out_file: '$LOG_PATH/out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    watch: false,
    ignore_watch: ['node_modules', 'logs', 'data'],
    kill_timeout: 5000,
    listen_timeout: 3000
  }]
};
EOF
    
    chown "$DEPLOY_USER:$DEPLOY_GROUP" "$pm2_config"
    
    log_success "应用配置完成"
}

# 配置Nginx
configure_nginx() {
    log_info "配置Nginx..."
    
    # 复制Nginx配置
    if [ -f "$APP_HOME/docker/nginx/nginx.conf" ]; then
        cp "$APP_HOME/docker/nginx/nginx.conf" /etc/nginx/nginx.conf
        
        # 修复用户配置 - Ubuntu/Debian使用www-data，CentOS/RHEL使用nginx
        if [ "$DISTRO" = "ubuntu" ] || [ "$DISTRO" = "debian" ]; then
            sed -i 's/user nginx;/user www-data;/g' /etc/nginx/nginx.conf
        fi
    fi
    
    if [ -f "$APP_HOME/docker/nginx/conf.d/app.conf" ]; then
        cp "$APP_HOME/docker/nginx/conf.d/app.conf" "/etc/nginx/sites-available/$APP_NAME"
        
        # 更新配置中的变量
        sed -i "s/\$APP_PORT/$APP_PORT/g" "/etc/nginx/sites-available/$APP_NAME"
        sed -i "s/\$DOMAIN_NAME/$DOMAIN_NAME/g" "/etc/nginx/sites-available/$APP_NAME"
        
        # 启用站点
        ln -sf "/etc/nginx/sites-available/$APP_NAME" "/etc/nginx/sites-enabled/$APP_NAME"
    fi
    
    # 测试配置
    if nginx -t; then
        systemctl reload nginx
        log_success "Nginx配置完成"
    else
        log_error "Nginx配置测试失败"
        return 1
    fi
}

# 配置SSL证书
configure_ssl() {
    if [ "$SSL_ENABLED" != "true" ]; then
        log_info "跳过SSL配置"
        return 0
    fi
    
    log_info "配置SSL证书..."
    
    # 安装Certbot
    if ! command_exists certbot; then
        if [ "$DISTRO" = "ubuntu" ] || [ "$DISTRO" = "debian" ]; then
            $PKG_INSTALL certbot python3-certbot-nginx
        elif [ "$DISTRO" = "centos" ] || [ "$DISTRO" = "rhel" ] || [ "$DISTRO" = "fedora" ]; then
            $PKG_INSTALL certbot python3-certbot-nginx
        fi
    fi
    
    # 获取SSL证书
    certbot --nginx -d "$DOMAIN_NAME" --email "$SSL_EMAIL" --agree-tos --non-interactive
    
    # 配置自动续期
    echo "0 12 * * * /usr/bin/certbot renew --quiet" | crontab -
    
    log_success "SSL证书配置完成"
}

# ============================================================================
# 服务管理函数
# ============================================================================

# 启动应用服务
start_application() {
    log_info "启动应用服务..."
    
    cd "$APP_HOME"
    
    # 使用PM2启动应用
    sudo -u "$DEPLOY_USER" pm2 start ecosystem.config.js
    sudo -u "$DEPLOY_USER" pm2 save
    
    # 等待应用启动
    wait_for_service "$APP_NAME" "$APP_PORT"
    
    log_success "应用服务启动完成"
}

# 配置系统服务
configure_system_services() {
    log_info "配置系统服务..."
    
    # 配置PM2开机启动
    sudo -u "$DEPLOY_USER" pm2 startup
    
    # 启用必要的系统服务
    local services=("nginx")
    
    if [ "$DB_TYPE" = "postgresql" ] && [ "$DB_INSTALL" = "true" ]; then
        services+=("postgresql")
    fi
    
    if [ "$REDIS_ENABLED" = "true" ] && [ "$REDIS_INSTALL" = "true" ]; then
        services+=("redis")
    fi
    
    for service in "${services[@]}"; do
        systemctl enable "$service"
        systemctl start "$service"
        log_info "已启用服务: $service"
    done
    
    log_success "系统服务配置完成"
}

# ============================================================================
# 安全和优化函数
# ============================================================================

# 执行安全加固
perform_security_hardening() {
    if [ "$SECURITY_HARDENING" != "true" ] || [ "$SKIP_SECURITY" = "true" ]; then
        log_info "跳过安全加固"
        return 0
    fi
    
    log_info "执行安全加固..."
    
    # 运行安全加固脚本
    if [ -f "$APP_HOME/scripts/security-hardening.sh" ]; then
        bash "$APP_HOME/scripts/security-hardening.sh" harden
    else
        log_warn "安全加固脚本不存在"
    fi
    
    log_success "安全加固完成"
}

# 执行性能优化
perform_performance_optimization() {
    if [ "$PERFORMANCE_OPTIMIZATION" != "true" ] || [ "$SKIP_OPTIMIZATION" = "true" ]; then
        log_info "跳过性能优化"
        return 0
    fi
    
    log_info "执行性能优化..."
    
    # 运行性能优化脚本
    if [ -f "$APP_HOME/scripts/performance-optimization.sh" ]; then
        bash "$APP_HOME/scripts/performance-optimization.sh" optimize
    else
        log_warn "性能优化脚本不存在"
    fi
    
    log_success "性能优化完成"
}

# 配置监控
configure_monitoring() {
    if [ "$MONITORING_ENABLED" != "true" ] || [ "$SKIP_MONITORING" = "true" ]; then
        log_info "跳过监控配置"
        return 0
    fi
    
    log_info "配置监控..."
    
    # 复制监控配置
    if [ -d "$APP_HOME/monitoring" ]; then
        cp -r "$APP_HOME/monitoring"/* /etc/
    fi
    
    # 启动监控脚本
    if [ -f "$APP_HOME/scripts/system-monitor.sh" ]; then
        bash "$APP_HOME/scripts/system-monitor.sh" start
    fi
    
    log_success "监控配置完成"
}

# 配置备份
configure_backup() {
    if [ "$BACKUP_ENABLED" != "true" ]; then
        log_info "跳过备份配置"
        return 0
    fi
    
    log_info "配置备份..."
    
    # 配置定时备份
    if [ -f "$APP_HOME/scripts/backup-restore.sh" ]; then
        # 添加到crontab
        echo "$BACKUP_SCHEDULE root bash $APP_HOME/scripts/backup-restore.sh backup" >> /etc/crontab
        log_info "已配置定时备份: $BACKUP_SCHEDULE"
    fi
    
    log_success "备份配置完成"
}

# ============================================================================
# 验证和测试函数
# ============================================================================

# 验证部署
verify_deployment() {
    log_info "验证部署..."
    
    local errors=0
    
    # 检查应用进程
    if ! pgrep -f "$APP_NAME" >/dev/null; then
        log_error "应用进程未运行"
        errors=$((errors + 1))
    else
        log_success "应用进程正常运行"
    fi
    
    # 检查端口监听
    if ! netstat -tln | grep -q ":$APP_PORT "; then
        log_error "应用端口 $APP_PORT 未监听"
        errors=$((errors + 1))
    else
        log_success "应用端口 $APP_PORT 正常监听"
    fi
    
    # 检查HTTP响应
    if command_exists curl; then
        local http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$APP_PORT/health" || echo "000")
        if [ "$http_code" = "200" ]; then
            log_success "应用健康检查正常"
        else
            log_error "应用健康检查失败 (HTTP $http_code)"
            errors=$((errors + 1))
        fi
    fi
    
    # 检查Nginx
    if ! systemctl is-active nginx >/dev/null; then
        log_error "Nginx服务未运行"
        errors=$((errors + 1))
    else
        log_success "Nginx服务正常运行"
    fi
    
    # 检查数据库（如果启用）
    if [ "$DB_TYPE" = "postgresql" ] && [ "$DB_INSTALL" = "true" ]; then
        if ! systemctl is-active postgresql >/dev/null; then
            log_error "PostgreSQL服务未运行"
            errors=$((errors + 1))
        else
            log_success "PostgreSQL服务正常运行"
        fi
    fi
    
    # 检查Redis（如果启用）
    if [ "$REDIS_ENABLED" = "true" ] && [ "$REDIS_INSTALL" = "true" ]; then
        if ! systemctl is-active redis >/dev/null; then
            log_error "Redis服务未运行"
            errors=$((errors + 1))
        else
            log_success "Redis服务正常运行"
        fi
    fi
    
    if [ $errors -eq 0 ]; then
        log_success "部署验证通过"
        return 0
    else
        log_error "部署验证失败，发现 $errors 个错误"
        return 1
    fi
}

# 性能测试
perform_performance_test() {
    log_info "执行性能测试..."
    
    if command_exists ab; then
        log_info "使用Apache Bench进行压力测试..."
        ab -n 1000 -c 10 "http://localhost:$APP_PORT/" > /tmp/performance-test.log
        log_info "性能测试结果已保存到 /tmp/performance-test.log"
    elif command_exists wrk; then
        log_info "使用wrk进行压力测试..."
        wrk -t4 -c100 -d30s "http://localhost:$APP_PORT/" > /tmp/performance-test.log
        log_info "性能测试结果已保存到 /tmp/performance-test.log"
    else
        log_warn "未安装性能测试工具，跳过性能测试"
    fi
    
    log_success "性能测试完成"
}

# ============================================================================
# 主部署函数
# ============================================================================

# 执行完整部署
perform_full_deployment() {
    log_deploy "开始执行完整部署..."
    
    local start_time=$(date +%s)
    
    # 环境检查
    check_root
    detect_os
    get_package_manager
    
    # 创建日志目录
    mkdir -p "$LOG_PATH"
    
    # 创建用户和目录
    create_app_user
    create_directories
    
    # 安装依赖（如果未跳过）
    if [ "$SKIP_DEPENDENCIES" != "true" ]; then
        update_system
        install_base_dependencies
        install_nodejs
        install_nginx
        install_postgresql
        install_redis
        install_monitoring
    fi
    
    # 部署应用
    deploy_application
    configure_application
    configure_nginx
    configure_ssl
    
    # 启动服务
    configure_system_services
    start_application
    
    # 安全和优化
    perform_security_hardening
    perform_performance_optimization
    configure_monitoring
    configure_backup
    
    # 验证部署
    verify_deployment
    
    # 计算总耗时
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_deploy "部署完成，耗时 ${duration} 秒"
    
    # 显示部署信息
    show_deployment_info
}

# 显示部署信息
show_deployment_info() {
    cat << EOF

${GREEN}========================================${NC}
${GREEN}  申论行测学习系统部署完成${NC}
${GREEN}========================================${NC}

${BLUE}应用信息:${NC}
  应用名称: $APP_NAME
  应用版本: $APP_VERSION
  部署环境: $DEPLOY_ENV
  应用端口: $APP_PORT
  应用目录: $APP_HOME
  数据目录: $DATA_PATH
  日志目录: $LOG_PATH

${BLUE}访问信息:${NC}
  本地访问: http://localhost:$APP_PORT
  域名访问: http://$DOMAIN_NAME
EOF

    if [ "$SSL_ENABLED" = "true" ]; then
        echo "  HTTPS访问: https://$DOMAIN_NAME"
    fi

cat << EOF

${BLUE}服务状态:${NC}
  应用服务: $(systemctl is-active "$APP_NAME" 2>/dev/null || echo "使用PM2管理")
  Nginx服务: $(systemctl is-active nginx)
EOF

    if [ "$DB_TYPE" = "postgresql" ] && [ "$DB_INSTALL" = "true" ]; then
        echo "  PostgreSQL: $(systemctl is-active postgresql)"
    fi
    
    if [ "$REDIS_ENABLED" = "true" ] && [ "$REDIS_INSTALL" = "true" ]; then
        echo "  Redis服务: $(systemctl is-active redis)"
    fi

cat << EOF

${BLUE}管理命令:${NC}
  查看应用状态: pm2 status
  查看应用日志: pm2 logs $APP_NAME
  重启应用: pm2 restart $APP_NAME
  停止应用: pm2 stop $APP_NAME
  重载Nginx: systemctl reload nginx
  查看系统状态: bash $APP_HOME/scripts/system-monitor.sh status

${BLUE}重要文件:${NC}
  环境配置: $APP_HOME/.env
  PM2配置: $APP_HOME/ecosystem.config.js
  Nginx配置: /etc/nginx/sites-available/$APP_NAME
  部署日志: $LOG_PATH/deploy.log

${YELLOW}注意事项:${NC}
  1. 请妥善保管数据库密码和密钥信息
  2. 定期检查系统安全更新
  3. 监控系统资源使用情况
  4. 定期备份重要数据

${GREEN}部署成功！${NC}

EOF
}

# 显示帮助信息
show_help() {
    cat << EOF
申论行测学习系统 - 自动化部署脚本

用法:
  $0 <命令> [选项]

命令:
  deploy                       执行完整部署
  install-deps                 仅安装依赖
  deploy-app                   仅部署应用
  configure                    仅配置服务
  start                        启动服务
  stop                         停止服务
  restart                      重启服务
  status                       查看状态
  verify                       验证部署
  test                         性能测试
  help                         显示帮助信息

环境变量:
  DEPLOY_ENV                   部署环境 (production/staging)
  DOMAIN_NAME                  域名
  SSL_ENABLED                  启用SSL
  DB_TYPE                      数据库类型
  REDIS_ENABLED                启用Redis
  SKIP_DEPENDENCIES            跳过依赖安装
  SKIP_SECURITY                跳过安全加固
  SKIP_OPTIMIZATION            跳过性能优化

示例:
  $0 deploy                    执行完整部署
  DOMAIN_NAME=example.com $0 deploy  指定域名部署
  SSL_ENABLED=true $0 deploy   启用SSL部署
EOF
}

# 主函数
main() {
    # 确保日志目录存在
    mkdir -p "$LOG_PATH"
    
    case "${1:-deploy}" in
        "deploy")
            perform_full_deployment
            ;;
        "install-deps")
            check_root
            detect_os
            get_package_manager
            update_system
            install_base_dependencies
            install_nodejs
            install_nginx
            install_postgresql
            install_redis
            install_monitoring
            ;;
        "deploy-app")
            deploy_application
            configure_application
            ;;
        "configure")
            configure_nginx
            configure_ssl
            configure_system_services
            ;;
        "start")
            start_application
            ;;
        "stop")
            sudo -u "$DEPLOY_USER" pm2 stop all
            ;;
        "restart")
            sudo -u "$DEPLOY_USER" pm2 restart all
            systemctl reload nginx
            ;;
        "status")
            sudo -u "$DEPLOY_USER" pm2 status
            systemctl status nginx
            ;;
        "verify")
            verify_deployment
            ;;
        "test")
            perform_performance_test
            ;;
        "help")
            show_help
            ;;
        *)
            log_error "未知命令: $1"
            show_help
            exit 1
            ;;
    esac
}

# ============================================================================
# 脚本入口
# ============================================================================

# 如果脚本被直接执行
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi