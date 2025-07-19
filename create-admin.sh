#!/bin/bash

# 创建新管理员账户脚本
# 使用方法: ./create-admin.sh <用户名> <邮箱> <密码>
# 示例: ./create-admin.sh newadmin admin@example.com mypassword123

USERS_FILE="/root/shenlun-xingce-system/data/users.json"
SCRIPT_DIR="/root/shenlun-xingce-system"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}📋 $1${NC}"
}

# 检查依赖
check_dependencies() {
    if ! command -v node &> /dev/null; then
        print_error "Node.js 未安装，请先安装 Node.js"
        exit 1
    fi
    
    if ! command -v npm &> /dev/null; then
        print_error "npm 未安装，请先安装 npm"
        exit 1
    fi
}

# 检查bcryptjs是否安装
check_bcrypt() {
    cd "$SCRIPT_DIR"
    if ! npm list bcryptjs &> /dev/null; then
        print_warning "bcryptjs 未安装，正在安装..."
        npm install bcryptjs
        if [ $? -ne 0 ]; then
            print_error "bcryptjs 安装失败"
            exit 1
        fi
        print_success "bcryptjs 安装完成"
    fi
}

# 验证邮箱格式
validate_email() {
    local email=$1
    if [[ ! $email =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

# 创建管理员账户
create_admin() {
    local username=$1
    local email=$2
    local password=$3
    
    # 验证输入
    if [ -z "$username" ] || [ -z "$email" ] || [ -z "$password" ]; then
        print_error "用户名、邮箱和密码都是必填项"
        exit 1
    fi
    
    if [ ${#password} -lt 6 ]; then
        print_error "密码长度至少6位"
        exit 1
    fi
    
    if ! validate_email "$email"; then
        print_error "邮箱格式不正确"
        exit 1
    fi
    
    # 确保数据目录存在
    mkdir -p "$(dirname "$USERS_FILE")"
    
    # 如果用户文件不存在，创建空数组
    if [ ! -f "$USERS_FILE" ]; then
        echo '[]' > "$USERS_FILE"
    fi
    
    # 检查用户名和邮箱是否已存在
    if grep -q "\"username\": \"$username\"" "$USERS_FILE" 2>/dev/null; then
        print_error "用户名 '$username' 已存在"
        exit 1
    fi
    
    if grep -q "\"email\": \"$email\"" "$USERS_FILE" 2>/dev/null; then
        print_error "邮箱 '$email' 已存在"
        exit 1
    fi
    
    # 使用Node.js生成加密密码
    cd "$SCRIPT_DIR"
    local hashed_password=$(node -e "
        const bcrypt = require('bcryptjs');
        const password = '$password';
        const hash = bcrypt.hashSync(password, 10);
        console.log(hash);
    ")
    
    if [ $? -ne 0 ]; then
        print_error "密码加密失败"
        exit 1
    fi
    
    # 生成用户ID和时间戳
    local user_id="admin_$(date +%s)000"
    local created_at=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
    
    # 创建新用户JSON
    local new_user=$(cat <<EOF
{
  "id": "$user_id",
  "username": "$username",
  "email": "$email",
  "password": "$hashed_password",
  "role": "admin",
  "createdAt": "$created_at",
  "lastLogin": null,
  "isActive": true
}
EOF
)
    
    # 读取现有用户数据
    local existing_users=$(cat "$USERS_FILE")
    
    # 如果是空数组，直接添加
    if [ "$existing_users" = "[]" ]; then
        echo "[$new_user]" > "$USERS_FILE"
    else
        # 移除最后的 ] 并添加新用户
        echo "$existing_users" | sed 's/]$//' > "$USERS_FILE.tmp"
        echo "," >> "$USERS_FILE.tmp"
        echo "$new_user" >> "$USERS_FILE.tmp"
        echo "]" >> "$USERS_FILE.tmp"
        mv "$USERS_FILE.tmp" "$USERS_FILE"
    fi
    
    # 格式化JSON文件
    if command -v jq &> /dev/null; then
        jq '.' "$USERS_FILE" > "$USERS_FILE.tmp" && mv "$USERS_FILE.tmp" "$USERS_FILE"
    fi
    
    print_success "管理员账户创建成功！"
    print_info "账户信息:"
    echo "   用户名: $username"
    echo "   邮箱: $email"
    echo "   角色: 管理员"
    echo "   创建时间: $created_at"
    echo "   账户ID: $user_id"
    echo ""
    print_info "现在可以使用以下信息登录:"
    echo "   用户名: $username"
    echo "   密码: $password"
    echo ""
    print_warning "请妥善保管登录信息！"
}

# 列出所有用户
list_users() {
    if [ ! -f "$USERS_FILE" ]; then
        print_warning "用户文件不存在"
        return
    fi
    
    print_info "当前用户列表:"
    echo "================================================================================"
    
    # 使用jq解析JSON（如果可用）
    if command -v jq &> /dev/null; then
        local count=1
        jq -r '.[] | "\(.username)\t\(.email)\t\(.role)\t\(.isActive)\t\(.createdAt)\t\(.lastLogin // "从未登录")"' "$USERS_FILE" | while IFS=$'\t' read -r username email role isActive createdAt lastLogin; do
            echo "$count. $username"
            echo "   邮箱: $email"
            echo "   角色: $([ "$role" = "admin" ] && echo "管理员" || echo "普通用户")"
            echo "   状态: $([ "$isActive" = "true" ] && echo "激活" || echo "禁用")"
            echo "   创建时间: $createdAt"
            echo "   最后登录: $lastLogin"
            echo "----------------------------------------"
            ((count++))
        done
    else
        # 简单的grep方式
        grep -o '"username": "[^"]*"' "$USERS_FILE" | sed 's/"username": "\(.*\)"/\1/' | nl
    fi
}

# 显示帮助信息
show_help() {
    echo "🔧 创建管理员账户工具"
    echo ""
    echo "使用方法:"
    echo "  ./create-admin.sh <用户名> <邮箱> <密码>     # 创建新管理员"
    echo "  ./create-admin.sh --list                    # 列出所有用户"
    echo "  ./create-admin.sh --help                    # 显示帮助"
    echo ""
    echo "示例:"
    echo "  ./create-admin.sh newadmin admin@example.com mypassword123"
    echo "  ./create-admin.sh --list"
    echo ""
    echo "注意事项:"
    echo "  - 密码长度至少6位"
    echo "  - 邮箱格式必须正确"
    echo "  - 用户名和邮箱不能重复"
    echo "  - 需要在项目根目录下运行"
}

# 主函数
main() {
    # 检查参数
    if [ $# -eq 0 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        show_help
        exit 0
    fi
    
    if [ "$1" = "--list" ] || [ "$1" = "-l" ]; then
        list_users
        exit 0
    fi
    
    if [ $# -ne 3 ]; then
        print_error "参数错误！需要提供用户名、邮箱和密码"
        echo "使用 ./create-admin.sh --help 查看帮助"
        exit 1
    fi
    
    # 检查依赖
    check_dependencies
    check_bcrypt
    
    # 创建管理员
    create_admin "$1" "$2" "$3"
}

# 运行主函数
main "$@"