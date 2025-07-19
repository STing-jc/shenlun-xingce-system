#!/bin/bash
# 申论行测学习系统 - 备份和恢复脚本
# 版本: v2.0.0
# 描述: 数据备份、恢复和灾难恢复脚本

set -e

# ============================================================================
# 配置变量
# ============================================================================

# 应用配置
APP_NAME="${APP_NAME:-shenlun-xingce-system}"
APP_VERSION="${APP_VERSION:-2.0.0}"
DATA_PATH="${DATA_PATH:-/app/data}"
LOG_PATH="${LOG_PATH:-/app/logs}"
BACKUP_PATH="${BACKUP_PATH:-/app/backups}"

# 备份配置
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
BACKUP_COMPRESSION="${BACKUP_COMPRESSION:-gzip}"
BACKUP_ENCRYPTION="${BACKUP_ENCRYPTION:-false}"
BACKUP_ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY:-}"

# 远程备份配置
REMOTE_BACKUP_ENABLED="${REMOTE_BACKUP_ENABLED:-false}"
REMOTE_BACKUP_TYPE="${REMOTE_BACKUP_TYPE:-s3}"  # s3, ftp, rsync
REMOTE_BACKUP_ENDPOINT="${REMOTE_BACKUP_ENDPOINT:-}"
REMOTE_BACKUP_BUCKET="${REMOTE_BACKUP_BUCKET:-}"
REMOTE_BACKUP_ACCESS_KEY="${REMOTE_BACKUP_ACCESS_KEY:-}"
REMOTE_BACKUP_SECRET_KEY="${REMOTE_BACKUP_SECRET_KEY:-}"

# 数据库配置
DB_TYPE="${DB_TYPE:-file}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-shenlun_system}"
DB_USER="${DB_USER:-app_user}"
DB_PASSWORD="${DB_PASSWORD:-}"

# 通知配置
NOTIFICATION_ENABLED="${NOTIFICATION_ENABLED:-false}"
NOTIFICATION_WEBHOOK="${NOTIFICATION_WEBHOOK:-}"
NOTIFICATION_EMAIL="${NOTIFICATION_EMAIL:-}"

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
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_PATH/backup.log"
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
    
    local required_tools=("tar" "gzip")
    local missing_tools=()
    
    # 根据配置检查额外工具
    if [ "$BACKUP_ENCRYPTION" = "true" ]; then
        required_tools+=("openssl")
    fi
    
    if [ "$REMOTE_BACKUP_ENABLED" = "true" ]; then
        case "$REMOTE_BACKUP_TYPE" in
            "s3")
                required_tools+=("aws")
                ;;
            "ftp")
                required_tools+=("ftp")
                ;;
            "rsync")
                required_tools+=("rsync")
                ;;
        esac
    fi
    
    if [ "$DB_TYPE" = "postgresql" ]; then
        required_tools+=("pg_dump" "psql")
    fi
    
    for tool in "${required_tools[@]}"; do
        if ! command_exists "$tool"; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "缺少必需的工具: ${missing_tools[*]}"
        return 1
    fi
    
    log_success "工具检查通过"
}

# 创建备份目录
create_backup_dirs() {
    log_info "创建备份目录..."
    
    local dirs=(
        "$BACKUP_PATH"
        "$BACKUP_PATH/daily"
        "$BACKUP_PATH/weekly"
        "$BACKUP_PATH/monthly"
        "$BACKUP_PATH/database"
        "$BACKUP_PATH/logs"
        "$BACKUP_PATH/temp"
    )
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            log_info "创建目录: $dir"
        fi
    done
    
    log_success "备份目录创建完成"
}

# 发送通知
send_notification() {
    local title="$1"
    local message="$2"
    local status="$3"  # success, warning, error
    
    if [ "$NOTIFICATION_ENABLED" != "true" ]; then
        return 0
    fi
    
    log_info "发送通知: $title"
    
    # Webhook通知
    if [ -n "$NOTIFICATION_WEBHOOK" ] && command_exists curl; then
        local color
        case "$status" in
            "success") color="#00ff00" ;;
            "warning") color="#ffff00" ;;
            "error") color="#ff0000" ;;
            *) color="#0000ff" ;;
        esac
        
        curl -s -X POST "$NOTIFICATION_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{
                \"embeds\": [{
                    \"title\": \"$title\",
                    \"description\": \"$message\",
                    \"color\": \"$color\",
                    \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",
                    \"footer\": {
                        \"text\": \"$APP_NAME v$APP_VERSION\"
                    }
                }]
            }" >/dev/null 2>&1 || true
    fi
    
    # 邮件通知
    if [ -n "$NOTIFICATION_EMAIL" ] && command_exists mail; then
        echo "$message" | mail -s "[$APP_NAME] $title" "$NOTIFICATION_EMAIL" >/dev/null 2>&1 || true
    fi
}

# ============================================================================
# 备份函数
# ============================================================================

# 备份应用数据
backup_app_data() {
    local backup_type="$1"  # daily, weekly, monthly
    local timestamp=$(date +"%Y%m%d-%H%M%S")
    local backup_file="$BACKUP_PATH/$backup_type/app-data-$timestamp.tar"
    
    log_info "开始备份应用数据 ($backup_type)..."
    
    # 创建临时目录
    local temp_dir="$BACKUP_PATH/temp/app-data-$timestamp"
    mkdir -p "$temp_dir"
    
    # 复制数据文件
    if [ -d "$DATA_PATH" ]; then
        cp -r "$DATA_PATH" "$temp_dir/"
        log_info "已复制数据目录"
    fi
    
    # 复制配置文件
    if [ -f "/app/.env" ]; then
        cp "/app/.env" "$temp_dir/"
        log_info "已复制配置文件"
    fi
    
    # 创建备份信息文件
    cat > "$temp_dir/backup-info.txt" << EOF
备份信息
========
应用名称: $APP_NAME
应用版本: $APP_VERSION
备份类型: $backup_type
备份时间: $(date)
备份主机: $(hostname)
备份用户: $(whoami)
EOF
    
    # 创建tar包
    tar -cf "$backup_file" -C "$temp_dir" . 2>/dev/null
    
    # 压缩备份文件
    if [ "$BACKUP_COMPRESSION" = "gzip" ]; then
        gzip "$backup_file"
        backup_file="$backup_file.gz"
    elif [ "$BACKUP_COMPRESSION" = "bzip2" ] && command_exists bzip2; then
        bzip2 "$backup_file"
        backup_file="$backup_file.bz2"
    fi
    
    # 加密备份文件
    if [ "$BACKUP_ENCRYPTION" = "true" ] && [ -n "$BACKUP_ENCRYPTION_KEY" ]; then
        openssl enc -aes-256-cbc -salt -in "$backup_file" -out "$backup_file.enc" -k "$BACKUP_ENCRYPTION_KEY"
        rm "$backup_file"
        backup_file="$backup_file.enc"
        log_info "备份文件已加密"
    fi
    
    # 清理临时目录
    rm -rf "$temp_dir"
    
    # 计算文件大小和校验和
    local file_size=$(du -h "$backup_file" | cut -f1)
    local file_md5=$(md5sum "$backup_file" | cut -d' ' -f1)
    
    log_success "应用数据备份完成"
    log_info "备份文件: $backup_file"
    log_info "文件大小: $file_size"
    log_info "MD5校验: $file_md5"
    
    # 上传到远程存储
    if [ "$REMOTE_BACKUP_ENABLED" = "true" ]; then
        upload_to_remote "$backup_file" "app-data/$backup_type/"
    fi
    
    echo "$backup_file"
}

# 备份数据库
backup_database() {
    if [ "$DB_TYPE" != "postgresql" ]; then
        log_info "跳过数据库备份（使用文件存储）"
        return 0
    fi
    
    local timestamp=$(date +"%Y%m%d-%H%M%S")
    local backup_file="$BACKUP_PATH/database/db-$timestamp.sql"
    
    log_info "开始备份PostgreSQL数据库..."
    
    # 设置数据库密码
    export PGPASSWORD="$DB_PASSWORD"
    
    # 执行数据库备份
    if pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        --verbose --no-password --format=custom --compress=9 \
        --file="$backup_file" 2>/dev/null; then
        
        log_success "数据库备份完成"
        log_info "备份文件: $backup_file"
        
        # 上传到远程存储
        if [ "$REMOTE_BACKUP_ENABLED" = "true" ]; then
            upload_to_remote "$backup_file" "database/"
        fi
        
        echo "$backup_file"
    else
        log_error "数据库备份失败"
        return 1
    fi
    
    unset PGPASSWORD
}

# 备份日志文件
backup_logs() {
    local timestamp=$(date +"%Y%m%d-%H%M%S")
    local backup_file="$BACKUP_PATH/logs/logs-$timestamp.tar.gz"
    
    log_info "开始备份日志文件..."
    
    if [ -d "$LOG_PATH" ]; then
        tar -czf "$backup_file" -C "$LOG_PATH" . 2>/dev/null
        
        local file_size=$(du -h "$backup_file" | cut -f1)
        
        log_success "日志文件备份完成"
        log_info "备份文件: $backup_file"
        log_info "文件大小: $file_size"
        
        # 上传到远程存储
        if [ "$REMOTE_BACKUP_ENABLED" = "true" ]; then
            upload_to_remote "$backup_file" "logs/"
        fi
        
        echo "$backup_file"
    else
        log_warn "日志目录不存在，跳过日志备份"
    fi
}

# 上传到远程存储
upload_to_remote() {
    local local_file="$1"
    local remote_path="$2"
    
    log_info "上传到远程存储: $remote_path"
    
    case "$REMOTE_BACKUP_TYPE" in
        "s3")
            if aws s3 cp "$local_file" "s3://$REMOTE_BACKUP_BUCKET/$remote_path$(basename "$local_file")" \
                --endpoint-url="$REMOTE_BACKUP_ENDPOINT" >/dev/null 2>&1; then
                log_success "文件已上传到S3"
            else
                log_error "S3上传失败"
                return 1
            fi
            ;;
        "rsync")
            if rsync -avz "$local_file" "$REMOTE_BACKUP_ENDPOINT/$remote_path" >/dev/null 2>&1; then
                log_success "文件已通过rsync上传"
            else
                log_error "rsync上传失败"
                return 1
            fi
            ;;
        *)
            log_warn "不支持的远程备份类型: $REMOTE_BACKUP_TYPE"
            return 1
            ;;
    esac
}

# ============================================================================
# 恢复函数
# ============================================================================

# 恢复应用数据
restore_app_data() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        log_error "备份文件不存在: $backup_file"
        return 1
    fi
    
    log_info "开始恢复应用数据..."
    log_warn "此操作将覆盖现有数据，请确认继续"
    
    # 创建数据备份
    if [ -d "$DATA_PATH" ]; then
        local current_backup="$BACKUP_PATH/temp/current-data-$(date +%Y%m%d-%H%M%S).tar.gz"
        tar -czf "$current_backup" -C "$(dirname "$DATA_PATH")" "$(basename "$DATA_PATH")" 2>/dev/null
        log_info "当前数据已备份到: $current_backup"
    fi
    
    # 创建临时目录
    local temp_dir="$BACKUP_PATH/temp/restore-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$temp_dir"
    
    # 解密备份文件（如果需要）
    local restore_file="$backup_file"
    if [[ "$backup_file" == *.enc ]]; then
        if [ -z "$BACKUP_ENCRYPTION_KEY" ]; then
            log_error "需要加密密钥来解密备份文件"
            return 1
        fi
        
        restore_file="$temp_dir/$(basename "$backup_file" .enc)"
        openssl enc -aes-256-cbc -d -in "$backup_file" -out "$restore_file" -k "$BACKUP_ENCRYPTION_KEY"
        log_info "备份文件已解密"
    fi
    
    # 解压备份文件
    if [[ "$restore_file" == *.gz ]]; then
        gunzip -c "$restore_file" | tar -xf - -C "$temp_dir"
    elif [[ "$restore_file" == *.bz2 ]]; then
        bunzip2 -c "$restore_file" | tar -xf - -C "$temp_dir"
    else
        tar -xf "$restore_file" -C "$temp_dir"
    fi
    
    # 恢复数据目录
    if [ -d "$temp_dir/data" ]; then
        rm -rf "$DATA_PATH"
        mv "$temp_dir/data" "$DATA_PATH"
        log_success "数据目录已恢复"
    fi
    
    # 恢复配置文件
    if [ -f "$temp_dir/.env" ]; then
        cp "$temp_dir/.env" "/app/"
        log_success "配置文件已恢复"
    fi
    
    # 清理临时目录
    rm -rf "$temp_dir"
    
    log_success "应用数据恢复完成"
}

# 恢复数据库
restore_database() {
    local backup_file="$1"
    
    if [ "$DB_TYPE" != "postgresql" ]; then
        log_info "跳过数据库恢复（使用文件存储）"
        return 0
    fi
    
    if [ ! -f "$backup_file" ]; then
        log_error "数据库备份文件不存在: $backup_file"
        return 1
    fi
    
    log_info "开始恢复PostgreSQL数据库..."
    log_warn "此操作将覆盖现有数据库，请确认继续"
    
    # 设置数据库密码
    export PGPASSWORD="$DB_PASSWORD"
    
    # 删除现有数据库（可选）
    # dropdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$DB_NAME" 2>/dev/null || true
    # createdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$DB_NAME" 2>/dev/null || true
    
    # 恢复数据库
    if pg_restore -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        --verbose --clean --if-exists --no-password "$backup_file" 2>/dev/null; then
        
        log_success "数据库恢复完成"
    else
        log_error "数据库恢复失败"
        return 1
    fi
    
    unset PGPASSWORD
}

# ============================================================================
# 清理函数
# ============================================================================

# 清理旧备份
cleanup_old_backups() {
    log_info "清理旧备份文件..."
    
    local backup_types=("daily" "weekly" "monthly" "database" "logs")
    local cleaned_count=0
    
    for backup_type in "${backup_types[@]}"; do
        local backup_dir="$BACKUP_PATH/$backup_type"
        
        if [ -d "$backup_dir" ]; then
            # 删除超过保留期的文件
            local old_files=$(find "$backup_dir" -type f -mtime +"$BACKUP_RETENTION_DAYS" 2>/dev/null || true)
            
            if [ -n "$old_files" ]; then
                echo "$old_files" | while read -r file; do
                    rm -f "$file"
                    cleaned_count=$((cleaned_count + 1))
                    log_info "已删除旧备份: $(basename "$file")"
                done
            fi
        fi
    done
    
    # 清理临时目录
    if [ -d "$BACKUP_PATH/temp" ]; then
        find "$BACKUP_PATH/temp" -type f -mtime +1 -delete 2>/dev/null || true
        find "$BACKUP_PATH/temp" -type d -empty -delete 2>/dev/null || true
    fi
    
    log_success "清理完成，共删除 $cleaned_count 个旧备份文件"
}

# ============================================================================
# 主函数
# ============================================================================

# 执行完整备份
perform_full_backup() {
    local backup_type="${1:-daily}"
    
    log_info "开始执行完整备份 ($backup_type)..."
    
    local start_time=$(date +%s)
    local backup_files=()
    local success=true
    
    # 检查环境
    if ! check_requirements; then
        send_notification "备份失败" "环境检查失败，缺少必需的工具" "error"
        return 1
    fi
    
    # 创建备份目录
    create_backup_dirs
    
    # 备份应用数据
    if app_backup_file=$(backup_app_data "$backup_type"); then
        backup_files+=("$app_backup_file")
    else
        success=false
    fi
    
    # 备份数据库
    if db_backup_file=$(backup_database); then
        [ -n "$db_backup_file" ] && backup_files+=("$db_backup_file")
    else
        success=false
    fi
    
    # 备份日志
    if log_backup_file=$(backup_logs); then
        [ -n "$log_backup_file" ] && backup_files+=("$log_backup_file")
    else
        log_warn "日志备份失败，但不影响整体备份"
    fi
    
    # 清理旧备份
    cleanup_old_backups
    
    # 计算总耗时
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [ "$success" = true ]; then
        log_success "完整备份完成，耗时 ${duration} 秒"
        log_info "备份文件列表:"
        for file in "${backup_files[@]}"; do
            log_info "  - $(basename "$file")"
        done
        
        send_notification "备份成功" "完整备份已完成，共备份 ${#backup_files[@]} 个文件，耗时 ${duration} 秒" "success"
    else
        log_error "备份过程中出现错误"
        send_notification "备份失败" "备份过程中出现错误，请检查日志" "error"
        return 1
    fi
}

# 显示帮助信息
show_help() {
    cat << EOF
申论行测学习系统 - 备份和恢复脚本

用法:
  $0 <命令> [选项]

命令:
  backup [daily|weekly|monthly]  执行备份（默认：daily）
  restore <备份文件>             恢复数据
  restore-db <数据库备份文件>    恢复数据库
  cleanup                        清理旧备份
  list                          列出备份文件
  help                          显示帮助信息

示例:
  $0 backup daily               执行日常备份
  $0 backup weekly              执行周备份
  $0 restore /path/to/backup    恢复数据
  $0 cleanup                    清理旧备份
  $0 list                       列出所有备份

环境变量:
  DATA_PATH                     数据目录路径
  BACKUP_PATH                   备份目录路径
  BACKUP_RETENTION_DAYS         备份保留天数
  REMOTE_BACKUP_ENABLED         是否启用远程备份
  NOTIFICATION_ENABLED          是否启用通知
EOF
}

# 列出备份文件
list_backups() {
    log_info "备份文件列表:"
    
    local backup_types=("daily" "weekly" "monthly" "database" "logs")
    
    for backup_type in "${backup_types[@]}"; do
        local backup_dir="$BACKUP_PATH/$backup_type"
        
        if [ -d "$backup_dir" ] && [ "$(ls -A "$backup_dir" 2>/dev/null)" ]; then
            echo
            echo "$backup_type 备份:"
            ls -lh "$backup_dir" | tail -n +2 | while read -r line; do
                echo "  $line"
            done
        fi
    done
}

# 主函数
main() {
    # 确保日志目录存在
    mkdir -p "$LOG_PATH"
    
    case "${1:-help}" in
        "backup")
            perform_full_backup "${2:-daily}"
            ;;
        "restore")
            if [ -z "$2" ]; then
                log_error "请指定备份文件路径"
                exit 1
            fi
            restore_app_data "$2"
            ;;
        "restore-db")
            if [ -z "$2" ]; then
                log_error "请指定数据库备份文件路径"
                exit 1
            fi
            restore_database "$2"
            ;;
        "cleanup")
            cleanup_old_backups
            ;;
        "list")
            list_backups
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