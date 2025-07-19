#!/bin/bash
# 申论行测学习系统 - Docker健康检查脚本
# 版本: v2.0.0
# 描述: 容器健康状态检查脚本

set -e

# ============================================================================
# 配置变量
# ============================================================================

# 应用配置
APP_HOST="${APP_HOST:-localhost}"
APP_PORT="${PORT:-3000}"
HEALTH_ENDPOINT="${HEALTH_ENDPOINT:-/api/health}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-10}"

# 检查配置
MAX_RETRIES="${HEALTH_MAX_RETRIES:-3}"
RETRY_INTERVAL="${HEALTH_RETRY_INTERVAL:-2}"

# 日志配置
LOG_LEVEL="${LOG_LEVEL:-info}"
QUIET_MODE="${HEALTH_QUIET:-false}"

# ============================================================================
# 工具函数
# ============================================================================

# 日志函数
log() {
    if [ "$QUIET_MODE" != "true" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [HEALTH] $1" >&2
    fi
}

log_debug() {
    if [ "$LOG_LEVEL" = "debug" ]; then
        log "DEBUG: $1"
    fi
}

log_info() {
    log "INFO: $1"
}

log_warn() {
    log "WARN: $1"
}

log_error() {
    log "ERROR: $1"
}

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ============================================================================
# 健康检查函数
# ============================================================================

# 检查进程是否运行
check_process() {
    log_debug "检查Node.js进程"
    
    if pgrep -f "node.*server.js" >/dev/null 2>&1; then
        log_debug "Node.js进程正在运行"
        return 0
    else
        log_error "Node.js进程未运行"
        return 1
    fi
}

# 检查端口是否监听
check_port() {
    log_debug "检查端口 $APP_PORT 是否监听"
    
    if command_exists netstat; then
        if netstat -tln 2>/dev/null | grep -q ":$APP_PORT "; then
            log_debug "端口 $APP_PORT 正在监听"
            return 0
        fi
    elif command_exists ss; then
        if ss -tln 2>/dev/null | grep -q ":$APP_PORT "; then
            log_debug "端口 $APP_PORT 正在监听"
            return 0
        fi
    elif command_exists nc; then
        if nc -z "$APP_HOST" "$APP_PORT" 2>/dev/null; then
            log_debug "端口 $APP_PORT 正在监听"
            return 0
        fi
    fi
    
    log_error "端口 $APP_PORT 未监听"
    return 1
}

# 检查HTTP健康端点
check_http_health() {
    log_debug "检查HTTP健康端点"
    
    local url="http://$APP_HOST:$APP_PORT$HEALTH_ENDPOINT"
    local response
    local http_code
    
    if command_exists curl; then
        # 使用curl检查
        response=$(curl -s -w "\n%{http_code}" \
            --max-time "$HEALTH_TIMEOUT" \
            --connect-timeout 5 \
            --retry 0 \
            "$url" 2>/dev/null || echo "000")
        
        http_code=$(echo "$response" | tail -n1)
        response_body=$(echo "$response" | head -n -1)
        
    elif command_exists wget; then
        # 使用wget检查
        response=$(wget -qO- \
            --timeout="$HEALTH_TIMEOUT" \
            --connect-timeout=5 \
            --tries=1 \
            "$url" 2>/dev/null || echo "")
        
        if [ -n "$response" ]; then
            http_code="200"
        else
            http_code="000"
        fi
        response_body="$response"
        
    else
        log_error "curl或wget命令不可用"
        return 1
    fi
    
    log_debug "HTTP响应码: $http_code"
    log_debug "响应内容: $response_body"
    
    # 检查HTTP状态码
    if [ "$http_code" = "200" ]; then
        log_debug "HTTP健康检查通过"
        return 0
    else
        log_error "HTTP健康检查失败 (状态码: $http_code)"
        return 1
    fi
}

# 检查应用响应时间
check_response_time() {
    log_debug "检查应用响应时间"
    
    local url="http://$APP_HOST:$APP_PORT$HEALTH_ENDPOINT"
    local start_time
    local end_time
    local response_time
    
    if command_exists curl; then
        start_time=$(date +%s%N)
        
        if curl -s --max-time "$HEALTH_TIMEOUT" \
            --connect-timeout 5 \
            "$url" >/dev/null 2>&1; then
            
            end_time=$(date +%s%N)
            response_time=$(( (end_time - start_time) / 1000000 ))
            
            log_debug "响应时间: ${response_time}ms"
            
            # 如果响应时间超过5秒，发出警告
            if [ "$response_time" -gt 5000 ]; then
                log_warn "响应时间较慢: ${response_time}ms"
            fi
            
            return 0
        else
            log_error "响应时间检查失败"
            return 1
        fi
    else
        log_debug "跳过响应时间检查（curl不可用）"
        return 0
    fi
}

# 检查内存使用情况
check_memory_usage() {
    log_debug "检查内存使用情况"
    
    local memory_info
    local memory_usage
    
    if command_exists ps; then
        # 获取Node.js进程的内存使用情况
        memory_info=$(ps aux | grep "node.*server.js" | grep -v grep | awk '{print $4}' | head -n1)
        
        if [ -n "$memory_info" ]; then
            memory_usage=$(echo "$memory_info" | cut -d. -f1)
            log_debug "内存使用率: ${memory_usage}%"
            
            # 如果内存使用率超过80%，发出警告
            if [ "$memory_usage" -gt 80 ]; then
                log_warn "内存使用率较高: ${memory_usage}%"
            fi
        else
            log_debug "无法获取内存使用信息"
        fi
    fi
    
    return 0
}

# 检查磁盘空间
check_disk_space() {
    log_debug "检查磁盘空间"
    
    local data_path="${DATA_PATH:-/app/data}"
    local disk_usage
    
    if command_exists df; then
        disk_usage=$(df "$data_path" 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//')
        
        if [ -n "$disk_usage" ]; then
            log_debug "磁盘使用率: ${disk_usage}%"
            
            # 如果磁盘使用率超过85%，发出警告
            if [ "$disk_usage" -gt 85 ]; then
                log_warn "磁盘空间不足: ${disk_usage}%"
            fi
        else
            log_debug "无法获取磁盘使用信息"
        fi
    fi
    
    return 0
}

# 检查关键文件
check_critical_files() {
    log_debug "检查关键文件"
    
    local critical_files=(
        "/app/server.js"
        "/app/package.json"
        "${DATA_PATH:-/app/data}"
    )
    
    for file in "${critical_files[@]}"; do
        if [ ! -e "$file" ]; then
            log_error "关键文件不存在: $file"
            return 1
        fi
    done
    
    log_debug "关键文件检查通过"
    return 0
}

# 检查数据库连接（如果启用）
check_database_connection() {
    local db_type="${DB_TYPE:-file}"
    
    if [ "$db_type" = "postgresql" ]; then
        log_debug "检查PostgreSQL数据库连接"
        
        local db_host="${DB_HOST:-localhost}"
        local db_port="${DB_PORT:-5432}"
        
        if command_exists nc; then
            if nc -z "$db_host" "$db_port" 2>/dev/null; then
                log_debug "PostgreSQL数据库连接正常"
                return 0
            else
                log_error "无法连接到PostgreSQL数据库"
                return 1
            fi
        fi
    fi
    
    return 0
}

# 检查Redis连接（如果启用）
check_redis_connection() {
    local redis_enabled="${REDIS_ENABLED:-false}"
    
    if [ "$redis_enabled" = "true" ]; then
        log_debug "检查Redis连接"
        
        local redis_host="${REDIS_HOST:-localhost}"
        local redis_port="${REDIS_PORT:-6379}"
        
        if command_exists nc; then
            if nc -z "$redis_host" "$redis_port" 2>/dev/null; then
                log_debug "Redis连接正常"
                return 0
            else
                log_warn "无法连接到Redis"
                # Redis连接失败不应该导致健康检查失败
                return 0
            fi
        fi
    fi
    
    return 0
}

# ============================================================================
# 主健康检查函数
# ============================================================================

# 执行所有健康检查
perform_health_checks() {
    local checks_passed=0
    local total_checks=0
    
    # 基础检查（必须通过）
    local critical_checks=(
        "check_process"
        "check_port"
        "check_http_health"
        "check_critical_files"
    )
    
    # 可选检查（失败不影响整体结果）
    local optional_checks=(
        "check_response_time"
        "check_memory_usage"
        "check_disk_space"
        "check_database_connection"
        "check_redis_connection"
    )
    
    log_info "开始健康检查"
    
    # 执行关键检查
    for check in "${critical_checks[@]}"; do
        total_checks=$((total_checks + 1))
        
        if $check; then
            checks_passed=$((checks_passed + 1))
        else
            log_error "关键检查失败: $check"
            return 1
        fi
    done
    
    # 执行可选检查
    for check in "${optional_checks[@]}"; do
        total_checks=$((total_checks + 1))
        
        if $check; then
            checks_passed=$((checks_passed + 1))
        else
            log_warn "可选检查失败: $check"
        fi
    done
    
    log_info "健康检查完成: $checks_passed/$total_checks 项通过"
    
    # 只要关键检查都通过，就认为健康
    return 0
}

# 带重试的健康检查
health_check_with_retry() {
    local attempt=1
    
    while [ $attempt -le $MAX_RETRIES ]; do
        log_debug "健康检查尝试 $attempt/$MAX_RETRIES"
        
        if perform_health_checks; then
            log_info "健康检查通过"
            return 0
        else
            if [ $attempt -lt $MAX_RETRIES ]; then
                log_warn "健康检查失败，${RETRY_INTERVAL}秒后重试..."
                sleep $RETRY_INTERVAL
            else
                log_error "健康检查失败，已达到最大重试次数"
                return 1
            fi
        fi
        
        attempt=$((attempt + 1))
    done
    
    return 1
}

# ============================================================================
# 主函数
# ============================================================================

main() {
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --quiet)
                QUIET_MODE="true"
                shift
                ;;
            --debug)
                LOG_LEVEL="debug"
                shift
                ;;
            --timeout)
                HEALTH_TIMEOUT="$2"
                shift 2
                ;;
            --retries)
                MAX_RETRIES="$2"
                shift 2
                ;;
            --help)
                echo "用法: $0 [选项]"
                echo "选项:"
                echo "  --quiet     静默模式"
                echo "  --debug     调试模式"
                echo "  --timeout   HTTP超时时间（秒）"
                echo "  --retries   最大重试次数"
                echo "  --help      显示帮助信息"
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                exit 1
                ;;
        esac
    done
    
    # 执行健康检查
    if health_check_with_retry; then
        exit 0
    else
        exit 1
    fi
}

# ============================================================================
# 脚本入口
# ============================================================================

# 如果脚本被直接执行
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi