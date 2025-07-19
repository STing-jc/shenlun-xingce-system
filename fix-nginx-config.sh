#!/bin/bash

# 修复Nginx配置脚本
# 解决"getpwnam(\"nginx\") failed"错误

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# 检测操作系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    elif [ -f /etc/redhat-release ]; then
        DISTRO="centos"
    else
        log_error "无法检测操作系统"
        exit 1
    fi
    
    log_info "检测到操作系统: $DISTRO"
}

# 修复Nginx用户配置
fix_nginx_user() {
    log_info "修复Nginx用户配置..."
    
    local nginx_conf="/etc/nginx/nginx.conf"
    
    if [ ! -f "$nginx_conf" ]; then
        log_error "Nginx配置文件不存在: $nginx_conf"
        return 1
    fi
    
    # 备份原配置
    cp "$nginx_conf" "${nginx_conf}.backup.$(date +%Y%m%d_%H%M%S)"
    log_info "已备份原配置文件"
    
    # 根据操作系统设置正确的用户
    if [ "$DISTRO" = "ubuntu" ] || [ "$DISTRO" = "debian" ]; then
        # Ubuntu/Debian使用www-data用户
        sed -i 's/user nginx;/user www-data;/g' "$nginx_conf"
        log_info "已将Nginx用户设置为: www-data"
    elif [ "$DISTRO" = "centos" ] || [ "$DISTRO" = "rhel" ] || [ "$DISTRO" = "fedora" ]; then
        # CentOS/RHEL/Fedora使用nginx用户
        if ! id nginx >/dev/null 2>&1; then
            # 如果nginx用户不存在，创建它
            useradd -r -d /var/cache/nginx -s /sbin/nologin nginx
            log_info "已创建nginx用户"
        fi
        log_info "已确认Nginx用户设置为: nginx"
    else
        log_warn "未知的操作系统，使用默认配置"
    fi
}

# 测试Nginx配置
test_nginx_config() {
    log_info "测试Nginx配置..."
    
    if nginx -t; then
        log_success "Nginx配置测试通过"
        return 0
    else
        log_error "Nginx配置测试失败"
        return 1
    fi
}

# 重启Nginx服务
restart_nginx() {
    log_info "重启Nginx服务..."
    
    if systemctl restart nginx; then
        log_success "Nginx服务重启成功"
    else
        log_error "Nginx服务重启失败"
        return 1
    fi
    
    # 检查服务状态
    if systemctl is-active nginx >/dev/null; then
        log_success "Nginx服务运行正常"
    else
        log_error "Nginx服务未正常运行"
        systemctl status nginx
        return 1
    fi
}

# 显示解决方案
show_solution() {
    echo
    log_info "=== Nginx配置修复解决方案 ==="
    echo
    log_info "问题原因:"
    echo "  - Docker配置文件中使用了'user nginx;'"
    echo "  - 但Ubuntu系统中Nginx的默认用户是'www-data'"
    echo "  - 导致配置测试失败"
    echo
    log_info "解决方案:"
    echo "  1. 修改/etc/nginx/nginx.conf中的用户配置"
    echo "  2. Ubuntu/Debian: user www-data;"
    echo "  3. CentOS/RHEL: user nginx;"
    echo
    log_info "预防措施:"
    echo "  - 已更新auto-deploy.sh脚本，自动处理用户配置"
    echo "  - 未来部署将自动适配操作系统"
    echo
}

# 主函数
main() {
    echo "=== Nginx配置修复脚本 ==="
    echo
    
    # 环境检查
    check_root
    detect_os
    
    # 显示解决方案
    show_solution
    
    # 修复配置
    if fix_nginx_user; then
        log_success "用户配置修复完成"
    else
        log_error "用户配置修复失败"
        exit 1
    fi
    
    # 测试配置
    if test_nginx_config; then
        log_success "配置测试通过"
    else
        log_error "配置测试失败，请检查配置文件"
        exit 1
    fi
    
    # 重启服务
    if restart_nginx; then
        log_success "Nginx服务重启成功"
    else
        log_error "Nginx服务重启失败"
        exit 1
    fi
    
    echo
    log_success "=== Nginx配置修复完成 ==="
    log_info "现在可以继续部署流程了"
    echo
    log_info "继续部署命令:"
    echo "  cd ~/shenlun-xingce-system"
    echo "  bash scripts/auto-deploy.sh deploy"
    echo
}

# 执行主函数
main "$@"