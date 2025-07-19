#!/bin/bash

# 申论行测学习系统 - 完整部署脚本
# 版本: v2.0.0
# 作者: 系统管理员
# 描述: 一键部署申论行测学习系统到云服务器

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置变量
APP_NAME="shenlun-xingce-system"
APP_DIR="/opt/${APP_NAME}"
NGINX_CONF_DIR="/etc/nginx/sites-available"
NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"
SERVICE_USER="appuser"
NODE_VERSION="18"
PM2_APP_NAME="${APP_NAME}"
DOMAIN="your-domain.com"
EMAIL="admin@your-domain.com"
HTTP_PORT="80"
HTTPS_PORT="443"
APP_PORT="3000"
LOG_DIR="/var/log/${APP_NAME}"
BACKUP_DIR="/backup/${APP_NAME}"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

# 显示横幅
show_banner() {
    echo -e "${CYAN}"
    echo "═══════════════════════════════════════════════════════════════"
    echo "          申论行测学习系统 - 云服务器部署脚本 v2.0.0"
    echo "═══════════════════════════════════════════════════════════════"
    echo -e "${NC}"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        log_info "请使用: sudo $0"
        exit 1
    fi
}

# 检查操作系统
check_os() {
    log_step "检查操作系统..."
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        log_error "无法确定操作系统版本"
        exit 1
    fi
    
    log_info "操作系统: $OS $VER"
    
    # 检查是否为支持的系统
    case $OS in
        "Ubuntu")
            if [[ $(echo "$VER >= 18.04" | bc -l) -eq 0 ]]; then
                log_error "需要Ubuntu 18.04或更高版本"
                exit 1
            fi
            PACKAGE_MANAGER="apt"
            ;;
        "CentOS Linux")
            if [[ $(echo "$VER >= 7" | bc -l) -eq 0 ]]; then
                log_error "需要CentOS 7或更高版本"
                exit 1
            fi
            PACKAGE_MANAGER="yum"
            ;;
        *)
            log_warning "未测试的操作系统: $OS"
            log_info "继续安装可能会遇到问题"
            PACKAGE_MANAGER="apt"  # 默认使用apt
            ;;
    esac
    
    log_success "操作系统检查通过"
}

# 更新系统包
update_system() {
    log_step "更新系统包..."
    
    case $PACKAGE_MANAGER in
        "apt")
            apt update && apt upgrade -y
            apt install -y curl wget git unzip software-properties-common
            ;;
        "yum")
            yum update -y
            yum install -y curl wget git unzip epel-release
            ;;
    esac
    
    log_success "系统包更新完成"
}

# 安装Node.js
install_nodejs() {
    log_step "安装Node.js ${NODE_VERSION}..."
    
    # 检查是否已安装
    if command -v node &> /dev/null; then
        CURRENT_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
        if [[ $CURRENT_VERSION -ge $NODE_VERSION ]]; then
            log_info "Node.js已安装，版本: $(node --version)"
            return
        fi
    fi
    
    # 安装NodeSource仓库
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -
    
    case $PACKAGE_MANAGER in
        "apt")
            apt install -y nodejs
            ;;
        "yum")
            yum install -y nodejs npm
            ;;
    esac
    
    # 验证安装
    if command -v node &> /dev/null && command -v npm &> /dev/null; then
        log_success "Node.js安装成功: $(node --version)"
        log_success "npm版本: $(npm --version)"
    else
        log_error "Node.js安装失败"
        exit 1
    fi
}

# 安装PM2
install_pm2() {
    log_step "安装PM2进程管理器..."
    
    if command -v pm2 &> /dev/null; then
        log_info "PM2已安装，版本: $(pm2 --version)"
        return
    fi
    
    npm install -g pm2
    
    # 设置PM2开机启动
    pm2 startup
    
    log_success "PM2安装完成"
}

# 安装Nginx
install_nginx() {
    log_step "安装Nginx..."
    
    if command -v nginx &> /dev/null; then
        log_info "Nginx已安装，版本: $(nginx -v 2>&1 | cut -d' ' -f3)"
        return
    fi
    
    case $PACKAGE_MANAGER in
        "apt")
            apt install -y nginx
            ;;
        "yum")
            yum install -y nginx
            ;;
    esac
    
    # 启动并设置开机启动
    systemctl start nginx
    systemctl enable nginx
    
    log_success "Nginx安装完成"
}

# 创建应用用户
create_app_user() {
    log_step "创建应用用户..."
    
    if id "$SERVICE_USER" &>/dev/null; then
        log_info "用户 $SERVICE_USER 已存在"
        return
    fi
    
    # 创建系统用户
    useradd --system --shell /bin/bash --home-dir $APP_DIR --create-home $SERVICE_USER
    
    # 设置用户权限
    usermod -aG www-data $SERVICE_USER
    
    log_success "应用用户 $SERVICE_USER 创建完成"
}

# 创建目录结构
create_directories() {
    log_step "创建目录结构..."
    
    # 创建应用目录
    mkdir -p $APP_DIR
    mkdir -p $LOG_DIR
    mkdir -p $BACKUP_DIR
    mkdir -p $APP_DIR/data
    mkdir -p $APP_DIR/data/users_data
    mkdir -p $APP_DIR/data/backups
    mkdir -p $APP_DIR/logs
    mkdir -p $APP_DIR/temp
    
    # 设置目录权限
    chown -R $SERVICE_USER:$SERVICE_USER $APP_DIR
    chown -R $SERVICE_USER:$SERVICE_USER $LOG_DIR
    chown -R $SERVICE_USER:$SERVICE_USER $BACKUP_DIR
    
    chmod 755 $APP_DIR
    chmod 755 $LOG_DIR
    chmod 755 $BACKUP_DIR
    chmod 750 $APP_DIR/data
    
    log_success "目录结构创建完成"
}

# 部署应用代码
deploy_application() {
    log_step "部署应用代码..."
    
    # 如果是从Git仓库部署
    if [[ -n "$GIT_REPO" ]]; then
        log_info "从Git仓库克隆代码: $GIT_REPO"
        
        # 备份现有代码
        if [[ -d "$APP_DIR/app" ]]; then
            mv "$APP_DIR/app" "$APP_DIR/app.backup.$(date +%Y%m%d_%H%M%S)"
        fi
        
        # 克隆代码
        git clone $GIT_REPO $APP_DIR/app
        
    else
        # 从当前目录复制代码
        log_info "从当前目录复制应用代码"
        
        # 确保源代码存在
        if [[ ! -f "package.json" ]]; then
            log_error "在当前目录未找到package.json文件"
            log_info "请确保在应用根目录运行此脚本"
            exit 1
        fi
        
        # 复制应用文件
        cp -r . $APP_DIR/app/
        
        # 排除不需要的文件
        rm -rf $APP_DIR/app/.git
        rm -rf $APP_DIR/app/node_modules
        rm -f $APP_DIR/app/deploy*.sh
    fi
    
    # 设置文件权限
    chown -R $SERVICE_USER:$SERVICE_USER $APP_DIR/app
    
    log_success "应用代码部署完成"
}

# 安装应用依赖
install_dependencies() {
    log_step "安装应用依赖..."
    
    cd $APP_DIR/app
    
    # 使用应用用户身份安装依赖
    sudo -u $SERVICE_USER npm install --production
    
    log_success "应用依赖安装完成"
}

# 配置环境变量
setup_environment() {
    log_step "配置环境变量..."
    
    # 创建环境变量文件
    cat > $APP_DIR/app/.env << EOF
# 应用配置
NODE_ENV=production
PORT=$APP_PORT
APP_NAME=$APP_NAME

# JWT配置
JWT_SECRET=$(openssl rand -base64 32)
JWT_EXPIRES_IN=24h

# 安全配置
SESSION_SECRET=$(openssl rand -base64 32)
ENCRYPTION_KEY=$(openssl rand -base64 32)

# 文件路径
DATA_DIR=$APP_DIR/data
LOG_DIR=$LOG_DIR
BACKUP_DIR=$BACKUP_DIR

# 服务器配置
DOMAIN=$DOMAIN
HTTP_PORT=$HTTP_PORT
HTTPS_PORT=$HTTPS_PORT

# 管理员配置
ADMIN_EMAIL=$EMAIL
ADMIN_USERNAME=admin
ADMIN_PASSWORD=$(openssl rand -base64 12)

# 日志配置
LOG_LEVEL=info
LOG_MAX_SIZE=10m
LOG_MAX_FILES=5

# 备份配置
BACKUP_INTERVAL=daily
BACKUP_RETENTION=30

# 性能配置
MAX_UPLOAD_SIZE=10mb
RATE_LIMIT_WINDOW=15
RATE_LIMIT_MAX=100
EOF

    # 设置环境变量文件权限
    chown $SERVICE_USER:$SERVICE_USER $APP_DIR/app/.env
    chmod 600 $APP_DIR/app/.env
    
    log_success "环境变量配置完成"
    log_warning "管理员密码已生成，请查看 $APP_DIR/app/.env 文件"
}

# 配置Nginx
setup_nginx() {
    log_step "配置Nginx..."
    
    # 创建Nginx配置文件
    cat > $NGINX_CONF_DIR/$APP_NAME << EOF
server {
    listen $HTTP_PORT;
    server_name $DOMAIN www.$DOMAIN;
    
    # 重定向到HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen $HTTPS_PORT ssl http2;
    server_name $DOMAIN www.$DOMAIN;
    
    # SSL配置
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # 安全头
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # 日志配置
    access_log $LOG_DIR/nginx_access.log;
    error_log $LOG_DIR/nginx_error.log;
    
    # 根目录
    root $APP_DIR/app;
    index index.html;
    
    # 静态文件缓存
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)\$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    # API代理
    location /api/ {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        
        # 超时设置
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # 主页面
    location / {
        try_files \$uri \$uri/ /index.html;
    }
    
    # 文件上传大小限制
    client_max_body_size 10M;
    
    # Gzip压缩
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
}
EOF

    # 启用站点
    ln -sf $NGINX_CONF_DIR/$APP_NAME $NGINX_ENABLED_DIR/
    
    # 删除默认站点
    rm -f $NGINX_ENABLED_DIR/default
    
    # 测试Nginx配置
    if nginx -t; then
        log_success "Nginx配置验证通过"
    else
        log_error "Nginx配置验证失败"
        exit 1
    fi
}

# 安装SSL证书
install_ssl() {
    log_step "安装SSL证书..."
    
    # 安装Certbot
    case $PACKAGE_MANAGER in
        "apt")
            apt install -y certbot python3-certbot-nginx
            ;;
        "yum")
            yum install -y certbot python3-certbot-nginx
            ;;
    esac
    
    # 停止Nginx以释放80端口
    systemctl stop nginx
    
    # 获取SSL证书
    if certbot certonly --standalone -d $DOMAIN -d www.$DOMAIN --email $EMAIL --agree-tos --non-interactive; then
        log_success "SSL证书获取成功"
        
        # 设置自动续期
        (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -
        
    else
        log_warning "SSL证书获取失败，将使用HTTP模式"
        
        # 修改Nginx配置为HTTP模式
        cat > $NGINX_CONF_DIR/$APP_NAME << EOF
server {
    listen $HTTP_PORT;
    server_name $DOMAIN www.$DOMAIN;
    
    # 日志配置
    access_log $LOG_DIR/nginx_access.log;
    error_log $LOG_DIR/nginx_error.log;
    
    # 根目录
    root $APP_DIR/app;
    index index.html;
    
    # 静态文件缓存
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)\$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    # API代理
    location /api/ {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
    
    # 主页面
    location / {
        try_files \$uri \$uri/ /index.html;
    }
    
    # 文件上传大小限制
    client_max_body_size 10M;
    
    # Gzip压缩
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
}
EOF
    fi
    
    # 启动Nginx
    systemctl start nginx
}

# 配置PM2
setup_pm2() {
    log_step "配置PM2应用..."
    
    # 创建PM2配置文件
    cat > $APP_DIR/app/ecosystem.config.js << EOF
module.exports = {
  apps: [{
    name: '$PM2_APP_NAME',
    script: 'server.js',
    cwd: '$APP_DIR/app',
    instances: 'max',
    exec_mode: 'cluster',
    env: {
      NODE_ENV: 'production',
      PORT: $APP_PORT
    },
    log_file: '$LOG_DIR/app.log',
    out_file: '$LOG_DIR/app_out.log',
    error_file: '$LOG_DIR/app_error.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    merge_logs: true,
    max_memory_restart: '500M',
    node_args: '--max-old-space-size=512',
    watch: false,
    ignore_watch: ['node_modules', 'logs', 'data'],
    restart_delay: 4000,
    max_restarts: 10,
    min_uptime: '10s'
  }]
};
EOF

    # 设置文件权限
    chown $SERVICE_USER:$SERVICE_USER $APP_DIR/app/ecosystem.config.js
    
    log_success "PM2配置完成"
}

# 启动应用
start_application() {
    log_step "启动应用..."
    
    cd $APP_DIR/app
    
    # 使用应用用户启动PM2
    sudo -u $SERVICE_USER pm2 start ecosystem.config.js
    
    # 保存PM2配置
    sudo -u $SERVICE_USER pm2 save
    
    # 设置PM2开机启动
    sudo -u $SERVICE_USER pm2 startup
    
    log_success "应用启动完成"
}

# 配置防火墙
setup_firewall() {
    log_step "配置防火墙..."
    
    # 检查防火墙类型
    if command -v ufw &> /dev/null; then
        # Ubuntu UFW
        ufw --force enable
        ufw allow ssh
        ufw allow $HTTP_PORT
        ufw allow $HTTPS_PORT
        log_success "UFW防火墙配置完成"
        
    elif command -v firewall-cmd &> /dev/null; then
        # CentOS firewalld
        systemctl start firewalld
        systemctl enable firewalld
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --reload
        log_success "firewalld防火墙配置完成"
        
    else
        log_warning "未检测到防火墙，请手动配置"
    fi
}

# 创建管理脚本
create_management_scripts() {
    log_step "创建管理脚本..."
    
    # 创建启动脚本
    cat > $APP_DIR/start.sh << 'EOF'
#!/bin/bash
cd /opt/shenlun-xingce-system/app
sudo -u appuser pm2 start ecosystem.config.js
echo "应用已启动"
EOF

    # 创建停止脚本
    cat > $APP_DIR/stop.sh << 'EOF'
#!/bin/bash
cd /opt/shenlun-xingce-system/app
sudo -u appuser pm2 stop shenlun-xingce-system
echo "应用已停止"
EOF

    # 创建重启脚本
    cat > $APP_DIR/restart.sh << 'EOF'
#!/bin/bash
cd /opt/shenlun-xingce-system/app
sudo -u appuser pm2 restart shenlun-xingce-system
echo "应用已重启"
EOF

    # 创建状态检查脚本
    cat > $APP_DIR/status.sh << 'EOF'
#!/bin/bash
echo "=== 应用状态 ==="
sudo -u appuser pm2 status
echo ""
echo "=== Nginx状态 ==="
systemctl status nginx --no-pager -l
echo ""
echo "=== 系统资源 ==="
free -h
df -h
EOF

    # 创建日志查看脚本
    cat > $APP_DIR/logs.sh << 'EOF'
#!/bin/bash
echo "=== 应用日志 ==="
sudo -u appuser pm2 logs --lines 50
EOF

    # 创建备份脚本
    cat > $APP_DIR/backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/backup/shenlun-xingce-system"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/backup_$DATE.tar.gz"

mkdir -p $BACKUP_DIR

echo "开始备份..."
tar -czf $BACKUP_FILE -C /opt/shenlun-xingce-system/data .

echo "备份完成: $BACKUP_FILE"

# 清理30天前的备份
find $BACKUP_DIR -name "backup_*.tar.gz" -mtime +30 -delete
EOF

    # 设置脚本权限
    chmod +x $APP_DIR/*.sh
    
    log_success "管理脚本创建完成"
}

# 运行健康检查
health_check() {
    log_step "运行健康检查..."
    
    # 等待应用启动
    sleep 10
    
    # 检查应用端口
    if netstat -tlnp | grep :$APP_PORT > /dev/null; then
        log_success "应用端口 $APP_PORT 正常监听"
    else
        log_error "应用端口 $APP_PORT 未监听"
        return 1
    fi
    
    # 检查HTTP响应
    if curl -f http://localhost:$APP_PORT/api/health > /dev/null 2>&1; then
        log_success "应用健康检查通过"
    else
        log_warning "应用健康检查失败，可能需要时间启动"
    fi
    
    # 检查Nginx
    if systemctl is-active nginx > /dev/null; then
        log_success "Nginx服务正常运行"
    else
        log_error "Nginx服务未运行"
        return 1
    fi
    
    # 检查PM2
    if sudo -u $SERVICE_USER pm2 list | grep -q $PM2_APP_NAME; then
        log_success "PM2应用正常运行"
    else
        log_error "PM2应用未运行"
        return 1
    fi
    
    return 0
}

# 显示部署信息
show_deployment_info() {
    echo -e "${GREEN}"
    echo "═══════════════════════════════════════════════════════════════"
    echo "                    部署完成！"
    echo "═══════════════════════════════════════════════════════════════"
    echo -e "${NC}"
    
    echo -e "${CYAN}应用信息:${NC}"
    echo "  应用名称: $APP_NAME"
    echo "  应用目录: $APP_DIR"
    echo "  应用端口: $APP_PORT"
    echo "  运行用户: $SERVICE_USER"
    echo ""
    
    echo -e "${CYAN}访问地址:${NC}"
    if [[ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]; then
        echo "  HTTPS: https://$DOMAIN"
        echo "  HTTP: http://$DOMAIN (自动重定向到HTTPS)"
    else
        echo "  HTTP: http://$DOMAIN"
    fi
    echo "  API: http://$DOMAIN/api/health"
    echo ""
    
    echo -e "${CYAN}管理命令:${NC}"
    echo "  启动应用: $APP_DIR/start.sh"
    echo "  停止应用: $APP_DIR/stop.sh"
    echo "  重启应用: $APP_DIR/restart.sh"
    echo "  查看状态: $APP_DIR/status.sh"
    echo "  查看日志: $APP_DIR/logs.sh"
    echo "  数据备份: $APP_DIR/backup.sh"
    echo ""
    
    echo -e "${CYAN}重要文件:${NC}"
    echo "  环境配置: $APP_DIR/app/.env"
    echo "  Nginx配置: $NGINX_CONF_DIR/$APP_NAME"
    echo "  PM2配置: $APP_DIR/app/ecosystem.config.js"
    echo "  应用日志: $LOG_DIR/"
    echo "  数据目录: $APP_DIR/data/"
    echo ""
    
    echo -e "${YELLOW}注意事项:${NC}"
    echo "  1. 请修改 $APP_DIR/app/.env 中的管理员密码"
    echo "  2. 定期运行备份脚本保护数据"
    echo "  3. 监控系统资源使用情况"
    echo "  4. 及时更新系统和应用依赖"
    echo ""
    
    echo -e "${GREEN}部署成功完成！${NC}"
}

# 主函数
main() {
    show_banner
    
    # 检查参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --domain)
                DOMAIN="$2"
                shift 2
                ;;
            --email)
                EMAIL="$2"
                shift 2
                ;;
            --git-repo)
                GIT_REPO="$2"
                shift 2
                ;;
            --app-port)
                APP_PORT="$2"
                shift 2
                ;;
            --help)
                echo "用法: $0 [选项]"
                echo "选项:"
                echo "  --domain DOMAIN     设置域名 (默认: your-domain.com)"
                echo "  --email EMAIL       设置邮箱 (默认: admin@your-domain.com)"
                echo "  --git-repo URL      从Git仓库部署"
                echo "  --app-port PORT     设置应用端口 (默认: 3000)"
                echo "  --help              显示帮助信息"
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                exit 1
                ;;
        esac
    done
    
    # 执行部署步骤
    check_root
    check_os
    update_system
    install_nodejs
    install_pm2
    install_nginx
    create_app_user
    create_directories
    deploy_application
    install_dependencies
    setup_environment
    setup_nginx
    install_ssl
    setup_pm2
    start_application
    setup_firewall
    create_management_scripts
    
    # 健康检查
    if health_check; then
        show_deployment_info
    else
        log_error "部署完成但健康检查失败，请检查日志"
        exit 1
    fi
}

# 错误处理
trap 'log_error "部署过程中发生错误，请检查日志"' ERR

# 运行主函数
main "$@"