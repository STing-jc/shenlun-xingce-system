#!/bin/bash

# 从GitHub快速部署脚本
# 用于在服务器上快速拉取和部署申论行测学习系统

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
GITHUB_REPO="https://github.com/STing-jc/shenlun-xingce-system.git"
PROJECT_NAME="shenlun-xingce-system"
DEPLOY_DIR="/root"
APP_PORT="3000"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用root用户运行此脚本"
        exit 1
    fi
}

# 检查Git是否安装
check_git() {
    if ! command -v git >/dev/null 2>&1; then
        log_info "Git未安装，正在安装..."
        apt update
        apt install git -y
        log_success "Git安装完成"
    else
        log_info "Git已安装: $(git --version)"
    fi
}

# 克隆或更新项目
clone_or_update_project() {
    cd "$DEPLOY_DIR"
    
    if [ -d "$PROJECT_NAME" ]; then
        log_info "项目目录已存在，更新代码..."
        cd "$PROJECT_NAME"
        
        # 停止应用避免文件占用
        if command -v pm2 >/dev/null 2>&1; then
            pm2 stop all || true
        fi
        
        # 备份本地更改
        if [ -n "$(git status --porcelain)" ]; then
            log_warn "检测到本地更改，正在备份..."
            git stash push -m "自动备份 $(date '+%Y-%m-%d %H:%M:%S')"
        fi
        
        # 拉取最新代码
        git fetch origin
        git reset --hard origin/main
        log_success "代码更新完成"
    else
        log_info "克隆项目..."
        git clone "$GITHUB_REPO" "$PROJECT_NAME"
        cd "$PROJECT_NAME"
        log_success "项目克隆完成"
    fi
}

# 安装依赖
install_dependencies() {
    log_info "安装项目依赖..."
    
    # 检查Node.js
    if ! command -v node >/dev/null 2>&1; then
        log_info "Node.js未安装，正在安装..."
        curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
        apt-get install -y nodejs
        log_success "Node.js安装完成"
    fi
    
    # 安装npm依赖
    if [ -f "package.json" ]; then
        npm install --production
        log_success "依赖安装完成"
    else
        log_warn "未找到package.json文件"
    fi
}

# 配置环境
configure_environment() {
    log_info "配置环境..."
    
    # 创建.env文件（如果不存在）
    if [ ! -f ".env" ]; then
        cat > .env << EOF
# 应用配置
NODE_ENV=production
PORT=$APP_PORT
APP_NAME=申论行测学习系统

# 数据库配置
DB_TYPE=postgresql
DB_HOST=localhost
DB_PORT=5432
DB_NAME=shenlun_xingce
DB_USER=postgres
DB_PASSWORD=your_password_here

# Redis配置
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=

# 安全配置
JWT_SECRET=$(openssl rand -base64 32)
SESSION_SECRET=$(openssl rand -base64 32)

# 日志配置
LOG_LEVEL=info
LOG_PATH=./logs
EOF
        log_success "环境配置文件已创建"
        log_warn "请根据实际情况修改.env文件中的配置"
    else
        log_info "环境配置文件已存在"
    fi
    
    # 创建必要目录
    mkdir -p logs data uploads
    chmod 755 logs data uploads
}

# 构建项目（如果需要）
build_project() {
    if [ -f "package.json" ] && grep -q '"build"' package.json; then
        log_info "构建项目..."
        npm run build
        log_success "项目构建完成"
    else
        log_info "无需构建，跳过构建步骤"
    fi
}

# 安装PM2（如果未安装）
install_pm2() {
    if ! command -v pm2 >/dev/null 2>&1; then
        log_info "安装PM2..."
        npm install -g pm2
        log_success "PM2安装完成"
    else
        log_info "PM2已安装: $(pm2 --version)"
    fi
}

# 启动应用
start_application() {
    log_info "启动应用..."
    
    # 检查PM2配置文件
    if [ -f "ecosystem.config.js" ]; then
        pm2 start ecosystem.config.js
    elif [ -f "server.js" ]; then
        pm2 start server.js --name "$PROJECT_NAME"
    elif [ -f "app.js" ]; then
        pm2 start app.js --name "$PROJECT_NAME"
    else
        log_error "未找到应用入口文件"
        return 1
    fi
    
    # 保存PM2配置
    pm2 save
    
    # 设置开机启动
    pm2 startup
    
    log_success "应用启动完成"
}

# 验证部署
verify_deployment() {
    log_info "验证部署..."
    
    # 等待应用启动
    sleep 5
    
    # 检查PM2进程
    if pm2 list | grep -q "online"; then
        log_success "PM2进程运行正常"
    else
        log_error "PM2进程异常"
        pm2 logs --lines 10
        return 1
    fi
    
    # 检查端口监听
    if netstat -tln | grep -q ":$APP_PORT "; then
        log_success "应用端口监听正常"
    else
        log_error "应用端口未监听"
        return 1
    fi
    
    # 测试HTTP响应
    if command -v curl >/dev/null 2>&1; then
        local http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$APP_PORT" || echo "000")
        if [ "$http_code" = "200" ] || [ "$http_code" = "302" ]; then
            log_success "HTTP响应正常 ($http_code)"
        else
            log_warn "HTTP响应异常 ($http_code)"
        fi
    fi
    
    log_success "部署验证完成"
}

# 显示部署信息
show_deployment_info() {
    echo
    log_success "=== 部署完成 ==="
    echo
    log_info "项目目录: $DEPLOY_DIR/$PROJECT_NAME"
    log_info "应用端口: $APP_PORT"
    log_info "访问地址: http://$(curl -s ifconfig.me):$APP_PORT"
    echo
    log_info "常用命令:"
    echo "  查看应用状态: pm2 list"
    echo "  查看应用日志: pm2 logs"
    echo "  重启应用: pm2 restart all"
    echo "  停止应用: pm2 stop all"
    echo "  更新代码: cd $DEPLOY_DIR/$PROJECT_NAME && git pull"
    echo
    log_info "如需完整部署（包含Nginx、数据库等），请运行:"
    echo "  bash scripts/auto-deploy.sh deploy"
    echo
}

# 显示帮助信息
show_help() {
    echo "从GitHub快速部署脚本"
    echo
    echo "用法: $0 [选项]"
    echo
    echo "选项:"
    echo "  deploy    执行完整部署（默认）"
    echo "  update    仅更新代码"
    echo "  restart   重启应用"
    echo "  status    查看状态"
    echo "  logs      查看日志"
    echo "  help      显示帮助"
    echo
    echo "示例:"
    echo "  $0 deploy   # 完整部署"
    echo "  $0 update   # 仅更新代码"
    echo "  $0 restart  # 重启应用"
    echo
}

# 仅更新代码
update_only() {
    log_info "仅更新代码..."
    check_git
    clone_or_update_project
    install_dependencies
    build_project
    
    if command -v pm2 >/dev/null 2>&1; then
        pm2 restart all
        log_success "应用已重启"
    fi
    
    log_success "代码更新完成"
}

# 重启应用
restart_app() {
    if command -v pm2 >/dev/null 2>&1; then
        log_info "重启应用..."
        pm2 restart all
        log_success "应用重启完成"
    else
        log_error "PM2未安装"
        exit 1
    fi
}

# 查看状态
show_status() {
    if command -v pm2 >/dev/null 2>&1; then
        echo "=== PM2进程状态 ==="
        pm2 list
        echo
        echo "=== 端口监听状态 ==="
        netstat -tln | grep ":$APP_PORT "
        echo
        echo "=== 系统资源使用 ==="
        free -h
        df -h
    else
        log_error "PM2未安装"
        exit 1
    fi
}

# 查看日志
show_logs() {
    if command -v pm2 >/dev/null 2>&1; then
        pm2 logs --lines 50
    else
        log_error "PM2未安装"
        exit 1
    fi
}

# 主函数
main() {
    local action="${1:-deploy}"
    
    case "$action" in
        "deploy")
            echo "=== 从GitHub快速部署申论行测学习系统 ==="
            echo
            check_root
            check_git
            clone_or_update_project
            install_dependencies
            configure_environment
            build_project
            install_pm2
            start_application
            verify_deployment
            show_deployment_info
            ;;
        "update")
            update_only
            ;;
        "restart")
            restart_app
            ;;
        "status")
            show_status
            ;;
        "logs")
            show_logs
            ;;
        "help")
            show_help
            ;;
        *)
            log_error "未知选项: $action"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"