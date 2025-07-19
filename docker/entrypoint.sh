#!/bin/bash
# 申论行测学习系统 - Docker入口脚本
# 版本: v2.0.0
# 描述: 容器启动时的初始化和应用启动脚本

set -e

# ============================================================================
# 环境变量和配置
# ============================================================================

# 应用配置
APP_NAME="${APP_NAME:-shenlun-xingce-system}"
APP_VERSION="${APP_VERSION:-2.0.0}"
NODE_ENV="${NODE_ENV:-production}"
PORT="${PORT:-3000}"
DATA_PATH="${DATA_PATH:-/app/data}"

# 日志配置
LOG_LEVEL="${LOG_LEVEL:-info}"
LOG_PATH="${LOG_PATH:-/app/logs}"

# 数据库配置
DB_TYPE="${DB_TYPE:-file}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-shenlun_system}"
DB_USER="${DB_USER:-app_user}"
DB_PASSWORD="${DB_PASSWORD:-}"

# Redis配置
REDIS_ENABLED="${REDIS_ENABLED:-false}"
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"

# 安全配置
JWT_SECRET="${JWT_SECRET:-}"
SESSION_SECRET="${SESSION_SECRET:-}"
ENCRYPTION_KEY="${ENCRYPTION_KEY:-}"

# 功能开关
CLOUD_SYNC_ENABLED="${CLOUD_SYNC_ENABLED:-true}"
BACKUP_ENABLED="${BACKUP_ENABLED:-true}"
MONITORING_ENABLED="${MONITORING_ENABLED:-false}"

# ============================================================================
# 工具函数
# ============================================================================

# 日志函数
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$1] $2"
}

log_info() {
    log "INFO" "$1"
}

log_warn() {
    log "WARN" "$1"
}

log_error() {
    log "ERROR" "$1"
}

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 等待服务可用
wait_for_service() {
    local host="$1"
    local port="$2"
    local service="$3"
    local timeout="${4:-30}"
    
    log_info "等待 $service 服务可用 ($host:$port)..."
    
    local count=0
    while ! nc -z "$host" "$port" >/dev/null 2>&1; do
        if [ $count -ge $timeout ]; then
            log_error "等待 $service 服务超时"
            return 1
        fi
        sleep 1
        count=$((count + 1))
    done
    
    log_info "$service 服务已可用"
    return 0
}

# 检查环境变量
check_required_env() {
    local required_vars=("JWT_SECRET" "SESSION_SECRET")
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            log_error "必需的环境变量 $var 未设置"
            exit 1
        fi
    done
}

# ============================================================================
# 初始化函数
# ============================================================================

# 创建必要的目录
create_directories() {
    log_info "创建必要的目录..."
    
    local dirs=(
        "$DATA_PATH"
        "$DATA_PATH/questions"
        "$DATA_PATH/history"
        "$DATA_PATH/tags"
        "$DATA_PATH/annotations"
        "$DATA_PATH/users"
        "$DATA_PATH/backups"
        "$LOG_PATH"
        "/app/tmp"
        "/app/uploads"
    )
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            log_info "创建目录: $dir"
        fi
    done
    
    # 设置权限
    chown -R app:app "$DATA_PATH" "$LOG_PATH" "/app/tmp" "/app/uploads" 2>/dev/null || true
    chmod -R 755 "$DATA_PATH" "$LOG_PATH" "/app/tmp" "/app/uploads" 2>/dev/null || true
}

# 生成默认配置
generate_default_config() {
    log_info "生成默认配置..."
    
    # 生成默认的JWT密钥（如果未设置）
    if [ -z "$JWT_SECRET" ]; then
        JWT_SECRET=$(openssl rand -hex 32)
        export JWT_SECRET
        log_warn "自动生成JWT密钥，建议在生产环境中手动设置"
    fi
    
    # 生成默认的会话密钥（如果未设置）
    if [ -z "$SESSION_SECRET" ]; then
        SESSION_SECRET=$(openssl rand -hex 32)
        export SESSION_SECRET
        log_warn "自动生成会话密钥，建议在生产环境中手动设置"
    fi
    
    # 生成默认的加密密钥（如果未设置）
    if [ -z "$ENCRYPTION_KEY" ]; then
        ENCRYPTION_KEY=$(openssl rand -hex 32)
        export ENCRYPTION_KEY
        log_warn "自动生成加密密钥，建议在生产环境中手动设置"
    fi
}

# 初始化数据库
init_database() {
    if [ "$DB_TYPE" = "postgresql" ] && [ -n "$DB_HOST" ]; then
        log_info "初始化PostgreSQL数据库..."
        
        # 等待数据库可用
        if wait_for_service "$DB_HOST" "$DB_PORT" "PostgreSQL" 60; then
            # 运行数据库迁移（如果有的话）
            if [ -f "/app/scripts/init-db.sql" ]; then
                log_info "运行数据库初始化脚本..."
                PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "/app/scripts/init-db.sql" || true
            fi
        else
            log_error "无法连接到PostgreSQL数据库"
            exit 1
        fi
    fi
}

# 初始化Redis
init_redis() {
    if [ "$REDIS_ENABLED" = "true" ] && [ -n "$REDIS_HOST" ]; then
        log_info "检查Redis连接..."
        
        if wait_for_service "$REDIS_HOST" "$REDIS_PORT" "Redis" 30; then
            log_info "Redis连接正常"
        else
            log_warn "无法连接到Redis，将禁用缓存功能"
            export REDIS_ENABLED="false"
        fi
    fi
}

# 创建管理员用户
create_admin_user() {
    if [ -n "$ADMIN_USERNAME" ] && [ -n "$ADMIN_PASSWORD" ]; then
        log_info "创建管理员用户..."
        
        # 创建管理员用户的脚本
        cat > /tmp/create-admin.js << EOF
const fs = require('fs');
const path = require('path');
const bcrypt = require('bcryptjs');
const crypto = require('crypto');

const dataPath = process.env.DATA_PATH || '/app/data';
const usersFile = path.join(dataPath, 'users', 'users.json');

// 确保用户目录存在
if (!fs.existsSync(path.dirname(usersFile))) {
    fs.mkdirSync(path.dirname(usersFile), { recursive: true });
}

// 读取现有用户
let users = [];
if (fs.existsSync(usersFile)) {
    try {
        users = JSON.parse(fs.readFileSync(usersFile, 'utf8'));
    } catch (e) {
        console.log('无法读取用户文件，创建新文件');
    }
}

// 检查管理员是否已存在
const adminExists = users.some(user => user.username === process.env.ADMIN_USERNAME);

if (!adminExists) {
    // 创建管理员用户
    const adminUser = {
        id: crypto.randomUUID(),
        username: process.env.ADMIN_USERNAME,
        email: process.env.ADMIN_EMAIL || 'admin@example.com',
        password: bcrypt.hashSync(process.env.ADMIN_PASSWORD, 10),
        role: 'admin',
        isActive: true,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
        profile: {
            name: '系统管理员',
            avatar: '',
            bio: '系统默认管理员账户'
        },
        settings: {
            theme: 'light',
            language: 'zh-CN',
            notifications: true
        }
    };
    
    users.push(adminUser);
    
    // 保存用户文件
    fs.writeFileSync(usersFile, JSON.stringify(users, null, 2));
    console.log('管理员用户创建成功');
} else {
    console.log('管理员用户已存在');
}
EOF
        
        # 运行创建管理员用户的脚本
        node /tmp/create-admin.js
        rm -f /tmp/create-admin.js
    fi
}

# 设置文件权限
setup_permissions() {
    log_info "设置文件权限..."
    
    # 确保应用用户拥有必要的权限
    if id "app" >/dev/null 2>&1; then
        chown -R app:app /app 2>/dev/null || true
        chown -R app:app "$DATA_PATH" 2>/dev/null || true
        chown -R app:app "$LOG_PATH" 2>/dev/null || true
    fi
    
    # 设置适当的权限
    chmod -R 755 /app 2>/dev/null || true
    chmod -R 755 "$DATA_PATH" 2>/dev/null || true
    chmod -R 755 "$LOG_PATH" 2>/dev/null || true
    
    # 保护敏感文件
    if [ -f "/app/.env" ]; then
        chmod 600 /app/.env 2>/dev/null || true
    fi
}

# 健康检查
health_check() {
    log_info "执行健康检查..."
    
    # 检查Node.js
    if ! command_exists node; then
        log_error "Node.js未安装"
        exit 1
    fi
    
    # 检查应用文件
    if [ ! -f "/app/server.js" ]; then
        log_error "应用主文件不存在"
        exit 1
    fi
    
    # 检查package.json
    if [ ! -f "/app/package.json" ]; then
        log_error "package.json文件不存在"
        exit 1
    fi
    
    # 检查node_modules
    if [ ! -d "/app/node_modules" ]; then
        log_error "依赖包未安装"
        exit 1
    fi
    
    log_info "健康检查通过"
}

# 备份数据
backup_data() {
    if [ "$BACKUP_ENABLED" = "true" ]; then
        log_info "执行数据备份..."
        
        local backup_dir="$DATA_PATH/backups"
        local backup_file="$backup_dir/backup-$(date +%Y%m%d-%H%M%S).tar.gz"
        
        # 创建备份目录
        mkdir -p "$backup_dir"
        
        # 创建备份
        tar -czf "$backup_file" -C "$DATA_PATH" \
            --exclude="backups" \
            --exclude="*.log" \
            --exclude="tmp" \
            . 2>/dev/null || true
        
        if [ -f "$backup_file" ]; then
            log_info "数据备份完成: $backup_file"
            
            # 清理旧备份（保留最近7天）
            find "$backup_dir" -name "backup-*.tar.gz" -mtime +7 -delete 2>/dev/null || true
        else
            log_warn "数据备份失败"
        fi
    fi
}

# ============================================================================
# 信号处理
# ============================================================================

# 优雅关闭处理
graceful_shutdown() {
    log_info "接收到关闭信号，正在优雅关闭..."
    
    # 如果应用正在运行，发送SIGTERM信号
    if [ -n "$APP_PID" ]; then
        log_info "正在关闭应用进程 (PID: $APP_PID)..."
        kill -TERM "$APP_PID" 2>/dev/null || true
        
        # 等待进程结束
        local count=0
        while kill -0 "$APP_PID" 2>/dev/null && [ $count -lt 30 ]; do
            sleep 1
            count=$((count + 1))
        done
        
        # 如果进程仍在运行，强制杀死
        if kill -0 "$APP_PID" 2>/dev/null; then
            log_warn "强制关闭应用进程"
            kill -KILL "$APP_PID" 2>/dev/null || true
        fi
    fi
    
    log_info "应用已关闭"
    exit 0
}

# 设置信号处理
trap graceful_shutdown SIGTERM SIGINT

# ============================================================================
# 主函数
# ============================================================================

main() {
    log_info "启动 $APP_NAME v$APP_VERSION"
    log_info "环境: $NODE_ENV"
    log_info "端口: $PORT"
    log_info "数据路径: $DATA_PATH"
    
    # 检查必需的环境变量
    # check_required_env
    
    # 执行初始化
    create_directories
    generate_default_config
    setup_permissions
    
    # 初始化外部服务
    init_database
    init_redis
    
    # 创建管理员用户
    create_admin_user
    
    # 执行健康检查
    health_check
    
    # 执行备份
    backup_data
    
    log_info "初始化完成，启动应用..."
    
    # 切换到应用用户（如果存在）
    if id "app" >/dev/null 2>&1 && [ "$(id -u)" = "0" ]; then
        log_info "切换到应用用户运行"
        exec su-exec app "$0" "$@"
    fi
    
    # 启动应用
    cd /app
    
    if [ "$NODE_ENV" = "development" ]; then
        log_info "以开发模式启动应用"
        exec node server.js &
    else
        log_info "以生产模式启动应用"
        exec node server.js &
    fi
    
    APP_PID=$!
    log_info "应用已启动 (PID: $APP_PID)"
    
    # 等待应用进程
    wait $APP_PID
}

# ============================================================================
# 脚本入口
# ============================================================================

# 如果脚本被直接执行
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi