#!/bin/bash
# 申论行测学习系统 - 系统监控和维护脚本
# 版本: v2.0.0
# 描述: 系统健康检查、性能监控和自动维护脚本

set -e

# ============================================================================
# 配置变量
# ============================================================================

# 应用配置
APP_NAME="${APP_NAME:-shenlun-xingce-system}"
APP_VERSION="${APP_VERSION:-2.0.0}"
APP_PORT="${APP_PORT:-3000}"
APP_HOST="${APP_HOST:-localhost}"
APP_PID_FILE="${APP_PID_FILE:-/app/app.pid}"
DATA_PATH="${DATA_PATH:-/app/data}"
LOG_PATH="${LOG_PATH:-/app/logs}"

# 监控配置
MONITOR_INTERVAL="${MONITOR_INTERVAL:-60}"  # 监控间隔（秒）
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-10}"  # 健康检查超时（秒）
MAX_RETRIES="${MAX_RETRIES:-3}"  # 最大重试次数
RESTART_THRESHOLD="${RESTART_THRESHOLD:-5}"  # 连续失败重启阈值

# 性能阈值
CPU_THRESHOLD="${CPU_THRESHOLD:-80}"  # CPU使用率阈值（%）
MEMORY_THRESHOLD="${MEMORY_THRESHOLD:-80}"  # 内存使用率阈值（%）
DISK_THRESHOLD="${DISK_THRESHOLD:-85}"  # 磁盘使用率阈值（%）
LOAD_THRESHOLD="${LOAD_THRESHOLD:-2.0}"  # 系统负载阈值
RESPONSE_TIME_THRESHOLD="${RESPONSE_TIME_THRESHOLD:-5000}"  # 响应时间阈值（毫秒）

# 日志配置
LOG_MAX_SIZE="${LOG_MAX_SIZE:-100M}"  # 单个日志文件最大大小
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-30}"  # 日志保留天数
LOG_ROTATION_ENABLED="${LOG_ROTATION_ENABLED:-true}"  # 是否启用日志轮转

# 数据库配置
DB_TYPE="${DB_TYPE:-file}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-shenlun_system}"
DB_USER="${DB_USER:-app_user}"
DB_PASSWORD="${DB_PASSWORD:-}"
DB_MAX_CONNECTIONS="${DB_MAX_CONNECTIONS:-100}"

# Redis配置
REDIS_ENABLED="${REDIS_ENABLED:-false}"
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"

# 通知配置
NOTIFICATION_ENABLED="${NOTIFICATION_ENABLED:-false}"
NOTIFICATION_WEBHOOK="${NOTIFICATION_WEBHOOK:-}"
NOTIFICATION_EMAIL="${NOTIFICATION_EMAIL:-}"
ALERT_COOLDOWN="${ALERT_COOLDOWN:-300}"  # 告警冷却时间（秒）

# 自动维护配置
AUTO_RESTART_ENABLED="${AUTO_RESTART_ENABLED:-true}"
AUTO_CLEANUP_ENABLED="${AUTO_CLEANUP_ENABLED:-true}"
AUTO_BACKUP_ENABLED="${AUTO_BACKUP_ENABLED:-false}"
MAINTENANCE_WINDOW="${MAINTENANCE_WINDOW:-02:00-04:00}"  # 维护时间窗口

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 状态文件
STATUS_FILE="/tmp/${APP_NAME}-monitor.status"
ALERT_FILE="/tmp/${APP_NAME}-alerts.log"
METRICS_FILE="/tmp/${APP_NAME}-metrics.log"

# ============================================================================
# 工具函数
# ============================================================================

# 日志函数
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_PATH/monitor.log"
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

log_debug() {
    if [ "${DEBUG:-false}" = "true" ]; then
        log "${PURPLE}[DEBUG]${NC} $1"
    fi
}

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 获取当前时间戳
get_timestamp() {
    date +%s
}

# 检查是否在维护时间窗口内
in_maintenance_window() {
    local current_time=$(date +"%H:%M")
    local start_time=$(echo "$MAINTENANCE_WINDOW" | cut -d'-' -f1)
    local end_time=$(echo "$MAINTENANCE_WINDOW" | cut -d'-' -f2)
    
    if [[ "$current_time" > "$start_time" && "$current_time" < "$end_time" ]]; then
        return 0
    else
        return 1
    fi
}

# 发送告警通知
send_alert() {
    local title="$1"
    local message="$2"
    local severity="$3"  # info, warning, critical
    local component="$4"
    
    if [ "$NOTIFICATION_ENABLED" != "true" ]; then
        return 0
    fi
    
    # 检查告警冷却时间
    local alert_key="${component:-system}-${severity}"
    local last_alert_file="/tmp/${APP_NAME}-last-alert-${alert_key}"
    local current_time=$(get_timestamp)
    
    if [ -f "$last_alert_file" ]; then
        local last_alert_time=$(cat "$last_alert_file")
        local time_diff=$((current_time - last_alert_time))
        
        if [ $time_diff -lt $ALERT_COOLDOWN ]; then
            log_debug "告警在冷却期内，跳过发送: $title"
            return 0
        fi
    fi
    
    # 记录告警时间
    echo "$current_time" > "$last_alert_file"
    
    # 记录告警日志
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$severity] [$component] $title: $message" >> "$ALERT_FILE"
    
    log_warn "发送告警: $title"
    
    # Webhook通知
    if [ -n "$NOTIFICATION_WEBHOOK" ] && command_exists curl; then
        local color
        case "$severity" in
            "info") color="#0099ff" ;;
            "warning") color="#ff9900" ;;
            "critical") color="#ff0000" ;;
            *) color="#666666" ;;
        esac
        
        curl -s -X POST "$NOTIFICATION_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{
                \"embeds\": [{
                    \"title\": \"🚨 $title\",
                    \"description\": \"$message\",
                    \"color\": \"$color\",
                    \"fields\": [
                        {
                            \"name\": \"严重程度\",
                            \"value\": \"$severity\",
                            \"inline\": true
                        },
                        {
                            \"name\": \"组件\",
                            \"value\": \"${component:-系统}\",
                            \"inline\": true
                        },
                        {
                            \"name\": \"主机\",
                            \"value\": \"$(hostname)\",
                            \"inline\": true
                        }
                    ],
                    \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",
                    \"footer\": {
                        \"text\": \"$APP_NAME v$APP_VERSION 监控系统\"
                    }
                }]
            }" >/dev/null 2>&1 || true
    fi
    
    # 邮件通知
    if [ -n "$NOTIFICATION_EMAIL" ] && command_exists mail; then
        {
            echo "告警详情:"
            echo "标题: $title"
            echo "消息: $message"
            echo "严重程度: $severity"
            echo "组件: ${component:-系统}"
            echo "主机: $(hostname)"
            echo "时间: $(date)"
            echo ""
            echo "-- "
            echo "$APP_NAME v$APP_VERSION 监控系统"
        } | mail -s "[$APP_NAME] $severity: $title" "$NOTIFICATION_EMAIL" >/dev/null 2>&1 || true
    fi
}

# ============================================================================
# 系统监控函数
# ============================================================================

# 检查应用进程状态
check_app_process() {
    log_debug "检查应用进程状态..."
    
    local status="unknown"
    local pid=""
    local cpu_usage="0"
    local memory_usage="0"
    local memory_mb="0"
    
    # 检查PID文件
    if [ -f "$APP_PID_FILE" ]; then
        pid=$(cat "$APP_PID_FILE" 2>/dev/null || echo "")
        
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            status="running"
            
            # 获取CPU和内存使用率
            if command_exists ps; then
                local ps_output=$(ps -p "$pid" -o pid,pcpu,pmem,rss --no-headers 2>/dev/null || echo "")
                if [ -n "$ps_output" ]; then
                    cpu_usage=$(echo "$ps_output" | awk '{print $2}')
                    memory_usage=$(echo "$ps_output" | awk '{print $3}')
                    memory_mb=$(echo "$ps_output" | awk '{print int($4/1024)}')
                fi
            fi
        else
            status="stopped"
            # 清理无效的PID文件
            rm -f "$APP_PID_FILE"
        fi
    else
        # 尝试通过进程名查找
        if command_exists pgrep; then
            pid=$(pgrep -f "$APP_NAME" | head -1 || echo "")
            if [ -n "$pid" ]; then
                status="running"
                echo "$pid" > "$APP_PID_FILE"
            else
                status="stopped"
            fi
        else
            status="stopped"
        fi
    fi
    
    # 记录指标
    echo "app_process_status{status=\"$status\"} $([ "$status" = "running" ] && echo 1 || echo 0)" >> "$METRICS_FILE"
    echo "app_cpu_usage $cpu_usage" >> "$METRICS_FILE"
    echo "app_memory_usage $memory_usage" >> "$METRICS_FILE"
    echo "app_memory_mb $memory_mb" >> "$METRICS_FILE"
    
    # 检查资源使用率
    if [ "$status" = "running" ]; then
        if (( $(echo "$cpu_usage > $CPU_THRESHOLD" | bc -l 2>/dev/null || echo 0) )); then
            send_alert "应用CPU使用率过高" "当前CPU使用率: ${cpu_usage}%，阈值: ${CPU_THRESHOLD}%" "warning" "application"
        fi
        
        if (( $(echo "$memory_usage > $MEMORY_THRESHOLD" | bc -l 2>/dev/null || echo 0) )); then
            send_alert "应用内存使用率过高" "当前内存使用率: ${memory_usage}%，阈值: ${MEMORY_THRESHOLD}%" "warning" "application"
        fi
    fi
    
    echo "$status|$pid|$cpu_usage|$memory_usage|$memory_mb"
}

# 检查应用健康状态
check_app_health() {
    log_debug "检查应用健康状态..."
    
    local health_url="http://$APP_HOST:$APP_PORT/health"
    local status="unknown"
    local response_time="0"
    local http_code="0"
    
    if command_exists curl; then
        local start_time=$(date +%s%3N)
        local response=$(curl -s -w "%{http_code}" -m "$HEALTH_CHECK_TIMEOUT" "$health_url" 2>/dev/null || echo "000")
        local end_time=$(date +%s%3N)
        
        http_code="${response: -3}"
        response_time=$((end_time - start_time))
        
        if [ "$http_code" = "200" ]; then
            status="healthy"
        elif [ "$http_code" = "000" ]; then
            status="unreachable"
        else
            status="unhealthy"
        fi
    elif command_exists wget; then
        local start_time=$(date +%s%3N)
        if wget -q -T "$HEALTH_CHECK_TIMEOUT" -O /dev/null "$health_url" 2>/dev/null; then
            status="healthy"
            http_code="200"
        else
            status="unreachable"
            http_code="000"
        fi
        local end_time=$(date +%s%3N)
        response_time=$((end_time - start_time))
    else
        # 使用端口检查作为备选方案
        if command_exists nc; then
            if nc -z "$APP_HOST" "$APP_PORT" 2>/dev/null; then
                status="reachable"
                http_code="200"
            else
                status="unreachable"
                http_code="000"
            fi
        fi
    fi
    
    # 记录指标
    echo "app_health_status{status=\"$status\"} $([ "$status" = "healthy" ] && echo 1 || echo 0)" >> "$METRICS_FILE"
    echo "app_response_time $response_time" >> "$METRICS_FILE"
    echo "app_http_code $http_code" >> "$METRICS_FILE"
    
    # 检查响应时间
    if [ "$status" = "healthy" ] && [ $response_time -gt $RESPONSE_TIME_THRESHOLD ]; then
        send_alert "应用响应时间过长" "当前响应时间: ${response_time}ms，阈值: ${RESPONSE_TIME_THRESHOLD}ms" "warning" "application"
    fi
    
    echo "$status|$response_time|$http_code"
}

# 检查系统资源
check_system_resources() {
    log_debug "检查系统资源..."
    
    local cpu_usage="0"
    local memory_usage="0"
    local disk_usage="0"
    local load_avg="0"
    local disk_free="0"
    local memory_free="0"
    
    # CPU使用率
    if command_exists top; then
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' 2>/dev/null || echo "0")
    elif [ -f /proc/loadavg ]; then
        load_avg=$(cat /proc/loadavg | awk '{print $1}')
        # 简单估算CPU使用率
        cpu_usage=$(echo "$load_avg * 100 / $(nproc)" | bc -l 2>/dev/null | cut -d. -f1 || echo "0")
    fi
    
    # 内存使用率
    if [ -f /proc/meminfo ]; then
        local mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        local mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}' 2>/dev/null || \
                             grep MemFree /proc/meminfo | awk '{print $2}')
        
        if [ "$mem_total" -gt 0 ] && [ "$mem_available" -gt 0 ]; then
            memory_usage=$(echo "($mem_total - $mem_available) * 100 / $mem_total" | bc -l | cut -d. -f1)
            memory_free=$(echo "$mem_available / 1024" | bc -l | cut -d. -f1)  # MB
        fi
    elif command_exists free; then
        local mem_info=$(free | grep Mem:)
        local mem_total=$(echo "$mem_info" | awk '{print $2}')
        local mem_used=$(echo "$mem_info" | awk '{print $3}')
        
        if [ "$mem_total" -gt 0 ]; then
            memory_usage=$(echo "$mem_used * 100 / $mem_total" | bc -l | cut -d. -f1)
            memory_free=$(echo "($mem_total - $mem_used) / 1024" | bc -l | cut -d. -f1)  # MB
        fi
    fi
    
    # 磁盘使用率
    if command_exists df; then
        local disk_info=$(df "$DATA_PATH" 2>/dev/null | tail -1)
        if [ -n "$disk_info" ]; then
            disk_usage=$(echo "$disk_info" | awk '{print $5}' | sed 's/%//')
            disk_free=$(echo "$disk_info" | awk '{print int($4/1024)}')  # MB
        fi
    fi
    
    # 系统负载
    if [ -f /proc/loadavg ]; then
        load_avg=$(cat /proc/loadavg | awk '{print $1}')
    fi
    
    # 记录指标
    echo "system_cpu_usage $cpu_usage" >> "$METRICS_FILE"
    echo "system_memory_usage $memory_usage" >> "$METRICS_FILE"
    echo "system_memory_free_mb $memory_free" >> "$METRICS_FILE"
    echo "system_disk_usage $disk_usage" >> "$METRICS_FILE"
    echo "system_disk_free_mb $disk_free" >> "$METRICS_FILE"
    echo "system_load_avg $load_avg" >> "$METRICS_FILE"
    
    # 检查阈值
    if [ "$cpu_usage" -gt "$CPU_THRESHOLD" ]; then
        send_alert "系统CPU使用率过高" "当前CPU使用率: ${cpu_usage}%，阈值: ${CPU_THRESHOLD}%" "warning" "system"
    fi
    
    if [ "$memory_usage" -gt "$MEMORY_THRESHOLD" ]; then
        send_alert "系统内存使用率过高" "当前内存使用率: ${memory_usage}%，阈值: ${MEMORY_THRESHOLD}%" "warning" "system"
    fi
    
    if [ "$disk_usage" -gt "$DISK_THRESHOLD" ]; then
        send_alert "磁盘空间不足" "当前磁盘使用率: ${disk_usage}%，阈值: ${DISK_THRESHOLD}%" "critical" "system"
    fi
    
    if (( $(echo "$load_avg > $LOAD_THRESHOLD" | bc -l 2>/dev/null || echo 0) )); then
        send_alert "系统负载过高" "当前系统负载: $load_avg，阈值: $LOAD_THRESHOLD" "warning" "system"
    fi
    
    echo "$cpu_usage|$memory_usage|$disk_usage|$load_avg|$disk_free|$memory_free"
}

# 检查数据库状态
check_database() {
    if [ "$DB_TYPE" != "postgresql" ]; then
        log_debug "跳过数据库检查（使用文件存储）"
        return 0
    fi
    
    log_debug "检查PostgreSQL数据库状态..."
    
    local status="unknown"
    local connections="0"
    local response_time="0"
    
    if command_exists psql; then
        export PGPASSWORD="$DB_PASSWORD"
        
        local start_time=$(date +%s%3N)
        if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
            -c "SELECT 1;" >/dev/null 2>&1; then
            status="healthy"
            
            # 获取连接数
            connections=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
                -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | tr -d ' ' || echo "0")
        else
            status="unhealthy"
        fi
        local end_time=$(date +%s%3N)
        response_time=$((end_time - start_time))
        
        unset PGPASSWORD
    fi
    
    # 记录指标
    echo "db_status{status=\"$status\"} $([ "$status" = "healthy" ] && echo 1 || echo 0)" >> "$METRICS_FILE"
    echo "db_connections $connections" >> "$METRICS_FILE"
    echo "db_response_time $response_time" >> "$METRICS_FILE"
    
    # 检查连接数
    if [ "$connections" -gt "$DB_MAX_CONNECTIONS" ]; then
        send_alert "数据库连接数过多" "当前连接数: $connections，最大连接数: $DB_MAX_CONNECTIONS" "warning" "database"
    fi
    
    echo "$status|$connections|$response_time"
}

# 检查Redis状态
check_redis() {
    if [ "$REDIS_ENABLED" != "true" ]; then
        log_debug "跳过Redis检查（未启用）"
        return 0
    fi
    
    log_debug "检查Redis状态..."
    
    local status="unknown"
    local memory_usage="0"
    local connections="0"
    local response_time="0"
    
    if command_exists redis-cli; then
        local redis_cmd="redis-cli -h $REDIS_HOST -p $REDIS_PORT"
        if [ -n "$REDIS_PASSWORD" ]; then
            redis_cmd="$redis_cmd -a $REDIS_PASSWORD"
        fi
        
        local start_time=$(date +%s%3N)
        if $redis_cmd ping >/dev/null 2>&1; then
            status="healthy"
            
            # 获取内存使用情况
            local info_memory=$($redis_cmd info memory 2>/dev/null || echo "")
            if [ -n "$info_memory" ]; then
                memory_usage=$(echo "$info_memory" | grep "used_memory:" | cut -d: -f2 | tr -d '\r')
            fi
            
            # 获取连接数
            local info_clients=$($redis_cmd info clients 2>/dev/null || echo "")
            if [ -n "$info_clients" ]; then
                connections=$(echo "$info_clients" | grep "connected_clients:" | cut -d: -f2 | tr -d '\r')
            fi
        else
            status="unhealthy"
        fi
        local end_time=$(date +%s%3N)
        response_time=$((end_time - start_time))
    fi
    
    # 记录指标
    echo "redis_status{status=\"$status\"} $([ "$status" = "healthy" ] && echo 1 || echo 0)" >> "$METRICS_FILE"
    echo "redis_memory_usage $memory_usage" >> "$METRICS_FILE"
    echo "redis_connections $connections" >> "$METRICS_FILE"
    echo "redis_response_time $response_time" >> "$METRICS_FILE"
    
    echo "$status|$memory_usage|$connections|$response_time"
}

# ============================================================================
# 维护函数
# ============================================================================

# 日志轮转
rotate_logs() {
    if [ "$LOG_ROTATION_ENABLED" != "true" ]; then
        return 0
    fi
    
    log_info "执行日志轮转..."
    
    local rotated_count=0
    
    # 查找需要轮转的日志文件
    find "$LOG_PATH" -name "*.log" -type f | while read -r log_file; do
        local file_size=$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo "0")
        local max_size_bytes
        
        # 转换大小单位
        case "$LOG_MAX_SIZE" in
            *K|*k) max_size_bytes=$(echo "$LOG_MAX_SIZE" | sed 's/[Kk]//' | awk '{print $1 * 1024}') ;;
            *M|*m) max_size_bytes=$(echo "$LOG_MAX_SIZE" | sed 's/[Mm]//' | awk '{print $1 * 1024 * 1024}') ;;
            *G|*g) max_size_bytes=$(echo "$LOG_MAX_SIZE" | sed 's/[Gg]//' | awk '{print $1 * 1024 * 1024 * 1024}') ;;
            *) max_size_bytes="$LOG_MAX_SIZE" ;;
        esac
        
        if [ "$file_size" -gt "$max_size_bytes" ]; then
            local timestamp=$(date +"%Y%m%d-%H%M%S")
            local rotated_file="${log_file}.${timestamp}"
            
            # 轮转日志文件
            mv "$log_file" "$rotated_file"
            touch "$log_file"
            
            # 压缩旧日志
            if command_exists gzip; then
                gzip "$rotated_file"
            fi
            
            rotated_count=$((rotated_count + 1))
            log_info "已轮转日志文件: $(basename "$log_file")"
        fi
    done
    
    # 清理旧日志文件
    find "$LOG_PATH" -name "*.log.*" -type f -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null || true
    
    if [ $rotated_count -gt 0 ]; then
        log_success "日志轮转完成，共轮转 $rotated_count 个文件"
    fi
}

# 清理临时文件
cleanup_temp_files() {
    log_info "清理临时文件..."
    
    local cleaned_count=0
    
    # 清理应用临时文件
    if [ -d "/tmp" ]; then
        find /tmp -name "${APP_NAME}-*" -type f -mtime +1 -delete 2>/dev/null || true
        cleaned_count=$((cleaned_count + $(find /tmp -name "${APP_NAME}-*" -type f -mtime +1 2>/dev/null | wc -l || echo 0)))
    fi
    
    # 清理应用数据目录中的临时文件
    if [ -d "$DATA_PATH/temp" ]; then
        find "$DATA_PATH/temp" -type f -mtime +1 -delete 2>/dev/null || true
        find "$DATA_PATH/temp" -type d -empty -delete 2>/dev/null || true
    fi
    
    # 清理上传临时文件
    if [ -d "$DATA_PATH/uploads/temp" ]; then
        find "$DATA_PATH/uploads/temp" -type f -mtime +1 -delete 2>/dev/null || true
    fi
    
    log_success "临时文件清理完成"
}

# 重启应用
restart_application() {
    log_warn "准备重启应用..."
    
    # 检查是否在维护时间窗口内
    if ! in_maintenance_window && [ "${FORCE_RESTART:-false}" != "true" ]; then
        log_warn "当前不在维护时间窗口内，跳过重启"
        return 1
    fi
    
    # 发送重启通知
    send_alert "应用重启" "应用即将重启以恢复服务" "info" "application"
    
    # 执行重启
    if [ -f "/app/scripts/app-control.sh" ]; then
        /app/scripts/app-control.sh restart
    elif command_exists systemctl; then
        systemctl restart "$APP_NAME" 2>/dev/null || true
    elif command_exists pm2; then
        pm2 restart "$APP_NAME" 2>/dev/null || true
    else
        # 手动重启
        if [ -f "$APP_PID_FILE" ]; then
            local pid=$(cat "$APP_PID_FILE")
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                kill "$pid"
                sleep 5
                
                # 如果进程仍然存在，强制杀死
                if kill -0 "$pid" 2>/dev/null; then
                    kill -9 "$pid"
                fi
            fi
            rm -f "$APP_PID_FILE"
        fi
        
        # 启动应用
        cd /app
        nohup node app.js > "$LOG_PATH/app.log" 2>&1 &
        echo $! > "$APP_PID_FILE"
    fi
    
    # 等待应用启动
    sleep 10
    
    # 验证重启是否成功
    local health_result=$(check_app_health)
    local health_status=$(echo "$health_result" | cut -d'|' -f1)
    
    if [ "$health_status" = "healthy" ]; then
        log_success "应用重启成功"
        send_alert "应用重启成功" "应用已成功重启并恢复正常服务" "info" "application"
    else
        log_error "应用重启失败"
        send_alert "应用重启失败" "应用重启后仍无法正常提供服务" "critical" "application"
        return 1
    fi
}

# ============================================================================
# 监控主循环
# ============================================================================

# 执行单次检查
perform_health_check() {
    local timestamp=$(date +%s)
    
    # 清空指标文件
    echo "# HELP 申论行测学习系统监控指标" > "$METRICS_FILE"
    echo "# TYPE timestamp gauge" >> "$METRICS_FILE"
    echo "timestamp $timestamp" >> "$METRICS_FILE"
    
    log_info "开始健康检查..."
    
    # 检查应用进程
    local process_result=$(check_app_process)
    local process_status=$(echo "$process_result" | cut -d'|' -f1)
    local process_pid=$(echo "$process_result" | cut -d'|' -f2)
    local process_cpu=$(echo "$process_result" | cut -d'|' -f3)
    local process_memory=$(echo "$process_result" | cut -d'|' -f4)
    
    # 检查应用健康状态
    local health_result=$(check_app_health)
    local health_status=$(echo "$health_result" | cut -d'|' -f1)
    local response_time=$(echo "$health_result" | cut -d'|' -f2)
    local http_code=$(echo "$health_result" | cut -d'|' -f3)
    
    # 检查系统资源
    local system_result=$(check_system_resources)
    local system_cpu=$(echo "$system_result" | cut -d'|' -f1)
    local system_memory=$(echo "$system_result" | cut -d'|' -f2)
    local system_disk=$(echo "$system_result" | cut -d'|' -f3)
    local system_load=$(echo "$system_result" | cut -d'|' -f4)
    
    # 检查数据库
    local db_result=$(check_database)
    if [ -n "$db_result" ]; then
        local db_status=$(echo "$db_result" | cut -d'|' -f1)
        local db_connections=$(echo "$db_result" | cut -d'|' -f2)
    fi
    
    # 检查Redis
    local redis_result=$(check_redis)
    if [ -n "$redis_result" ]; then
        local redis_status=$(echo "$redis_result" | cut -d'|' -f1)
        local redis_memory=$(echo "$redis_result" | cut -d'|' -f2)
    fi
    
    # 更新状态文件
    cat > "$STATUS_FILE" << EOF
{
  "timestamp": $timestamp,
  "application": {
    "process_status": "$process_status",
    "health_status": "$health_status",
    "pid": "$process_pid",
    "cpu_usage": "$process_cpu",
    "memory_usage": "$process_memory",
    "response_time": "$response_time",
    "http_code": "$http_code"
  },
  "system": {
    "cpu_usage": "$system_cpu",
    "memory_usage": "$system_memory",
    "disk_usage": "$system_disk",
    "load_avg": "$system_load"
  },
  "database": {
    "status": "${db_status:-n/a}",
    "connections": "${db_connections:-0}"
  },
  "redis": {
    "status": "${redis_status:-n/a}",
    "memory_usage": "${redis_memory:-0}"
  }
}
EOF
    
    # 检查是否需要重启应用
    if [ "$AUTO_RESTART_ENABLED" = "true" ]; then
        local failure_count_file="/tmp/${APP_NAME}-failure-count"
        
        if [ "$process_status" != "running" ] || [ "$health_status" != "healthy" ]; then
            # 增加失败计数
            local failure_count=1
            if [ -f "$failure_count_file" ]; then
                failure_count=$(cat "$failure_count_file")
                failure_count=$((failure_count + 1))
            fi
            echo "$failure_count" > "$failure_count_file"
            
            log_warn "应用状态异常，失败计数: $failure_count/$RESTART_THRESHOLD"
            
            # 达到重启阈值
            if [ $failure_count -ge $RESTART_THRESHOLD ]; then
                log_warn "达到重启阈值，准备重启应用"
                if restart_application; then
                    rm -f "$failure_count_file"
                fi
            fi
        else
            # 应用正常，清除失败计数
            rm -f "$failure_count_file"
        fi
    fi
    
    log_success "健康检查完成"
}

# 监控主循环
start_monitoring() {
    log_info "启动系统监控，监控间隔: ${MONITOR_INTERVAL}秒"
    
    # 创建必要的目录
    mkdir -p "$LOG_PATH"
    mkdir -p "$(dirname "$STATUS_FILE")"
    
    # 信号处理
    trap 'log_info "收到停止信号，退出监控"; exit 0' TERM INT
    
    while true; do
        perform_health_check
        
        # 执行维护任务
        if [ "$AUTO_CLEANUP_ENABLED" = "true" ]; then
            # 每小时执行一次清理
            local current_minute=$(date +%M)
            if [ "$current_minute" = "00" ]; then
                cleanup_temp_files
                rotate_logs
            fi
        fi
        
        sleep "$MONITOR_INTERVAL"
    done
}

# ============================================================================
# 报告函数
# ============================================================================

# 生成监控报告
generate_report() {
    local report_type="${1:-summary}"  # summary, detailed, metrics
    
    echo "申论行测学习系统 - 监控报告"
    echo "=============================="
    echo "生成时间: $(date)"
    echo "主机名称: $(hostname)"
    echo "系统版本: $(uname -a)"
    echo ""
    
    if [ -f "$STATUS_FILE" ]; then
        echo "当前状态:"
        if command_exists jq; then
            jq . "$STATUS_FILE" 2>/dev/null || cat "$STATUS_FILE"
        else
            cat "$STATUS_FILE"
        fi
        echo ""
    fi
    
    if [ "$report_type" = "detailed" ] || [ "$report_type" = "metrics" ]; then
        echo "性能指标:"
        if [ -f "$METRICS_FILE" ]; then
            cat "$METRICS_FILE"
        fi
        echo ""
    fi
    
    if [ "$report_type" = "detailed" ]; then
        echo "最近告警:"
        if [ -f "$ALERT_FILE" ]; then
            tail -20 "$ALERT_FILE" 2>/dev/null || echo "无告警记录"
        else
            echo "无告警记录"
        fi
        echo ""
        
        echo "系统信息:"
        echo "  CPU核心数: $(nproc)"
        echo "  总内存: $(free -h | grep Mem: | awk '{print $2}' 2>/dev/null || echo '未知')"
        echo "  磁盘空间: $(df -h "$DATA_PATH" | tail -1 | awk '{print $2}' 2>/dev/null || echo '未知')"
        echo "  系统运行时间: $(uptime -p 2>/dev/null || uptime)"
    fi
}

# 显示帮助信息
show_help() {
    cat << EOF
申论行测学习系统 - 系统监控和维护脚本

用法:
  $0 <命令> [选项]

命令:
  start                         启动监控服务
  check                         执行单次健康检查
  status                        显示当前状态
  report [summary|detailed|metrics]  生成监控报告
  restart                       重启应用
  cleanup                       清理临时文件和日志
  rotate-logs                   执行日志轮转
  help                          显示帮助信息

示例:
  $0 start                      启动监控服务
  $0 check                      执行健康检查
  $0 status                     查看当前状态
  $0 report detailed            生成详细报告
  $0 restart                    重启应用

环境变量:
  MONITOR_INTERVAL              监控间隔（秒）
  CPU_THRESHOLD                 CPU使用率阈值（%）
  MEMORY_THRESHOLD              内存使用率阈值（%）
  DISK_THRESHOLD                磁盘使用率阈值（%）
  AUTO_RESTART_ENABLED          是否启用自动重启
  NOTIFICATION_ENABLED          是否启用通知
EOF
}

# 主函数
main() {
    # 确保日志目录存在
    mkdir -p "$LOG_PATH"
    
    case "${1:-help}" in
        "start")
            start_monitoring
            ;;
        "check")
            perform_health_check
            ;;
        "status")
            if [ -f "$STATUS_FILE" ]; then
                if command_exists jq; then
                    jq . "$STATUS_FILE"
                else
                    cat "$STATUS_FILE"
                fi
            else
                echo "状态文件不存在，请先执行健康检查"
                exit 1
            fi
            ;;
        "report")
            generate_report "${2:-summary}"
            ;;
        "restart")
            FORCE_RESTART=true restart_application
            ;;
        "cleanup")
            cleanup_temp_files
            rotate_logs
            ;;
        "rotate-logs")
            rotate_logs
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