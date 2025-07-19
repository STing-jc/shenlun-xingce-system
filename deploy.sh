#!/bin/bash

# 申论行测学习系统部署脚本
# 适用于Linux轻量云服务器

set -e

echo "=== 申论行测学习系统部署脚本 ==="
echo "开始部署..."

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用root权限运行此脚本${NC}"
    echo "使用方法: sudo bash deploy.sh"
    exit 1
fi

# 更新系统
echo -e "${YELLOW}更新系统包...${NC}"
apt update && apt upgrade -y

# 安装必要的软件
echo -e "${YELLOW}安装必要软件...${NC}"
apt install -y curl wget git nginx

# 安装Node.js
echo -e "${YELLOW}安装Node.js...${NC}"
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

# 验证安装
echo -e "${GREEN}Node.js版本: $(node --version)${NC}"
echo -e "${GREEN}NPM版本: $(npm --version)${NC}"

# 安装Docker（可选）
read -p "是否安装Docker? (y/n): " install_docker
if [ "$install_docker" = "y" ]; then
    echo -e "${YELLOW}安装Docker...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    systemctl start docker
    systemctl enable docker
    
    # 安装Docker Compose
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo -e "${GREEN}Docker版本: $(docker --version)${NC}"
    echo -e "${GREEN}Docker Compose版本: $(docker-compose --version)${NC}"
fi

# 创建应用目录
APP_DIR="/var/www/study-system"
echo -e "${YELLOW}创建应用目录: $APP_DIR${NC}"
mkdir -p $APP_DIR
cd $APP_DIR

# 如果当前目录有文件，复制到应用目录
if [ -f "$(dirname $0)/package.json" ]; then
    echo -e "${YELLOW}复制应用文件...${NC}"
    cp -r $(dirname $0)/* $APP_DIR/
else
    echo -e "${RED}未找到应用文件，请确保在项目目录中运行此脚本${NC}"
    exit 1
fi

# 安装依赖
echo -e "${YELLOW}安装应用依赖...${NC}"
npm install --production

# 创建systemd服务
echo -e "${YELLOW}创建systemd服务...${NC}"
cat > /etc/systemd/system/study-system.service << EOF
[Unit]
Description=申论行测学习系统
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production
Environment=PORT=3000

[Install]
WantedBy=multi-user.target
EOF

# 设置文件权限
chown -R www-data:www-data $APP_DIR
chmod +x $APP_DIR/server.js

# 配置Nginx
echo -e "${YELLOW}配置Nginx...${NC}"
cp $APP_DIR/nginx.conf /etc/nginx/sites-available/study-system
ln -sf /etc/nginx/sites-available/study-system /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# 测试Nginx配置
nginx -t

# 启动服务
echo -e "${YELLOW}启动服务...${NC}"
systemctl daemon-reload
systemctl enable study-system
systemctl start study-system
systemctl restart nginx

# 配置防火墙
echo -e "${YELLOW}配置防火墙...${NC}"
if command -v ufw &> /dev/null; then
    ufw allow 22
    ufw allow 80
    ufw allow 443
    ufw --force enable
fi

# 检查服务状态
echo -e "${GREEN}检查服务状态...${NC}"
systemctl status study-system --no-pager
systemctl status nginx --no-pager

# 获取服务器IP
SERVER_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || echo "无法获取外网IP")

echo -e "${GREEN}=== 部署完成 ===${NC}"
echo -e "${GREEN}应用已成功部署到: $APP_DIR${NC}"
echo -e "${GREEN}本地访问: http://localhost${NC}"
echo -e "${GREEN}外网访问: http://$SERVER_IP${NC}"
echo ""
echo "常用命令:"
echo "  查看应用日志: journalctl -u study-system -f"
echo "  重启应用: systemctl restart study-system"
echo "  重启Nginx: systemctl restart nginx"
echo "  查看应用状态: systemctl status study-system"
echo ""
echo -e "${YELLOW}注意: 请确保云服务器安全组已开放80和443端口${NC}"