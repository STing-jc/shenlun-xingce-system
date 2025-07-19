#!/bin/bash

# 申论行测学习系统部署检查脚本

set -e

echo "=== 申论行测学习系统部署检查 ==="
echo "正在检查部署状态..."
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查函数
check_service() {
    local service_name=$1
    local description=$2
    
    if systemctl is-active --quiet $service_name; then
        echo -e "${GREEN}✓${NC} $description: 运行中"
        return 0
    else
        echo -e "${RED}✗${NC} $description: 未运行"
        return 1
    fi
}

check_port() {
    local port=$1
    local description=$2
    
    if netstat -tlnp | grep -q ":$port "; then
        echo -e "${GREEN}✓${NC} $description (端口 $port): 正常监听"
        return 0
    else
        echo -e "${RED}✗${NC} $description (端口 $port): 未监听"
        return 1
    fi
}

check_url() {
    local url=$1
    local description=$2
    
    if curl -s -o /dev/null -w "%{http_code}" $url | grep -q "200\|301\|302"; then
        echo -e "${GREEN}✓${NC} $description: 可访问"
        return 0
    else
        echo -e "${RED}✗${NC} $description: 无法访问"
        return 1
    fi
}

# 系统信息
echo -e "${BLUE}=== 系统信息 ===${NC}"
echo "操作系统: $(lsb_release -d 2>/dev/null | cut -f2 || echo '未知')"
echo "内核版本: $(uname -r)"
echo "CPU核心数: $(nproc)"
echo "内存使用: $(free -h | awk '/^Mem:/ {print $3"/"$2}')"
echo "磁盘使用: $(df -h / | awk 'NR==2 {print $3"/"$2" ("$5")')"
echo ""

# 检查必要软件
echo -e "${BLUE}=== 软件检查 ===${NC}"
if command -v node &> /dev/null; then
    echo -e "${GREEN}✓${NC} Node.js: $(node --version)"
else
    echo -e "${RED}✗${NC} Node.js: 未安装"
fi

if command -v npm &> /dev/null; then
    echo -e "${GREEN}✓${NC} NPM: $(npm --version)"
else
    echo -e "${RED}✗${NC} NPM: 未安装"
fi

if command -v nginx &> /dev/null; then
    echo -e "${GREEN}✓${NC} Nginx: $(nginx -v 2>&1 | cut -d' ' -f3)"
else
    echo -e "${RED}✗${NC} Nginx: 未安装"
fi

if command -v docker &> /dev/null; then
    echo -e "${GREEN}✓${NC} Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"
else
    echo -e "${YELLOW}!${NC} Docker: 未安装 (可选)"
fi
echo ""

# 检查服务状态
echo -e "${BLUE}=== 服务状态 ===${NC}"
check_service "study-system" "申论行测学习系统"
check_service "nginx" "Nginx服务"
echo ""

# 检查端口
echo -e "${BLUE}=== 端口检查 ===${NC}"
check_port "3000" "应用服务"
check_port "80" "HTTP服务"
if netstat -tlnp | grep -q ":443 "; then
    check_port "443" "HTTPS服务"
else
    echo -e "${YELLOW}!${NC} HTTPS服务 (端口 443): 未配置 (可选)"
fi
echo ""

# 检查应用文件
echo -e "${BLUE}=== 文件检查 ===${NC}"
APP_DIR="/var/www/study-system"
if [ -d "$APP_DIR" ]; then
    echo -e "${GREEN}✓${NC} 应用目录: $APP_DIR"
    
    if [ -f "$APP_DIR/server.js" ]; then
        echo -e "${GREEN}✓${NC} 服务器文件: server.js"
    else
        echo -e "${RED}✗${NC} 服务器文件: server.js 不存在"
    fi
    
    if [ -f "$APP_DIR/package.json" ]; then
        echo -e "${GREEN}✓${NC} 配置文件: package.json"
    else
        echo -e "${RED}✗${NC} 配置文件: package.json 不存在"
    fi
    
    if [ -d "$APP_DIR/node_modules" ]; then
        echo -e "${GREEN}✓${NC} 依赖模块: node_modules"
    else
        echo -e "${RED}✗${NC} 依赖模块: node_modules 不存在"
    fi
else
    echo -e "${RED}✗${NC} 应用目录: $APP_DIR 不存在"
fi
echo ""

# 检查网络访问
echo -e "${BLUE}=== 网络访问检查 ===${NC}"
check_url "http://localhost" "本地HTTP访问"
check_url "http://localhost:3000" "应用直接访问"

# 获取外网IP并检查
EXTERNAL_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo "无法获取")
if [ "$EXTERNAL_IP" != "无法获取" ]; then
    echo "外网IP: $EXTERNAL_IP"
    check_url "http://$EXTERNAL_IP" "外网HTTP访问"
else
    echo -e "${YELLOW}!${NC} 无法获取外网IP地址"
fi
echo ""

# 检查日志
echo -e "${BLUE}=== 最近日志 ===${NC}"
echo "应用日志 (最近5条):"
journalctl -u study-system -n 5 --no-pager 2>/dev/null || echo "无法获取应用日志"
echo ""
echo "Nginx错误日志 (最近3条):"
tail -n 3 /var/log/nginx/error.log 2>/dev/null || echo "无法获取Nginx错误日志"
echo ""

# 防火墙检查
echo -e "${BLUE}=== 防火墙检查 ===${NC}"
if command -v ufw &> /dev/null; then
    if ufw status | grep -q "Status: active"; then
        echo -e "${GREEN}✓${NC} UFW防火墙: 已启用"
        echo "开放端口:"
        ufw status | grep ALLOW | head -5
    else
        echo -e "${YELLOW}!${NC} UFW防火墙: 未启用"
    fi
elif command -v firewall-cmd &> /dev/null; then
    if firewall-cmd --state 2>/dev/null | grep -q "running"; then
        echo -e "${GREEN}✓${NC} Firewalld: 已启用"
        echo "开放服务:"
        firewall-cmd --list-services 2>/dev/null | head -1
    else
        echo -e "${YELLOW}!${NC} Firewalld: 未运行"
    fi
else
    echo -e "${YELLOW}!${NC} 防火墙: 未检测到防火墙管理工具"
fi
echo ""

# 总结
echo -e "${BLUE}=== 检查完成 ===${NC}"
echo "如果发现问题，请参考以下解决方案:"
echo "1. 服务未运行: systemctl start study-system nginx"
echo "2. 端口未监听: 检查服务配置和防火墙设置"
echo "3. 无法访问: 检查云服务器安全组设置"
echo "4. 查看详细日志: journalctl -u study-system -f"
echo ""
echo "部署文档: 查看 DEPLOY.md 获取详细说明"
echo "技术支持: 检查应用日志和系统状态"