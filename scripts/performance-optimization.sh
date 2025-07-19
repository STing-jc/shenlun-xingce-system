#!/bin/bash
# 申论行测学习系统 - 性能优化脚本
# 版本: v2.0.0
# 描述: 系统和应用性能优化脚本

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

# Node.js配置
NODE_ENV="${NODE_ENV:-production}"
NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=2048}"
UV_THREADPOOL_SIZE="${UV_THREADPOOL_SIZE:-16}"

# 系统优化配置
OPTIMIZE_KERNEL="${OPTIMIZE_KERNEL:-true}"
OPTIMIZE_NETWORK="${OPTIMIZE_NETWORK:-true}"
OPTIMIZE_FILESYSTEM="${OPTIMIZE_FILESYSTEM:-true}"
OPTIMIZE_MEMORY="${OPTIMIZE_MEMORY:-true}"
OPTIMIZE_CPU="${OPTIMIZE_CPU:-true}"

# 内存配置
SWAPPINESS="${SWAPPINESS:-10}"
VFS_CACHE_PRESSURE="${VFS_CACHE_PRESSURE:-50}"
DIRTY_RATIO="${DIRTY_RATIO:-15}"
DIRTY_BACKGROUND_RATIO="${DIRTY_BACKGROUND_RATIO:-5}"

# 网络配置
TCP_CONGESTION_CONTROL="${TCP_CONGESTION_CONTROL:-bbr}"
NET_CORE_RMEM_MAX="${NET_CORE_RMEM_MAX:-134217728}"
NET_CORE_WMEM_MAX="${NET_CORE_WMEM_MAX:-134217728}"
TCP_RMEM="${TCP_RMEM:-4096 87380 134217728}"
TCP_WMEM="${TCP_WMEM:-4096 65536 134217728}"

# 文件系统配置
FS_FILE_MAX="${FS_FILE_MAX:-2097152}"
FS_INOTIFY_MAX_USER_WATCHES="${FS_INOTIFY_MAX_USER_WATCHES:-524288}"

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
REDIS_MAXMEMORY="${REDIS_MAXMEMORY:-256mb}"
REDIS_MAXMEMORY_POLICY="${REDIS_MAXMEMORY_POLICY:-allkeys-lru}"

# Nginx配置
NGINX_WORKER_PROCESSES="${NGINX_WORKER_PROCESSES:-auto}"
NGINX_WORKER_CONNECTIONS="${NGINX_WORKER_CONNECTIONS:-1024}"
NGINX_KEEPALIVE_TIMEOUT="${NGINX_KEEPALIVE_TIMEOUT:-65}"
NGINX_CLIENT_MAX_BODY_SIZE="${NGINX_CLIENT_MAX_BODY_SIZE:-50M}"

# 缓存配置
ENABLE_GZIP="${ENABLE_GZIP:-true}"
ENABLE_BROTLI="${ENABLE_BROTLI:-false}"
STATIC_CACHE_TTL="${STATIC_CACHE_TTL:-86400}"
API_CACHE_TTL="${API_CACHE_TTL:-300}"

# 监控配置
PERFORMANCE_MONITORING="${PERFORMANCE_MONITORING:-true}"
METRICS_COLLECTION="${METRICS_COLLECTION:-true}"
PROFILING_ENABLED="${PROFILING_ENABLED:-false}"

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
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_PATH/performance.log"
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

log_perf() {
    log "${PURPLE}[PERF]${NC} $1"
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
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si)
        VER=$(lsb_release -sr)
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        OS=$DISTRIB_ID
        VER=$DISTRIB_RELEASE
    elif [ -f /etc/debian_version ]; then
        OS=Debian
        VER=$(cat /etc/debian_version)
    elif [ -f /etc/redhat-release ]; then
        OS=RedHat
    else
        OS=$(uname -s)
        VER=$(uname -r)
    fi
    
    log_info "检测到操作系统: $OS $VER"
}

# 获取系统信息
get_system_info() {
    local cpu_cores=$(nproc)
    local total_memory=$(free -m | grep Mem: | awk '{print $2}')
    local available_memory=$(free -m | grep Mem: | awk '{print $7}')
    local disk_space=$(df -h / | tail -1 | awk '{print $4}')
    
    log_info "系统信息:"
    log_info "  CPU核心数: $cpu_cores"
    log_info "  总内存: ${total_memory}MB"
    log_info "  可用内存: ${available_memory}MB"
    log_info "  可用磁盘空间: $disk_space"
}

# 备份配置文件
backup_config() {
    local config_file="$1"
    local backup_dir="/root/performance-backup-$(date +%Y%m%d)"
    
    if [ -f "$config_file" ]; then
        mkdir -p "$backup_dir"
        cp "$config_file" "$backup_dir/$(basename "$config_file").backup"
        log_info "已备份配置文件: $config_file"
    fi
}

# ============================================================================
# 系统优化函数
# ============================================================================

# 优化内核参数
optimize_kernel_parameters() {
    if [ "$OPTIMIZE_KERNEL" != "true" ]; then
        log_info "跳过内核参数优化"
        return 0
    fi
    
    log_info "优化内核参数..."
    
    backup_config /etc/sysctl.conf
    
    cat >> /etc/sysctl.conf << EOF

# 性能优化参数 - 由性能优化脚本添加
# 生成时间: $(date)

# 内存管理优化
vm.swappiness = $SWAPPINESS
vm.vfs_cache_pressure = $VFS_CACHE_PRESSURE
vm.dirty_ratio = $DIRTY_RATIO
vm.dirty_background_ratio = $DIRTY_BACKGROUND_RATIO
vm.dirty_expire_centisecs = 3000
vm.dirty_writeback_centisecs = 500
vm.overcommit_memory = 1
vm.overcommit_ratio = 50
vm.min_free_kbytes = 65536

# 网络性能优化
net.core.rmem_default = 262144
net.core.rmem_max = $NET_CORE_RMEM_MAX
net.core.wmem_default = 262144
net.core.wmem_max = $NET_CORE_WMEM_MAX
net.core.netdev_max_backlog = 5000
net.core.netdev_budget = 600
net.core.somaxconn = 65535

# TCP优化
net.ipv4.tcp_rmem = $TCP_RMEM
net.ipv4.tcp_wmem = $TCP_WMEM
net.ipv4.tcp_congestion_control = $TCP_CONGESTION_CONTROL
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_adv_win_scale = 1
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_frto = 2
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 10
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 2

# 文件系统优化
fs.file-max = $FS_FILE_MAX
fs.inotify.max_user_watches = $FS_INOTIFY_MAX_USER_WATCHES
fs.inotify.max_user_instances = 8192
fs.aio-max-nr = 1048576

# 进程和线程优化
kernel.pid_max = 4194304
kernel.threads-max = 4194304
kernel.sched_migration_cost_ns = 5000000
kernel.sched_autogroup_enabled = 0

# I/O调度优化
vm.zone_reclaim_mode = 0
vm.page-cluster = 3
EOF
    
    # 应用内核参数
    sysctl -p
    
    log_success "内核参数优化完成"
}

# 优化文件系统
optimize_filesystem() {
    if [ "$OPTIMIZE_FILESYSTEM" != "true" ]; then
        log_info "跳过文件系统优化"
        return 0
    fi
    
    log_info "优化文件系统..."
    
    # 优化文件描述符限制
    backup_config /etc/security/limits.conf
    
    cat >> /etc/security/limits.conf << EOF

# 性能优化 - 文件描述符限制
# 生成时间: $(date)

* soft nofile 65535
* hard nofile 65535
* soft nproc 65535
* hard nproc 65535
root soft nofile 65535
root hard nofile 65535
root soft nproc 65535
root hard nproc 65535
EOF
    
    # 优化systemd限制
    if command_exists systemctl; then
        mkdir -p /etc/systemd/system.conf.d
        cat > /etc/systemd/system.conf.d/limits.conf << EOF
[Manager]
DefaultLimitNOFILE=65535
DefaultLimitNPROC=65535
EOF
        
        mkdir -p /etc/systemd/user.conf.d
        cat > /etc/systemd/user.conf.d/limits.conf << EOF
[Manager]
DefaultLimitNOFILE=65535
DefaultLimitNPROC=65535
EOF
    fi
    
    # 优化tmpfs
    if ! grep -q "tmpfs /tmp" /etc/fstab; then
        echo "tmpfs /tmp tmpfs defaults,noatime,mode=1777,size=2G 0 0" >> /etc/fstab
        log_info "已配置tmpfs for /tmp"
    fi
    
    # 优化磁盘调度器
    local disk_devices=$(lsblk -d -o NAME | grep -v NAME | grep -E '^(sd|nvme|vd)')
    for device in $disk_devices; do
        if [ -f "/sys/block/$device/queue/scheduler" ]; then
            # 对于SSD使用noop或none，对于HDD使用deadline
            if [ -f "/sys/block/$device/queue/rotational" ] && [ "$(cat /sys/block/$device/queue/rotational)" = "0" ]; then
                # SSD
                echo "none" > "/sys/block/$device/queue/scheduler" 2>/dev/null || echo "noop" > "/sys/block/$device/queue/scheduler" 2>/dev/null || true
                log_info "已为SSD $device 设置调度器为 none/noop"
            else
                # HDD
                echo "deadline" > "/sys/block/$device/queue/scheduler" 2>/dev/null || true
                log_info "已为HDD $device 设置调度器为 deadline"
            fi
        fi
    done
    
    log_success "文件系统优化完成"
}

# 优化CPU性能
optimize_cpu_performance() {
    if [ "$OPTIMIZE_CPU" != "true" ]; then
        log_info "跳过CPU性能优化"
        return 0
    fi
    
    log_info "优化CPU性能..."
    
    # 设置CPU调频策略
    if command_exists cpupower; then
        cpupower frequency-set -g performance 2>/dev/null || true
        log_info "已设置CPU调频策略为performance"
    elif [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            if [ -f "$cpu" ]; then
                echo "performance" > "$cpu" 2>/dev/null || true
            fi
        done
        log_info "已设置CPU调频策略为performance"
    fi
    
    # 禁用CPU节能功能
    if [ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]; then
        echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo
        log_info "已启用Intel Turbo Boost"
    fi
    
    # 设置CPU亲和性（如果是多核系统）
    local cpu_cores=$(nproc)
    if [ $cpu_cores -gt 1 ]; then
        # 为网络中断设置CPU亲和性
        if command_exists irqbalance; then
            systemctl enable irqbalance
            systemctl start irqbalance
            log_info "已启用IRQ平衡"
        fi
    fi
    
    log_success "CPU性能优化完成"
}

# 优化内存管理
optimize_memory_management() {
    if [ "$OPTIMIZE_MEMORY" != "true" ]; then
        log_info "跳过内存管理优化"
        return 0
    fi
    
    log_info "优化内存管理..."
    
    # 配置透明大页
    if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
        echo "madvise" > /sys/kernel/mm/transparent_hugepage/enabled
        echo "defer+madvise" > /sys/kernel/mm/transparent_hugepage/defrag
        log_info "已配置透明大页为madvise模式"
    fi
    
    # 配置NUMA平衡
    if [ -f /proc/sys/kernel/numa_balancing ]; then
        echo 1 > /proc/sys/kernel/numa_balancing
        log_info "已启用NUMA平衡"
    fi
    
    # 配置内存压缩
    if [ -f /proc/sys/vm/compact_memory ]; then
        echo 1 > /proc/sys/vm/compact_memory
        log_info "已启用内存压缩"
    fi
    
    # 优化swap配置
    local swap_devices=$(swapon --show=NAME --noheadings)
    if [ -n "$swap_devices" ]; then
        log_info "检测到swap设备，已通过内核参数优化"
    else
        log_warn "未检测到swap设备，建议配置适当的swap空间"
    fi
    
    log_success "内存管理优化完成"
}

# ============================================================================
# 应用优化函数
# ============================================================================

# 优化Node.js应用
optimize_nodejs_app() {
    log_info "优化Node.js应用..."
    
    # 创建Node.js优化配置
    local node_config_file="$APP_HOME/.noderc"
    cat > "$node_config_file" << EOF
# Node.js性能优化配置
# 生成时间: $(date)

# 内存配置
export NODE_OPTIONS="--max-old-space-size=2048 --max-semi-space-size=128"

# 线程池配置
export UV_THREADPOOL_SIZE=16

# V8优化
export NODE_OPTIONS="\$NODE_OPTIONS --optimize-for-size"
export NODE_OPTIONS="\$NODE_OPTIONS --max-inlined-source-size=600"
export NODE_OPTIONS="\$NODE_OPTIONS --max-inlined-bytecode-size=600"

# 垃圾回收优化
export NODE_OPTIONS="\$NODE_OPTIONS --gc-interval=100"
export NODE_OPTIONS="\$NODE_OPTIONS --expose-gc"

# 性能监控
if [ "\$NODE_ENV" = "production" ]; then
    export NODE_OPTIONS="\$NODE_OPTIONS --trace-warnings"
fi
EOF
    
    # 创建PM2生态系统配置
    if command_exists pm2; then
        local pm2_config="$APP_HOME/ecosystem.config.js"
        cat > "$pm2_config" << EOF
module.exports = {
  apps: [{
    name: '$APP_NAME',
    script: './app.js',
    instances: 'max',
    exec_mode: 'cluster',
    env: {
      NODE_ENV: 'production',
      PORT: $APP_PORT,
      UV_THREADPOOL_SIZE: 16
    },
    env_production: {
      NODE_ENV: 'production',
      NODE_OPTIONS: '--max-old-space-size=2048 --optimize-for-size'
    },
    // 性能优化配置
    max_memory_restart: '2G',
    min_uptime: '10s',
    max_restarts: 10,
    
    // 日志配置
    log_file: '$LOG_PATH/app.log',
    error_file: '$LOG_PATH/error.log',
    out_file: '$LOG_PATH/out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    
    // 监控配置
    monitoring: false,
    
    // 集群配置
    instance_var: 'INSTANCE_ID',
    
    // 自动重启配置
    watch: false,
    ignore_watch: ['node_modules', 'logs', 'data'],
    
    // 进程配置
    kill_timeout: 5000,
    listen_timeout: 3000,
    
    // 资源限制
    max_memory_restart: '2G',
    
    // 健康检查
    health_check_grace_period: 3000
  }]
};
EOF
        
        log_info "已创建PM2生态系统配置"
    fi
    
    # 优化package.json脚本
    if [ -f "$APP_HOME/package.json" ]; then
        # 这里可以添加package.json优化逻辑
        log_info "检测到package.json，建议检查依赖项优化"
    fi
    
    log_success "Node.js应用优化完成"
}

# 优化Nginx配置
optimize_nginx() {
    if ! command_exists nginx; then
        log_info "跳过Nginx优化（未安装）"
        return 0
    fi
    
    log_info "优化Nginx配置..."
    
    local nginx_conf="/etc/nginx/nginx.conf"
    backup_config "$nginx_conf"
    
    cat > "$nginx_conf" << EOF
# Nginx性能优化配置
# 生成时间: $(date)

user www-data;
worker_processes $NGINX_WORKER_PROCESSES;
worker_rlimit_nofile 65535;
pid /run/nginx.pid;

# 错误日志
error_log /var/log/nginx/error.log warn;

events {
    worker_connections $NGINX_WORKER_CONNECTIONS;
    use epoll;
    multi_accept on;
    accept_mutex off;
}

http {
    # 基础配置
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # 字符集
    charset utf-8;
    
    # 服务器标识
    server_tokens off;
    
    # 日志格式
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for" '
                    'rt=\$request_time uct="\$upstream_connect_time" '
                    'uht="\$upstream_header_time" urt="\$upstream_response_time"';
    
    access_log /var/log/nginx/access.log main;
    
    # 性能优化
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    
    # 连接配置
    keepalive_timeout $NGINX_KEEPALIVE_TIMEOUT;
    keepalive_requests 1000;
    
    # 客户端配置
    client_max_body_size $NGINX_CLIENT_MAX_BODY_SIZE;
    client_body_buffer_size 128k;
    client_header_buffer_size 4k;
    large_client_header_buffers 4 16k;
    client_body_timeout 60;
    client_header_timeout 60;
    send_timeout 60;
    
    # 代理配置
    proxy_connect_timeout 60;
    proxy_send_timeout 60;
    proxy_read_timeout 60;
    proxy_buffer_size 4k;
    proxy_buffers 4 32k;
    proxy_busy_buffers_size 64k;
    proxy_temp_file_write_size 64k;
    
    # 压缩配置
EOF
    
    if [ "$ENABLE_GZIP" = "true" ]; then
        cat >> "$nginx_conf" << EOF
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;
EOF
    fi
    
    if [ "$ENABLE_BROTLI" = "true" ]; then
        cat >> "$nginx_conf" << EOF
    
    # Brotli压缩
    brotli on;
    brotli_comp_level 6;
    brotli_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;
EOF
    fi
    
    cat >> "$nginx_conf" << EOF
    
    # 缓存配置
    open_file_cache max=10000 inactive=20s;
    open_file_cache_valid 30s;
    open_file_cache_min_uses 2;
    open_file_cache_errors on;
    
    # 限制配置
    limit_req_zone \$binary_remote_addr zone=api:10m rate=10r/s;
    limit_conn_zone \$binary_remote_addr zone=conn:10m;
    
    # 包含站点配置
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF
    
    # 创建优化的站点配置
    local site_config="/etc/nginx/sites-available/$APP_NAME"
    cat > "$site_config" << EOF
# $APP_NAME 站点配置
server {
    listen 80;
    server_name _;
    
    # 安全头
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    
    # 静态文件缓存
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf|eot|svg)\$ {
        root $APP_HOME/public;
        expires $STATIC_CACHE_TTL;
        add_header Cache-Control "public, immutable";
        add_header Vary Accept-Encoding;
    }
    
    # API代理
    location /api/ {
        limit_req zone=api burst=20 nodelay;
        limit_conn conn 10;
        
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        
        # 缓存配置
        proxy_cache_valid 200 ${API_CACHE_TTL}s;
        proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
    }
    
    # 主应用代理
    location / {
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
}
EOF
    
    # 启用站点
    ln -sf "$site_config" "/etc/nginx/sites-enabled/$APP_NAME"
    
    # 测试配置
    if nginx -t; then
        systemctl reload nginx
        log_success "Nginx配置优化完成"
    else
        log_error "Nginx配置测试失败"
        return 1
    fi
}

# 优化数据库
optimize_database() {
    if [ "$DB_TYPE" != "postgresql" ]; then
        log_info "跳过数据库优化（使用文件存储）"
        return 0
    fi
    
    log_info "优化PostgreSQL数据库..."
    
    local pg_version=$(psql --version | awk '{print $3}' | sed 's/\..*//')
    local pg_config_dir="/etc/postgresql/$pg_version/main"
    local pg_config="$pg_config_dir/postgresql.conf"
    
    if [ ! -f "$pg_config" ]; then
        log_warn "PostgreSQL配置文件不存在，跳过数据库优化"
        return 0
    fi
    
    backup_config "$pg_config"
    
    # 计算内存相关参数
    local total_memory_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_memory_mb=$((total_memory_kb / 1024))
    local shared_buffers=$((total_memory_mb / 4))  # 25%的内存
    local effective_cache_size=$((total_memory_mb * 3 / 4))  # 75%的内存
    local work_mem=$((total_memory_mb / 100))  # 1%的内存
    local maintenance_work_mem=$((total_memory_mb / 16))  # 6.25%的内存
    
    # 添加优化配置
    cat >> "$pg_config" << EOF

# 性能优化配置 - 由性能优化脚本添加
# 生成时间: $(date)

# 内存配置
shared_buffers = ${shared_buffers}MB
effective_cache_size = ${effective_cache_size}MB
work_mem = ${work_mem}MB
maintenance_work_mem = ${maintenance_work_mem}MB

# 连接配置
max_connections = 200
superuser_reserved_connections = 3

# 检查点配置
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100

# 查询规划器
random_page_cost = 1.1
effective_io_concurrency = 200

# 并行查询
max_worker_processes = $(nproc)
max_parallel_workers_per_gather = $(($(nproc) / 2))
max_parallel_workers = $(nproc)
max_parallel_maintenance_workers = $(($(nproc) / 2))

# 日志配置
log_min_duration_statement = 1000
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
log_temp_files = 0

# 自动清理
autovacuum = on
autovacuum_max_workers = 3
autovacuum_naptime = 20s
autovacuum_vacuum_threshold = 50
autovacuum_analyze_threshold = 50
autovacuum_vacuum_scale_factor = 0.1
autovacuum_analyze_scale_factor = 0.05
EOF
    
    # 重启PostgreSQL
    systemctl restart postgresql
    
    log_success "PostgreSQL优化完成"
}

# 优化Redis
optimize_redis() {
    if [ "$REDIS_ENABLED" != "true" ] || ! command_exists redis-server; then
        log_info "跳过Redis优化（未启用或未安装）"
        return 0
    fi
    
    log_info "优化Redis配置..."
    
    local redis_config="/etc/redis/redis.conf"
    backup_config "$redis_config"
    
    # 添加优化配置
    cat >> "$redis_config" << EOF

# 性能优化配置 - 由性能优化脚本添加
# 生成时间: $(date)

# 内存配置
maxmemory $REDIS_MAXMEMORY
maxmemory-policy $REDIS_MAXMEMORY_POLICY

# 持久化优化
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes

# AOF配置
appendonly yes
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb

# 网络配置
tcp-keepalive 300
timeout 0

# 客户端配置
maxclients 10000

# 慢查询日志
slowlog-log-slower-than 10000
slowlog-max-len 128

# 延迟监控
latency-monitor-threshold 100
EOF
    
    # 重启Redis
    systemctl restart redis
    
    log_success "Redis优化完成"
}

# ============================================================================
# 性能监控和分析
# ============================================================================

# 性能基准测试
perform_benchmark() {
    log_info "执行性能基准测试..."
    
    local benchmark_results="/tmp/benchmark-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "申论行测学习系统 - 性能基准测试报告"
        echo "================================"
        echo "测试时间: $(date)"
        echo "主机名称: $(hostname)"
        echo "操作系统: $OS $VER"
        echo ""
        
        # CPU测试
        echo "CPU性能测试:"
        if command_exists sysbench; then
            echo "  CPU基准测试:"
            sysbench cpu --cpu-max-prime=20000 --threads=$(nproc) run | grep -E "(events per second|total time)"
        else
            echo "  CPU信息:"
            echo "    核心数: $(nproc)"
            echo "    频率: $(cat /proc/cpuinfo | grep 'cpu MHz' | head -1 | awk '{print $4}') MHz"
        fi
        echo ""
        
        # 内存测试
        echo "内存性能测试:"
        if command_exists sysbench; then
            echo "  内存基准测试:"
            sysbench memory --memory-block-size=1M --memory-total-size=10G run | grep -E "(transferred|total time)"
        else
            echo "  内存信息:"
            free -h
        fi
        echo ""
        
        # 磁盘I/O测试
        echo "磁盘I/O性能测试:"
        if command_exists dd; then
            echo "  写入测试:"
            dd if=/dev/zero of=/tmp/test_write bs=1M count=1024 oflag=direct 2>&1 | grep -E "(copied|MB/s)"
            echo "  读取测试:"
            dd if=/tmp/test_write of=/dev/null bs=1M iflag=direct 2>&1 | grep -E "(copied|MB/s)"
            rm -f /tmp/test_write
        fi
        echo ""
        
        # 网络测试
        echo "网络性能测试:"
        if command_exists iperf3; then
            echo "  本地回环测试:"
            iperf3 -s -D
            sleep 2
            iperf3 -c 127.0.0.1 -t 10
            pkill iperf3
        else
            echo "  网络接口信息:"
            ip addr show | grep -E "(inet |UP)"
        fi
        echo ""
        
        # 应用响应时间测试
        echo "应用响应时间测试:"
        if command_exists curl; then
            local app_url="http://localhost:$APP_PORT/health"
            echo "  健康检查响应时间:"
            for i in {1..5}; do
                local response_time=$(curl -o /dev/null -s -w "%{time_total}" "$app_url" 2>/dev/null || echo "N/A")
                echo "    测试 $i: ${response_time}s"
            done
        fi
        echo ""
        
        # 系统负载
        echo "系统负载信息:"
        echo "  当前负载: $(uptime | awk -F'load average:' '{print $2}')"
        echo "  CPU使用率: $(top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | sed 's/%us,//')%"
        echo "  内存使用率: $(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')"
        echo "  磁盘使用率: $(df / | tail -1 | awk '{print $5}')"
        
    } | tee "$benchmark_results"
    
    log_success "性能基准测试完成，报告已保存到: $benchmark_results"
}

# 性能分析
analyze_performance() {
    log_info "分析系统性能..."
    
    local analysis_report="/tmp/performance-analysis-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "申论行测学习系统 - 性能分析报告"
        echo "=============================="
        echo "分析时间: $(date)"
        echo "主机名称: $(hostname)"
        echo ""
        
        # 系统资源使用情况
        echo "系统资源使用情况:"
        echo "  CPU使用率: $(top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | sed 's/%us,//')%"
        echo "  内存使用率: $(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')"
        echo "  磁盘使用率: $(df / | tail -1 | awk '{print $5}')"
        echo "  系统负载: $(uptime | awk -F'load average:' '{print $2}')"
        echo ""
        
        # 进程分析
        echo "进程资源使用TOP 10:"
        ps aux --sort=-%cpu | head -11
        echo ""
        
        # 内存使用分析
        echo "内存使用分析:"
        echo "  总内存: $(free -h | grep Mem: | awk '{print $2}')"
        echo "  已用内存: $(free -h | grep Mem: | awk '{print $3}')"
        echo "  可用内存: $(free -h | grep Mem: | awk '{print $7}')"
        echo "  缓存/缓冲区: $(free -h | grep Mem: | awk '{print $6}')"
        echo "  Swap使用: $(free -h | grep Swap: | awk '{print $3}')"
        echo ""
        
        # 磁盘I/O分析
        echo "磁盘I/O分析:"
        if command_exists iostat; then
            iostat -x 1 3 | tail -n +4
        else
            echo "  磁盘使用情况:"
            df -h
        fi
        echo ""
        
        # 网络连接分析
        echo "网络连接分析:"
        echo "  活跃连接数: $(netstat -an | grep ESTABLISHED | wc -l)"
        echo "  监听端口数: $(netstat -tln | grep LISTEN | wc -l)"
        echo "  TIME_WAIT连接数: $(netstat -an | grep TIME_WAIT | wc -l)"
        echo ""
        
        # 应用性能分析
        echo "应用性能分析:"
        if pgrep -f "$APP_NAME" >/dev/null; then
            local app_pid=$(pgrep -f "$APP_NAME" | head -1)
            echo "  应用进程ID: $app_pid"
            echo "  CPU使用率: $(ps -p $app_pid -o %cpu --no-headers)%"
            echo "  内存使用率: $(ps -p $app_pid -o %mem --no-headers)%"
            echo "  内存使用量: $(ps -p $app_pid -o rss --no-headers | awk '{print int($1/1024)}')MB"
        else
            echo "  应用进程未运行"
        fi
        echo ""
        
        # 性能瓶颈识别
        echo "性能瓶颈识别:"
        local cpu_usage=$(top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | sed 's/%us,//' | cut -d. -f1)
        local mem_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
        local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
        local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | tr -d ' ')
        
        if [ "$cpu_usage" -gt 80 ]; then
            echo "  ⚠ CPU使用率过高 (${cpu_usage}%)"
        fi
        
        if [ "$mem_usage" -gt 80 ]; then
            echo "  ⚠ 内存使用率过高 (${mem_usage}%)"
        fi
        
        if [ "$disk_usage" -gt 85 ]; then
            echo "  ⚠ 磁盘使用率过高 (${disk_usage}%)"
        fi
        
        if (( $(echo "$load_avg > $(nproc)" | bc -l 2>/dev/null || echo 0) )); then
            echo "  ⚠ 系统负载过高 ($load_avg)"
        fi
        
        if [ "$cpu_usage" -lt 50 ] && [ "$mem_usage" -lt 50 ] && [ "$disk_usage" -lt 70 ]; then
            echo "  ✓ 系统性能良好"
        fi
        
        # 优化建议
        echo ""
        echo "优化建议:"
        echo "  1. 定期监控系统资源使用情况"
        echo "  2. 根据负载情况调整应用实例数量"
        echo "  3. 优化数据库查询和索引"
        echo "  4. 启用适当的缓存策略"
        echo "  5. 定期清理日志和临时文件"
        
    } | tee "$analysis_report"
    
    log_success "性能分析完成，报告已保存到: $analysis_report"
}

# ============================================================================
# 主函数
# ============================================================================

# 执行完整性能优化
perform_full_optimization() {
    log_info "开始执行完整性能优化..."
    
    local start_time=$(date +%s)
    
    # 检查环境
    check_root
    detect_os
    get_system_info
    
    # 创建日志目录
    mkdir -p "$LOG_PATH"
    
    # 执行系统优化
    optimize_kernel_parameters
    optimize_filesystem
    optimize_cpu_performance
    optimize_memory_management
    
    # 执行应用优化
    optimize_nodejs_app
    optimize_nginx
    optimize_database
    optimize_redis
    
    # 计算总耗时
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_success "性能优化完成，耗时 ${duration} 秒"
    
    # 执行性能测试
    log_info "执行性能基准测试..."
    perform_benchmark
    
    # 执行性能分析
    analyze_performance
}

# 显示帮助信息
show_help() {
    cat << EOF
申论行测学习系统 - 性能优化脚本

用法:
  $0 <命令> [选项]

命令:
  optimize                      执行完整性能优化
  kernel                        优化内核参数
  filesystem                    优化文件系统
  cpu                          优化CPU性能
  memory                       优化内存管理
  nodejs                       优化Node.js应用
  nginx                        优化Nginx配置
  database                     优化数据库
  redis                        优化Redis
  benchmark                    执行性能基准测试
  analyze                      分析系统性能
  help                         显示帮助信息

示例:
  $0 optimize                  执行完整性能优化
  $0 kernel                    优化内核参数
  $0 benchmark                 执行性能基准测试
  $0 analyze                   分析系统性能

环境变量:
  OPTIMIZE_KERNEL              是否优化内核参数
  OPTIMIZE_NETWORK             是否优化网络性能
  OPTIMIZE_FILESYSTEM          是否优化文件系统
  NODE_OPTIONS                 Node.js优化选项
  NGINX_WORKER_PROCESSES       Nginx工作进程数
EOF
}

# 主函数
main() {
    # 确保日志目录存在
    mkdir -p "$LOG_PATH"
    
    case "${1:-help}" in
        "optimize")
            perform_full_optimization
            ;;
        "kernel")
            check_root
            detect_os
            optimize_kernel_parameters
            ;;
        "filesystem")
            check_root
            optimize_filesystem
            ;;
        "cpu")
            check_root
            optimize_cpu_performance
            ;;
        "memory")
            check_root
            optimize_memory_management
            ;;
        "nodejs")
            optimize_nodejs_app
            ;;
        "nginx")
            check_root
            optimize_nginx
            ;;
        "database")
            check_root
            optimize_database
            ;;
        "redis")
            check_root
            optimize_redis
            ;;
        "benchmark")
            perform_benchmark
            ;;
        "analyze")
            analyze_performance
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