#!/bin/bash

# 推送项目到GitHub脚本
# 用于将本地申论行测学习系统项目推送到GitHub仓库

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
GITHUB_REPO="https://github.com/STing-jc/shenlun-xingce-system.git"
PROJECT_DIR="$(pwd)"
BRANCH_NAME="main"

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

# 检查Git是否安装
check_git() {
    if ! command -v git >/dev/null 2>&1; then
        log_error "Git未安装，请先安装Git"
        exit 1
    fi
    log_info "Git版本: $(git --version)"
}

# 检查Git配置
check_git_config() {
    local user_name=$(git config --global user.name 2>/dev/null || echo "")
    local user_email=$(git config --global user.email 2>/dev/null || echo "")
    
    if [ -z "$user_name" ] || [ -z "$user_email" ]; then
        log_warn "Git用户信息未配置"
        echo
        read -p "请输入您的Git用户名: " input_name
        read -p "请输入您的Git邮箱: " input_email
        
        git config --global user.name "$input_name"
        git config --global user.email "$input_email"
        
        log_success "Git用户信息配置完成"
    else
        log_info "Git用户: $user_name <$user_email>"
    fi
}

# 初始化Git仓库
init_git_repo() {
    if [ ! -d ".git" ]; then
        log_info "初始化Git仓库..."
        git init
        log_success "Git仓库初始化完成"
    else
        log_info "Git仓库已存在"
    fi
}

# 创建或更新.gitignore文件
create_gitignore() {
    log_info "创建.gitignore文件..."
    
    cat > .gitignore << 'EOF'
# 依赖目录
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# 环境变量文件
.env
.env.local
.env.development.local
.env.test.local
.env.production.local

# 日志文件
logs/
*.log

# 运行时文件
pids/
*.pid
*.seed
*.pid.lock

# 构建输出
dist/
build/

# 临时文件
tmp/
temp/

# 操作系统文件
.DS_Store
Thumbs.db

# IDE文件
.vscode/
.idea/
*.swp
*.swo

# 备份文件
*.backup
*.bak

# 数据库文件
*.sqlite
*.db

# SSL证书
*.pem
*.key
*.crt

# 压缩文件
*.zip
*.tar.gz
*.rar

# 测试覆盖率
coverage/
.nyc_output/

# 缓存目录
.cache/
.parcel-cache/

# 依赖锁定文件（可选）
# package-lock.json
# yarn.lock
EOF
    
    log_success ".gitignore文件创建完成"
}

# 添加远程仓库
add_remote_origin() {
    log_info "配置远程仓库..."
    
    # 检查是否已有远程仓库
    if git remote get-url origin >/dev/null 2>&1; then
        local current_url=$(git remote get-url origin)
        if [ "$current_url" != "$GITHUB_REPO" ]; then
            log_warn "远程仓库URL不匹配，正在更新..."
            git remote set-url origin "$GITHUB_REPO"
        else
            log_info "远程仓库已正确配置"
        fi
    else
        git remote add origin "$GITHUB_REPO"
        log_success "远程仓库添加完成"
    fi
    
    # 验证远程仓库
    git remote -v
}

# 添加文件到暂存区
add_files() {
    log_info "添加文件到暂存区..."
    
    # 显示当前状态
    echo "当前文件状态:"
    git status --short
    echo
    
    # 添加所有文件
    git add .
    
    # 显示暂存状态
    echo "暂存区状态:"
    git status --short
    
    log_success "文件添加完成"
}

# 提交更改
commit_changes() {
    log_info "提交更改..."
    
    # 检查是否有文件需要提交
    if git diff --cached --quiet; then
        log_warn "没有文件需要提交"
        return 0
    fi
    
    # 默认提交信息
    local default_message="初始提交：申论行测学习系统完整版本

包含功能:
- 完整的学习系统前端界面
- Node.js后端服务
- 数据库配置和脚本
- Docker容器化配置
- 自动化部署脚本
- 监控和安全配置
- 完整的文档和指南

版本: v1.0.0
日期: $(date '+%Y-%m-%d %H:%M:%S')"
    
    echo
    echo "请输入提交信息（留空使用默认信息）:"
    echo "默认信息: 初始提交：申论行测学习系统完整版本"
    read -p "提交信息: " commit_message
    
    if [ -z "$commit_message" ]; then
        commit_message="$default_message"
    fi
    
    git commit -m "$commit_message"
    log_success "提交完成"
}

# 推送到GitHub
push_to_github() {
    log_info "推送到GitHub..."
    
    # 设置主分支
    git branch -M "$BRANCH_NAME"
    
    # 首次推送
    echo "正在推送到 $GITHUB_REPO ..."
    echo "如果需要认证，请输入您的GitHub用户名和Personal Access Token"
    echo
    
    if git push -u origin "$BRANCH_NAME"; then
        log_success "推送成功！"
        echo
        log_info "项目已成功推送到: $GITHUB_REPO"
        log_info "您可以在浏览器中访问查看项目"
    else
        log_error "推送失败"
        echo
        log_info "可能的解决方案:"
        echo "1. 检查网络连接"
        echo "2. 确认GitHub用户名和密码/Token正确"
        echo "3. 确认仓库权限"
        echo "4. 如果仓库已存在内容，尝试先拉取: git pull origin main --allow-unrelated-histories"
        return 1
    fi
}

# 验证推送结果
verify_push() {
    log_info "验证推送结果..."
    
    # 检查远程分支
    if git ls-remote --heads origin "$BRANCH_NAME" >/dev/null 2>&1; then
        log_success "远程分支验证成功"
    else
        log_error "远程分支验证失败"
        return 1
    fi
    
    # 显示最新提交
    echo
    echo "最新提交信息:"
    git log --oneline -5
}

# 显示后续操作指南
show_next_steps() {
    echo
    log_success "=== 推送完成 ==="
    echo
    log_info "项目地址: $GITHUB_REPO"
    echo
    log_info "后续操作:"
    echo "1. 在浏览器中访问GitHub仓库查看项目"
    echo "2. 在服务器上使用以下命令拉取项目:"
    echo "   git clone $GITHUB_REPO"
    echo "   cd shenlun-xingce-system"
    echo "   bash quick-deploy-from-github.sh deploy"
    echo
    log_info "日常开发流程:"
    echo "1. 修改代码后提交: git add . && git commit -m \"更新说明\""
    echo "2. 推送到GitHub: git push origin main"
    echo "3. 服务器更新: bash quick-deploy-from-github.sh update"
    echo
    log_info "如需帮助，请查看 Git操作指南.md"
    echo
}

# 处理推送错误
handle_push_error() {
    log_warn "检测到推送可能失败，尝试解决..."
    
    echo
    echo "选择解决方案:"
    echo "1. 强制推送（覆盖远程仓库）"
    echo "2. 先拉取远程内容再推送"
    echo "3. 退出并手动处理"
    read -p "请选择 (1-3): " choice
    
    case "$choice" in
        1)
            log_warn "执行强制推送..."
            if git push --force origin "$BRANCH_NAME"; then
                log_success "强制推送成功"
                return 0
            else
                log_error "强制推送失败"
                return 1
            fi
            ;;
        2)
            log_info "拉取远程内容..."
            if git pull origin "$BRANCH_NAME" --allow-unrelated-histories; then
                log_info "重新推送..."
                if git push origin "$BRANCH_NAME"; then
                    log_success "推送成功"
                    return 0
                else
                    log_error "推送失败"
                    return 1
                fi
            else
                log_error "拉取失败"
                return 1
            fi
            ;;
        3)
            log_info "退出脚本，请手动处理"
            exit 0
            ;;
        *)
            log_error "无效选择"
            return 1
            ;;
    esac
}

# 主函数
main() {
    echo "=== 推送申论行测学习系统到GitHub ==="
    echo "目标仓库: $GITHUB_REPO"
    echo "当前目录: $PROJECT_DIR"
    echo
    
    # 环境检查
    check_git
    check_git_config
    
    # Git仓库操作
    init_git_repo
    create_gitignore
    add_remote_origin
    
    # 文件操作
    add_files
    commit_changes
    
    # 推送操作
    if push_to_github; then
        verify_push
        show_next_steps
    else
        if handle_push_error; then
            verify_push
            show_next_steps
        else
            log_error "推送失败，请检查错误信息并手动处理"
            exit 1
        fi
    fi
}

# 执行主函数
main "$@"