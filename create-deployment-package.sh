#!/bin/bash
# 申论行测学习系统 - 云服务部署打包脚本
# 版本: v2.0.0
# 描述: 创建完整的云服务部署档案

set -e

# ============================================================================
# 配置变量
# ============================================================================

# 项目信息
PROJECT_NAME="shenlun-xingce-system"
PROJECT_VERSION="2.0.0"
BUILD_DATE=$(date +"%Y%m%d-%H%M%S")

# 路径配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
BUILD_DIR="$PROJECT_ROOT/build"
DIST_DIR="$PROJECT_ROOT/dist"
PACKAGE_NAME="${PROJECT_NAME}-deployment-${PROJECT_VERSION}-${BUILD_DATE}"
PACKAGE_DIR="$DIST_DIR/$PACKAGE_NAME"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# 工具函数
# ============================================================================

# 日志函数
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
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

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 检查必需的工具
check_requirements() {
    log_info "检查必需的工具..."
    
    local required_tools=("tar" "gzip" "zip")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if ! command_exists "$tool"; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "缺少必需的工具: ${missing_tools[*]}"
        log_error "请安装缺少的工具后重试"
        exit 1
    fi
    
    log_success "工具检查通过"
}

# 清理构建目录
clean_build_dir() {
    log_info "清理构建目录..."
    
    if [ -d "$BUILD_DIR" ]; then
        rm -rf "$BUILD_DIR"
    fi
    
    if [ -d "$DIST_DIR" ]; then
        rm -rf "$DIST_DIR"
    fi
    
    mkdir -p "$BUILD_DIR"
    mkdir -p "$DIST_DIR"
    mkdir -p "$PACKAGE_DIR"
    
    log_success "构建目录已清理"
}

# ============================================================================
# 文件复制函数
# ============================================================================

# 复制应用核心文件
copy_app_files() {
    log_info "复制应用核心文件..."
    
    local app_files=(
        "server.js"
        "package.json"
        "package-lock.json"
        "index.html"
        "style.css"
        "script.js"
        "auth.js"
        "auth.css"
    )
    
    for file in "${app_files[@]}"; do
        if [ -f "$PROJECT_ROOT/$file" ]; then
            cp "$PROJECT_ROOT/$file" "$PACKAGE_DIR/"
            log_info "已复制: $file"
        else
            log_warn "文件不存在: $file"
        fi
    done
    
    log_success "应用核心文件复制完成"
}

# 复制API文件
copy_api_files() {
    log_info "复制API文件..."
    
    if [ -d "$PROJECT_ROOT/api" ]; then
        cp -r "$PROJECT_ROOT/api" "$PACKAGE_DIR/"
        log_success "API文件复制完成"
    else
        log_warn "API目录不存在"
    fi
}

# 复制Docker文件
copy_docker_files() {
    log_info "复制Docker配置文件..."
    
    if [ -d "$PROJECT_ROOT/docker" ]; then
        cp -r "$PROJECT_ROOT/docker" "$PACKAGE_DIR/"
        
        # 设置脚本执行权限
        chmod +x "$PACKAGE_DIR/docker/"*.sh 2>/dev/null || true
        
        log_success "Docker文件复制完成"
    else
        log_warn "Docker目录不存在"
    fi
}

# 复制部署脚本
copy_deployment_scripts() {
    log_info "复制部署脚本..."
    
    local scripts=(
        "deploy-complete.sh"
        "docker-compose.production.yml"
    )
    
    for script in "${scripts[@]}"; do
        if [ -f "$PROJECT_ROOT/$script" ]; then
            cp "$PROJECT_ROOT/$script" "$PACKAGE_DIR/"
            chmod +x "$PACKAGE_DIR/$script" 2>/dev/null || true
            log_info "已复制: $script"
        else
            log_warn "脚本不存在: $script"
        fi
    done
    
    log_success "部署脚本复制完成"
}

# 复制脚本文件
copy_scripts() {
    log_info "复制脚本文件..."
    
    local scripts_dir="$PACKAGE_DIR/scripts"
    mkdir -p "$scripts_dir"
    
    # 复制脚本文件
    if [ -d "$PROJECT_ROOT/scripts" ]; then
        cp -r "$PROJECT_ROOT/scripts/"* "$scripts_dir/"
    fi
    
    # 确保脚本可执行
    find "$scripts_dir" -name "*.sh" -exec chmod +x {} \;
    
    # 验证关键脚本存在
    local required_scripts=(
        "auto-deploy.sh"
        "backup-restore.sh"
        "system-monitor.sh"
        "security-hardening.sh"
        "performance-optimization.sh"
    )
    
    for script in "${required_scripts[@]}"; do
        if [ ! -f "$scripts_dir/$script" ]; then
            log_warn "缺少关键脚本: $script"
        else
            log_info "已包含脚本: $script"
        fi
    done
    
    log_success "脚本文件复制完成"
}

# 复制文档文件
copy_documentation() {
    log_info "复制文档文件..."
    
    local docs=(
        "README.md"
        "TUTORIAL.md"
        "ADMIN_GUIDE.md"
        "API_DOCS.md"
        "CLOUD_DEPLOYMENT.md"
        "ARCHITECTURE.md"
        "CLOUD_DEPLOYMENT_GUIDE.md"
    )
    
    mkdir -p "$PACKAGE_DIR/docs"
    
    for doc in "${docs[@]}"; do
        if [ -f "$PROJECT_ROOT/$doc" ]; then
            cp "$PROJECT_ROOT/$doc" "$PACKAGE_DIR/docs/"
            log_info "已复制: $doc"
        else
            log_warn "文档不存在: $doc"
        fi
    done
    
    # 复制云部署指南到根目录（重要文档）
    if [ -f "$PROJECT_ROOT/CLOUD_DEPLOYMENT_GUIDE.md" ]; then
        cp "$PROJECT_ROOT/CLOUD_DEPLOYMENT_GUIDE.md" "$PACKAGE_DIR/"
        log_info "已复制云部署指南到根目录"
    fi
    
    log_success "文档文件复制完成"
}

# 创建示例配置文件
create_example_configs() {
    log_info "创建示例配置文件..."
    
    # 创建环境变量示例文件
    cat > "$PACKAGE_DIR/.env.example" << 'EOF'
# 申论行测学习系统 - 环境变量配置示例
# 复制此文件为 .env 并根据实际情况修改配置

# ============================================================================
# 基础配置
# ============================================================================

# 应用名称和版本
APP_NAME=shenlun-xingce-system
APP_VERSION=2.0.0

# 运行环境 (development, production, test)
NODE_ENV=production

# 服务器配置
PORT=3000
HOST=0.0.0.0

# 域名配置
DOMAIN=your-domain.com
BASE_URL=https://your-domain.com

# ============================================================================
# 安全配置
# ============================================================================

# JWT密钥 (请生成一个强密钥)
JWT_SECRET=your-super-secret-jwt-key-here
JWT_EXPIRES_IN=7d

# 会话密钥 (请生成一个强密钥)
SESSION_SECRET=your-super-secret-session-key-here

# 加密密钥 (请生成一个强密钥)
ENCRYPTION_KEY=your-super-secret-encryption-key-here

# ============================================================================
# 管理员配置
# ============================================================================

# 默认管理员账户
ADMIN_USERNAME=admin
ADMIN_PASSWORD=your-secure-admin-password
ADMIN_EMAIL=admin@your-domain.com

# ============================================================================
# 数据库配置
# ============================================================================

# 数据库类型 (file, postgresql)
DB_TYPE=file

# PostgreSQL配置 (当DB_TYPE=postgresql时)
# DB_HOST=localhost
# DB_PORT=5432
# DB_NAME=shenlun_system
# DB_USER=app_user
# DB_PASSWORD=your-db-password

# ============================================================================
# Redis配置
# ============================================================================

# 是否启用Redis
REDIS_ENABLED=false

# Redis连接配置
# REDIS_HOST=localhost
# REDIS_PORT=6379
# REDIS_PASSWORD=your-redis-password

# ============================================================================
# 存储配置
# ============================================================================

# 数据存储路径
DATA_PATH=/app/data

# 日志路径
LOG_PATH=/app/logs

# 上传文件大小限制 (MB)
MAX_FILE_SIZE=10

# ============================================================================
# 功能开关
# ============================================================================

# 云同步功能
CLOUD_SYNC_ENABLED=true

# 备份功能
BACKUP_ENABLED=true

# 监控功能
MONITORING_ENABLED=false

# ============================================================================
# 日志配置
# ============================================================================

# 日志级别 (error, warn, info, debug)
LOG_LEVEL=info

# 日志格式 (json, simple)
LOG_FORMAT=json

# ============================================================================
# 性能配置
# ============================================================================

# 集群模式
CLUSTER_ENABLED=false
CLUSTER_WORKERS=auto

# 缓存配置
CACHE_ENABLED=true
CACHE_TTL=3600

# 限流配置
RATE_LIMIT_ENABLED=true
RATE_LIMIT_WINDOW=15
RATE_LIMIT_MAX=100
EOF
    
    # 创建Nginx配置示例
    mkdir -p "$PACKAGE_DIR/config/nginx"
    cat > "$PACKAGE_DIR/config/nginx/nginx.conf.example" << 'EOF'
# Nginx配置示例
# 复制到 /etc/nginx/sites-available/ 并根据实际情况修改

server {
    listen 80;
    server_name your-domain.com www.your-domain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name your-domain.com www.your-domain.com;
    
    # SSL配置
    ssl_certificate /path/to/your/certificate.crt;
    ssl_certificate_key /path/to/your/private.key;
    
    # 反向代理到应用
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF
    
    log_success "示例配置文件创建完成"
}

# ============================================================================
# 创建部署指南
# ============================================================================

create_deployment_guide() {
    log_info "创建部署指南..."
    
    cat > "$PACKAGE_DIR/DEPLOYMENT_GUIDE.md" << 'EOF'
# 申论行测学习系统 - 快速部署指南

## 快速部署

### 1. 自动化部署（推荐）

```bash
# 解压部署包
tar -xzf shenlun-xingce-system-deployment-v2.0.0.tar.gz
cd shenlun-xingce-system-deployment

# 执行自动部署
sudo chmod +x scripts/auto-deploy.sh
sudo ./scripts/auto-deploy.sh deploy
```

### 云服务部署

详细的云服务部署指南请参考 `CLOUD_DEPLOYMENT_GUIDE.md` 文件，包含：

- 阿里云ECS部署
- 腾讯云CVM部署
- AWS EC2部署
- 华为云ECS部署
- Docker容器化部署
- Kubernetes集群部署
- 负载均衡配置
- CDN加速配置
- 监控告警配置

### 1.1 传统部署方式

```bash
# 赋予执行权限
chmod +x deploy-complete.sh

# 运行自动化部署脚本
sudo ./deploy-complete.sh
```

### 2. Docker部署

```bash
# 复制环境变量文件
cp .env.example .env

# 编辑环境变量
vim .env

# 启动服务
docker-compose -f docker-compose.production.yml up -d
```

### 3. 手动部署

#### 3.1 安装依赖

```bash
# 安装Node.js (推荐v18+)
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# 安装PM2
sudo npm install -g pm2

# 安装Nginx
sudo apt-get install -y nginx
```

#### 3.2 部署应用

```bash
# 安装应用依赖
npm install --production

# 复制配置文件
cp .env.example .env
vim .env

# 启动应用
pm2 start server.js --name "shenlun-system"
```

#### 3.3 配置Nginx

```bash
# 复制Nginx配置
sudo cp config/nginx/nginx.conf.example /etc/nginx/sites-available/shenlun-system
sudo ln -s /etc/nginx/sites-available/shenlun-system /etc/nginx/sites-enabled/

# 测试配置
sudo nginx -t

# 重启Nginx
sudo systemctl restart nginx
```

## 配置说明

### 环境变量

请参考 `.env.example` 文件，主要配置项：

- `DOMAIN`: 你的域名
- `JWT_SECRET`: JWT密钥（必须设置）
- `ADMIN_USERNAME`: 管理员用户名
- `ADMIN_PASSWORD`: 管理员密码

### SSL证书

推荐使用Let's Encrypt免费证书：

```bash
# 安装Certbot
sudo apt-get install -y certbot python3-certbot-nginx

# 获取证书
sudo certbot --nginx -d your-domain.com
```

## 维护操作

### 查看日志

```bash
# PM2日志
pm2 logs

# 应用日志
tail -f /app/logs/app.log

# Nginx日志
sudo tail -f /var/log/nginx/access.log
```

### 备份数据

```bash
# 手动备份
tar -czf backup-$(date +%Y%m%d).tar.gz /app/data

# 自动备份（添加到crontab）
0 2 * * * /path/to/backup-script.sh
```

### 更新应用

```bash
# 停止应用
pm2 stop shenlun-system

# 更新代码
git pull origin main
npm install --production

# 重启应用
pm2 restart shenlun-system
```

## 故障排除

### 常见问题

1. **应用无法启动**
   - 检查环境变量配置
   - 查看PM2日志
   - 确认端口未被占用

2. **无法访问网站**
   - 检查Nginx配置
   - 确认防火墙设置
   - 查看SSL证书状态

3. **数据丢失**
   - 检查数据目录权限
   - 恢复备份数据
   - 查看应用日志

### 获取帮助

- 查看详细文档：`docs/`目录
- 技术支持：support@example.com
- 问题反馈：https://github.com/your-repo/issues
EOF
    
    log_success "部署指南创建完成"
}

# 创建版本信息文件
create_version_info() {
    log_info "创建版本信息文件..."
    
    cat > "$PACKAGE_DIR/VERSION.txt" << EOF
申论行测学习系统 - 云服务部署包

项目名称: $PROJECT_NAME
版本号: $PROJECT_VERSION
构建时间: $BUILD_DATE
构建主机: $(hostname)
构建用户: $(whoami)

包含组件:
- 应用核心文件
- API接口
- Docker配置
- 部署脚本
- 文档资料
- 配置示例

部署说明:
请参考 DEPLOYMENT_GUIDE.md 文件

技术支持:
Email: support@example.com
Website: https://your-domain.com
EOF
    
    log_success "版本信息文件创建完成"
}

# ============================================================================
# 打包函数
# ============================================================================

# 创建压缩包
create_archives() {
    log_info "创建压缩包..."
    
    cd "$DIST_DIR"
    
    # 创建tar.gz压缩包
    log_info "创建tar.gz压缩包..."
    tar -czf "${PACKAGE_NAME}.tar.gz" "$PACKAGE_NAME"
    
    # 创建zip压缩包
    log_info "创建zip压缩包..."
    zip -r "${PACKAGE_NAME}.zip" "$PACKAGE_NAME" >/dev/null
    
    # 计算文件大小和校验和
    local tar_size=$(du -h "${PACKAGE_NAME}.tar.gz" | cut -f1)
    local zip_size=$(du -h "${PACKAGE_NAME}.zip" | cut -f1)
    local tar_md5=$(md5sum "${PACKAGE_NAME}.tar.gz" | cut -d' ' -f1)
    local zip_md5=$(md5sum "${PACKAGE_NAME}.zip" | cut -d' ' -f1)
    
    # 创建校验和文件
    cat > "${PACKAGE_NAME}.checksums" << EOF
# 申论行测学习系统 - 部署包校验和
# 生成时间: $(date)

# tar.gz包
${PACKAGE_NAME}.tar.gz
大小: $tar_size
MD5: $tar_md5

# zip包
${PACKAGE_NAME}.zip
大小: $zip_size
MD5: $zip_md5
EOF
    
    log_success "压缩包创建完成"
    log_info "tar.gz包大小: $tar_size"
    log_info "zip包大小: $zip_size"
}

# 生成部署报告
generate_deployment_report() {
    log_info "生成部署报告..."
    
    local report_file="$DIST_DIR/${PACKAGE_NAME}-report.txt"
    
    cat > "$report_file" << EOF
申论行测学习系统 - 部署包生成报告

生成时间: $(date)
项目版本: $PROJECT_VERSION
包名称: $PACKAGE_NAME

包含文件:
EOF
    
    # 添加文件列表
    echo "" >> "$report_file"
    echo "文件列表:" >> "$report_file"
    find "$PACKAGE_DIR" -type f | sed "s|$PACKAGE_DIR/||" | sort >> "$report_file"
    
    # 添加目录结构
    echo "" >> "$report_file"
    echo "目录结构:" >> "$report_file"
    tree "$PACKAGE_DIR" 2>/dev/null >> "$report_file" || find "$PACKAGE_DIR" -type d | sed "s|$PACKAGE_DIR|.|" | sort >> "$report_file"
    
    log_success "部署报告生成完成: $report_file"
}

# ============================================================================
# 主函数
# ============================================================================

main() {
    log_info "开始创建云服务部署档案..."
    log_info "项目: $PROJECT_NAME v$PROJECT_VERSION"
    log_info "构建时间: $BUILD_DATE"
    
    # 检查环境
    check_requirements
    
    # 清理构建目录
    clean_build_dir
    
    # 复制文件
    copy_app_files
    copy_api_files
    copy_docker_files
    copy_deployment_scripts
    copy_scripts
    copy_documentation
    
    # 创建配置文件
    create_example_configs
    create_deployment_guide
    create_version_info
    
    # 创建压缩包
    create_archives
    
    # 生成报告
    generate_deployment_report
    
    # 显示结果
    echo
    log_success "云服务部署档案创建完成！"
    echo
    log_info "生成的文件:"
    ls -lh "$DIST_DIR"
    echo
    log_info "部署包位置: $DIST_DIR"
    log_info "请将压缩包上传到服务器并按照 DEPLOYMENT_GUIDE.md 进行部署"
    echo
}

# ============================================================================
# 脚本入口
# ============================================================================

# 如果脚本被直接执行
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi