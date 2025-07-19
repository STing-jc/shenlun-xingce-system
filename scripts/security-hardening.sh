#!/bin/bash
# 申论行测学习系统 - 安全加固脚本
# 版本: v2.0.0
# 描述: 系统安全配置、防护和加固脚本

set -e

# ============================================================================
# 配置变量
# ============================================================================

# 应用配置
APP_NAME="${APP_NAME:-shenlun-xingce-system}"
APP_VERSION="${APP_VERSION:-2.0.0}"
APP_USER="${APP_USER:-app}"
APP_GROUP="${APP_GROUP:-app}"
APP_HOME="${APP_HOME:-/app}"
DATA_PATH="${DATA_PATH:-/app/data}"
LOG_PATH="${LOG_PATH:-/app/logs}"

# 安全配置
SSH_PORT="${SSH_PORT:-22}"
SSH_ALLOW_USERS="${SSH_ALLOW_USERS:-}"
SSH_DENY_USERS="${SSH_DENY_USERS:-}"
FAIL2BAN_ENABLED="${FAIL2BAN_ENABLED:-true}"
FIREWALL_ENABLED="${FIREWALL_ENABLED:-true}"
SELINUX_ENABLED="${SELINUX_ENABLED:-false}"
APPARMOR_ENABLED="${APPARMOR_ENABLED:-false}"

# 密码策略
PASSWORD_MIN_LENGTH="${PASSWORD_MIN_LENGTH:-12}"
PASSWORD_MAX_AGE="${PASSWORD_MAX_AGE:-90}"
PASSWORD_MIN_AGE="${PASSWORD_MIN_AGE:-1}"
PASSWORD_WARN_AGE="${PASSWORD_WARN_AGE:-7}"
LOGIN_RETRIES="${LOGIN_RETRIES:-3}"
LOCKOUT_TIME="${LOCKOUT_TIME:-300}"

# 网络安全
ALLOWED_PORTS="${ALLOWED_PORTS:-22,80,443,3000}"
BLOCKED_COUNTRIES="${BLOCKED_COUNTRIES:-}"
RATE_LIMIT_ENABLED="${RATE_LIMIT_ENABLED:-true}"
DDOS_PROTECTION="${DDOS_PROTECTION:-true}"

# 文件系统安全
FILE_INTEGRITY_CHECK="${FILE_INTEGRITY_CHECK:-true}"
ANTIVIRUS_ENABLED="${ANTIVIRUS_ENABLED:-false}"
ROOTKIT_DETECTION="${ROOTKIT_DETECTION:-true}"
LOG_MONITORING="${LOG_MONITORING:-true}"

# 加密配置
ENCRYPTION_ALGORITHM="${ENCRYPTION_ALGORITHM:-aes-256-cbc}"
HASH_ALGORITHM="${HASH_ALGORITHM:-sha256}"
SSL_CIPHER_SUITE="${SSL_CIPHER_SUITE:-ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20:!aNULL:!MD5:!DSS}"
SSL_PROTOCOLS="${SSL_PROTOCOLS:-TLSv1.2,TLSv1.3}"

# 审计配置
AUDIT_ENABLED="${AUDIT_ENABLED:-true}"
AUDIT_LOG_SIZE="${AUDIT_LOG_SIZE:-100M}"
AUDIT_RETENTION_DAYS="${AUDIT_RETENTION_DAYS:-365}"

# 备份加密
BACKUP_ENCRYPTION_ENABLED="${BACKUP_ENCRYPTION_ENABLED:-true}"
BACKUP_ENCRYPTION_KEY_FILE="${BACKUP_ENCRYPTION_KEY_FILE:-/app/config/backup.key}"

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
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_PATH/security.log"
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

log_security() {
    log "${PURPLE}[SECURITY]${NC} $1"
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
    elif [ -f /etc/SuSe-release ]; then
        OS=openSUSE
    elif [ -f /etc/redhat-release ]; then
        OS=RedHat
    else
        OS=$(uname -s)
        VER=$(uname -r)
    fi
    
    log_info "检测到操作系统: $OS $VER"
}

# 备份配置文件
backup_config() {
    local config_file="$1"
    local backup_dir="/root/security-backup-$(date +%Y%m%d)"
    
    if [ -f "$config_file" ]; then
        mkdir -p "$backup_dir"
        cp "$config_file" "$backup_dir/$(basename "$config_file").backup"
        log_info "已备份配置文件: $config_file"
    fi
}

# 生成随机密码
generate_password() {
    local length="${1:-16}"
    if command_exists openssl; then
        openssl rand -base64 32 | tr -d "=+/" | cut -c1-"$length"
    elif command_exists pwgen; then
        pwgen -s "$length" 1
    else
        # 使用/dev/urandom作为备选
        tr -dc 'A-Za-z0-9!@#$%^&*()_+' < /dev/urandom | head -c "$length"
    fi
}

# 生成加密密钥
generate_encryption_key() {
    local key_file="$1"
    local key_size="${2:-32}"  # 256位密钥
    
    if command_exists openssl; then
        openssl rand -hex "$key_size" > "$key_file"
        chmod 600 "$key_file"
        chown root:root "$key_file"
        log_success "已生成加密密钥: $key_file"
    else
        log_error "无法生成加密密钥，缺少openssl"
        return 1
    fi
}

# ============================================================================
# 系统加固函数
# ============================================================================

# 更新系统
update_system() {
    log_info "更新系统软件包..."
    
    case "$OS" in
        *Ubuntu*|*Debian*)
            apt-get update -y
            apt-get upgrade -y
            apt-get autoremove -y
            apt-get autoclean
            ;;
        *CentOS*|*RedHat*|*Rocky*|*AlmaLinux*)
            if command_exists dnf; then
                dnf update -y
                dnf autoremove -y
            elif command_exists yum; then
                yum update -y
                yum autoremove -y
            fi
            ;;
        *)
            log_warn "未知操作系统，跳过系统更新"
            return 0
            ;;
    esac
    
    log_success "系统更新完成"
}

# 安装安全工具
install_security_tools() {
    log_info "安装安全工具..."
    
    local tools=()
    
    # 基础安全工具
    tools+=("fail2ban" "ufw" "iptables" "iptables-persistent")
    
    # 入侵检测
    if [ "$ROOTKIT_DETECTION" = "true" ]; then
        tools+=("rkhunter" "chkrootkit")
    fi
    
    # 文件完整性检查
    if [ "$FILE_INTEGRITY_CHECK" = "true" ]; then
        tools+=("aide" "tripwire")
    fi
    
    # 审计工具
    if [ "$AUDIT_ENABLED" = "true" ]; then
        tools+=("auditd" "audispd-plugins")
    fi
    
    # 防病毒
    if [ "$ANTIVIRUS_ENABLED" = "true" ]; then
        tools+=("clamav" "clamav-daemon")
    fi
    
    # 网络安全工具
    tools+=("nmap" "netstat-nat" "tcpdump" "wireshark-common")
    
    # 加密工具
    tools+=("openssl" "gnupg" "cryptsetup")
    
    case "$OS" in
        *Ubuntu*|*Debian*)
            for tool in "${tools[@]}"; do
                if ! dpkg -l | grep -q "^ii  $tool "; then
                    apt-get install -y "$tool" 2>/dev/null || log_warn "无法安装 $tool"
                fi
            done
            ;;
        *CentOS*|*RedHat*|*Rocky*|*AlmaLinux*)
            for tool in "${tools[@]}"; do
                if command_exists dnf; then
                    dnf install -y "$tool" 2>/dev/null || log_warn "无法安装 $tool"
                elif command_exists yum; then
                    yum install -y "$tool" 2>/dev/null || log_warn "无法安装 $tool"
                fi
            done
            ;;
    esac
    
    log_success "安全工具安装完成"
}

# 配置SSH安全
configure_ssh_security() {
    log_info "配置SSH安全..."
    
    local ssh_config="/etc/ssh/sshd_config"
    backup_config "$ssh_config"
    
    # SSH安全配置
    cat > "$ssh_config" << EOF
# SSH安全配置 - 由安全加固脚本生成
# 生成时间: $(date)

# 基础配置
Port $SSH_PORT
Protocol 2
AddressFamily inet

# 认证配置
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# 连接限制
MaxAuthTries 3
MaxSessions 10
MaxStartups 10:30:60
LoginGraceTime 60
ClientAliveInterval 300
ClientAliveCountMax 2

# 用户限制
EOF
    
    # 添加允许的用户
    if [ -n "$SSH_ALLOW_USERS" ]; then
        echo "AllowUsers $SSH_ALLOW_USERS" >> "$ssh_config"
    fi
    
    # 添加拒绝的用户
    if [ -n "$SSH_DENY_USERS" ]; then
        echo "DenyUsers $SSH_DENY_USERS" >> "$ssh_config"
    fi
    
    cat >> "$ssh_config" << EOF

# 安全选项
X11Forwarding no
AllowTcpForwarding no
GatewayPorts no
PermitTunnel no
PermitUserEnvironment no
StrictModes yes
IgnoreRhosts yes
HostbasedAuthentication no

# 加密配置
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,hmac-sha2-256,hmac-sha2-512
KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512

# 日志配置
SyslogFacility AUTH
LogLevel INFO

# Banner
Banner /etc/ssh/banner
EOF
    
    # 创建SSH Banner
    cat > /etc/ssh/banner << EOF
***************************************************************************
                    AUTHORIZED ACCESS ONLY
***************************************************************************

此系统仅供授权用户使用。未经授权的访问是被禁止的。
所有活动都将被监控和记录。

系统: $APP_NAME v$APP_VERSION
主机: $(hostname)
时间: $(date)

***************************************************************************
EOF
    
    # 重启SSH服务
    if command_exists systemctl; then
        systemctl restart sshd
    elif command_exists service; then
        service ssh restart
    fi
    
    log_success "SSH安全配置完成"
}

# 配置防火墙
configure_firewall() {
    if [ "$FIREWALL_ENABLED" != "true" ]; then
        log_info "跳过防火墙配置（已禁用）"
        return 0
    fi
    
    log_info "配置防火墙..."
    
    # 使用UFW（Ubuntu/Debian）
    if command_exists ufw; then
        # 重置防火墙规则
        ufw --force reset
        
        # 默认策略
        ufw default deny incoming
        ufw default allow outgoing
        
        # 允许指定端口
        IFS=',' read -ra PORTS <<< "$ALLOWED_PORTS"
        for port in "${PORTS[@]}"; do
            ufw allow "$port"
            log_info "允许端口: $port"
        done
        
        # 限制SSH连接
        ufw limit "$SSH_PORT"/tcp
        
        # 启用防火墙
        ufw --force enable
        
        log_success "UFW防火墙配置完成"
        
    # 使用firewalld（CentOS/RedHat）
    elif command_exists firewall-cmd; then
        # 启动firewalld
        systemctl start firewalld
        systemctl enable firewalld
        
        # 设置默认区域
        firewall-cmd --set-default-zone=public
        
        # 移除所有服务
        firewall-cmd --zone=public --remove-service=ssh --permanent 2>/dev/null || true
        firewall-cmd --zone=public --remove-service=dhcpv6-client --permanent 2>/dev/null || true
        
        # 添加允许的端口
        IFS=',' read -ra PORTS <<< "$ALLOWED_PORTS"
        for port in "${PORTS[@]}"; do
            firewall-cmd --zone=public --add-port="$port"/tcp --permanent
            log_info "允许端口: $port"
        done
        
        # 重新加载配置
        firewall-cmd --reload
        
        log_success "firewalld防火墙配置完成"
        
    # 使用iptables
    elif command_exists iptables; then
        # 清空现有规则
        iptables -F
        iptables -X
        iptables -t nat -F
        iptables -t nat -X
        iptables -t mangle -F
        iptables -t mangle -X
        
        # 默认策略
        iptables -P INPUT DROP
        iptables -P FORWARD DROP
        iptables -P OUTPUT ACCEPT
        
        # 允许本地回环
        iptables -A INPUT -i lo -j ACCEPT
        iptables -A OUTPUT -o lo -j ACCEPT
        
        # 允许已建立的连接
        iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
        
        # 允许指定端口
        IFS=',' read -ra PORTS <<< "$ALLOWED_PORTS"
        for port in "${PORTS[@]}"; do
            iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
            log_info "允许端口: $port"
        done
        
        # SSH连接限制
        iptables -A INPUT -p tcp --dport "$SSH_PORT" -m state --state NEW -m recent --set
        iptables -A INPUT -p tcp --dport "$SSH_PORT" -m state --state NEW -m recent --update --seconds 60 --hitcount 4 -j DROP
        
        # DDoS保护
        if [ "$DDOS_PROTECTION" = "true" ]; then
            iptables -A INPUT -p tcp --dport 80 -m limit --limit 25/minute --limit-burst 100 -j ACCEPT
            iptables -A INPUT -p tcp --dport 443 -m limit --limit 25/minute --limit-burst 100 -j ACCEPT
        fi
        
        # 保存规则
        if command_exists iptables-save; then
            iptables-save > /etc/iptables/rules.v4
        fi
        
        log_success "iptables防火墙配置完成"
    else
        log_warn "未找到防火墙工具"
    fi
}

# 配置Fail2Ban
configure_fail2ban() {
    if [ "$FAIL2BAN_ENABLED" != "true" ] || ! command_exists fail2ban-server; then
        log_info "跳过Fail2Ban配置"
        return 0
    fi
    
    log_info "配置Fail2Ban..."
    
    # 创建本地配置文件
    cat > /etc/fail2ban/jail.local << EOF
# Fail2Ban配置 - 由安全加固脚本生成
# 生成时间: $(date)

[DEFAULT]
# 忽略的IP地址
ignoreip = 127.0.0.1/8 ::1

# 封禁时间（秒）
bantime = $LOCKOUT_TIME

# 查找时间窗口（秒）
findtime = 600

# 最大重试次数
maxretry = $LOGIN_RETRIES

# 后端
backend = auto

# 邮件配置
destemail = root@localhost
sender = root@localhost
mta = sendmail

# 动作
action = %(action_mwl)s

[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
logpath = /var/log/nginx/error.log
maxretry = 5

[nginx-limit-req]
enabled = true
filter = nginx-limit-req
logpath = /var/log/nginx/error.log
maxretry = 10

[nginx-botsearch]
enabled = true
filter = nginx-botsearch
logpath = /var/log/nginx/access.log
maxretry = 2

[recidive]
enabled = true
filter = recidive
logpath = /var/log/fail2ban.log
action = %(action_mwl)s
bantime = 86400
findtime = 86400
maxretry = 5
EOF
    
    # 创建应用专用过滤器
    cat > "/etc/fail2ban/filter.d/${APP_NAME}.conf" << EOF
# $APP_NAME Fail2Ban过滤器

[Definition]
failregex = ^.*\[.*\] .*"(GET|POST).*" (4|5)\d\d .*".*" ".*".*$
            ^.*\[.*\] .*Authentication failed.*$
            ^.*\[.*\] .*Invalid login attempt.*$
            ^.*\[.*\] .*Suspicious activity detected.*$

ignoreregex =
EOF
    
    # 添加应用监控
    cat >> /etc/fail2ban/jail.local << EOF

[$APP_NAME]
enabled = true
filter = $APP_NAME
logpath = $LOG_PATH/app.log
maxretry = 5
bantime = 1800
EOF
    
    # 启动Fail2Ban
    systemctl enable fail2ban
    systemctl restart fail2ban
    
    log_success "Fail2Ban配置完成"
}

# 配置密码策略
configure_password_policy() {
    log_info "配置密码策略..."
    
    # 配置PAM密码复杂度
    if [ -f /etc/pam.d/common-password ]; then
        backup_config /etc/pam.d/common-password
        
        # 移除旧的pam_pwquality配置
        sed -i '/pam_pwquality.so/d' /etc/pam.d/common-password
        
        # 添加新的密码复杂度要求
        echo "password requisite pam_pwquality.so retry=3 minlen=$PASSWORD_MIN_LENGTH dcredit=-1 ucredit=-1 ocredit=-1 lcredit=-1" >> /etc/pam.d/common-password
    fi
    
    # 配置密码有效期
    backup_config /etc/login.defs
    
    sed -i "s/^PASS_MAX_DAYS.*/PASS_MAX_DAYS\t$PASSWORD_MAX_AGE/" /etc/login.defs
    sed -i "s/^PASS_MIN_DAYS.*/PASS_MIN_DAYS\t$PASSWORD_MIN_AGE/" /etc/login.defs
    sed -i "s/^PASS_WARN_AGE.*/PASS_WARN_AGE\t$PASSWORD_WARN_AGE/" /etc/login.defs
    sed -i "s/^PASS_MIN_LEN.*/PASS_MIN_LEN\t$PASSWORD_MIN_LENGTH/" /etc/login.defs
    
    # 配置账户锁定
    if [ -f /etc/pam.d/common-auth ]; then
        backup_config /etc/pam.d/common-auth
        
        # 添加账户锁定配置
        if ! grep -q "pam_tally2" /etc/pam.d/common-auth; then
            sed -i '1i auth required pam_tally2.so deny='"$LOGIN_RETRIES"' unlock_time='"$LOCKOUT_TIME"' onerr=fail audit even_deny_root' /etc/pam.d/common-auth
        fi
    fi
    
    log_success "密码策略配置完成"
}

# 配置文件权限
configure_file_permissions() {
    log_info "配置文件权限..."
    
    # 系统关键文件权限
    chmod 644 /etc/passwd
    chmod 600 /etc/shadow
    chmod 644 /etc/group
    chmod 600 /etc/gshadow
    chmod 600 /etc/ssh/sshd_config
    chmod 644 /etc/ssh/ssh_config
    
    # 应用文件权限
    if [ -d "$APP_HOME" ]; then
        # 创建应用用户（如果不存在）
        if ! id "$APP_USER" >/dev/null 2>&1; then
            useradd -r -s /bin/false -d "$APP_HOME" "$APP_USER"
            log_info "已创建应用用户: $APP_USER"
        fi
        
        # 设置应用目录权限
        chown -R "$APP_USER:$APP_GROUP" "$APP_HOME"
        chmod -R 750 "$APP_HOME"
        
        # 数据目录权限
        if [ -d "$DATA_PATH" ]; then
            chown -R "$APP_USER:$APP_GROUP" "$DATA_PATH"
            chmod -R 700 "$DATA_PATH"
        fi
        
        # 日志目录权限
        if [ -d "$LOG_PATH" ]; then
            chown -R "$APP_USER:$APP_GROUP" "$LOG_PATH"
            chmod -R 750 "$LOG_PATH"
        fi
        
        # 配置文件权限
        if [ -f "$APP_HOME/.env" ]; then
            chown "$APP_USER:$APP_GROUP" "$APP_HOME/.env"
            chmod 600 "$APP_HOME/.env"
        fi
    fi
    
    # 移除危险权限
    find / -type f -perm -4000 -exec ls -la {} \; 2>/dev/null | grep -v "^find:" > /tmp/suid_files.txt || true
    find / -type f -perm -2000 -exec ls -la {} \; 2>/dev/null | grep -v "^find:" > /tmp/sgid_files.txt || true
    
    log_success "文件权限配置完成"
}

# 配置内核参数
configure_kernel_parameters() {
    log_info "配置内核安全参数..."
    
    backup_config /etc/sysctl.conf
    
    cat >> /etc/sysctl.conf << EOF

# 安全加固参数 - 由安全加固脚本添加
# 生成时间: $(date)

# 网络安全
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.tcp_syncookies = 1

# TCP/IP栈加固
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1800
net.ipv4.tcp_keepalive_probes = 7
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_rmem = 4096 65536 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.netdev_max_backlog = 5000

# 内存保护
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
kernel.core_uses_pid = 1
fs.suid_dumpable = 0

# 地址空间随机化
kernel.randomize_va_space = 2

# 文件系统安全
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
EOF
    
    # 应用内核参数
    sysctl -p
    
    log_success "内核安全参数配置完成"
}

# 配置审计
configure_audit() {
    if [ "$AUDIT_ENABLED" != "true" ] || ! command_exists auditctl; then
        log_info "跳过审计配置"
        return 0
    fi
    
    log_info "配置系统审计..."
    
    backup_config /etc/audit/auditd.conf
    backup_config /etc/audit/audit.rules
    
    # 配置auditd
    cat > /etc/audit/auditd.conf << EOF
# 审计配置 - 由安全加固脚本生成
# 生成时间: $(date)

log_file = /var/log/audit/audit.log
log_format = RAW
log_group = adm
priority_boost = 4
flush = INCREMENTAL_ASYNC
freq = 50
max_log_file = $AUDIT_LOG_SIZE
num_logs = 5
disp_qos = lossy
dispatcher = /sbin/audispd
name_format = NONE
max_log_file_action = ROTATE
space_left = 75
space_left_action = SYSLOG
verify_email = yes
action_mail_acct = root
admin_space_left = 50
admin_space_left_action = SUSPEND
disk_full_action = SUSPEND
disk_error_action = SUSPEND
use_libwrap = yes
tcp_listen_queue = 5
tcp_max_per_addr = 1
tcp_client_max_idle = 0
enable_krb5 = no
krb5_principal = auditd
EOF
    
    # 配置审计规则
    cat > /etc/audit/audit.rules << EOF
# 审计规则 - 由安全加固脚本生成
# 生成时间: $(date)

# 删除所有现有规则
-D

# 设置缓冲区大小
-b 8192

# 设置失败模式
-f 1

# 监控系统调用
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time-change
-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S stime -k time-change
-a always,exit -F arch=b64 -S clock_settime -k time-change
-a always,exit -F arch=b32 -S clock_settime -k time-change
-w /etc/localtime -p wa -k time-change

# 监控用户和组管理
-w /etc/group -p wa -k identity
-w /etc/passwd -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity

# 监控网络配置
-a always,exit -F arch=b64 -S sethostname -S setdomainname -k system-locale
-a always,exit -F arch=b32 -S sethostname -S setdomainname -k system-locale
-w /etc/issue -p wa -k system-locale
-w /etc/issue.net -p wa -k system-locale
-w /etc/hosts -p wa -k system-locale
-w /etc/network -p wa -k system-locale

# 监控权限变更
-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b64 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod

# 监控文件访问
-a always,exit -F arch=b64 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b32 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b64 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b32 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access

# 监控特权命令
-w /bin/su -p x -k privileged
-w /usr/bin/sudo -p x -k privileged
-w /usr/bin/passwd -p x -k privileged
-w /usr/bin/ssh -p x -k privileged

# 监控系统配置文件
-w /etc/ssh/sshd_config -p wa -k sshd
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d/ -p wa -k scope

# 监控应用文件
-w $APP_HOME -p wa -k app-files
-w $DATA_PATH -p wa -k app-data
-w $LOG_PATH -p wa -k app-logs

# 使规则不可变
-e 2
EOF
    
    # 重启审计服务
    systemctl enable auditd
    systemctl restart auditd
    
    log_success "系统审计配置完成"
}

# 配置入侵检测
configure_intrusion_detection() {
    log_info "配置入侵检测..."
    
    # 配置rkhunter
    if command_exists rkhunter; then
        # 更新rkhunter数据库
        rkhunter --update
        
        # 配置rkhunter
        backup_config /etc/rkhunter.conf
        
        sed -i 's/^#MAIL-ON-WARNING=.*/MAIL-ON-WARNING=root@localhost/' /etc/rkhunter.conf
        sed -i 's/^#MAIL_CMD=.*/MAIL_CMD=mail -s "[rkhunter] Warnings found for ${HOST_NAME}"/' /etc/rkhunter.conf
        
        # 创建基线
        rkhunter --propupd
        
        log_success "rkhunter配置完成"
    fi
    
    # 配置AIDE
    if command_exists aide; then
        # 初始化AIDE数据库
        if [ ! -f /var/lib/aide/aide.db ]; then
            aide --init
            mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
        fi
        
        log_success "AIDE配置完成"
    fi
    
    # 配置ClamAV
    if [ "$ANTIVIRUS_ENABLED" = "true" ] && command_exists clamscan; then
        # 更新病毒库
        freshclam
        
        # 启动ClamAV守护进程
        systemctl enable clamav-daemon
        systemctl start clamav-daemon
        
        log_success "ClamAV配置完成"
    fi
}

# ============================================================================
# 加密和密钥管理
# ============================================================================

# 生成SSL证书
generate_ssl_certificate() {
    local domain="${1:-localhost}"
    local cert_dir="/etc/ssl/certs"
    local key_dir="/etc/ssl/private"
    
    log_info "生成SSL证书..."
    
    mkdir -p "$cert_dir" "$key_dir"
    
    # 生成私钥
    openssl genrsa -out "$key_dir/$domain.key" 2048
    chmod 600 "$key_dir/$domain.key"
    
    # 生成证书签名请求
    openssl req -new -key "$key_dir/$domain.key" -out "$cert_dir/$domain.csr" -subj "/C=CN/ST=Beijing/L=Beijing/O=$APP_NAME/OU=IT/CN=$domain"
    
    # 生成自签名证书
    openssl x509 -req -days 365 -in "$cert_dir/$domain.csr" -signkey "$key_dir/$domain.key" -out "$cert_dir/$domain.crt"
    
    # 生成DH参数
    openssl dhparam -out "$cert_dir/dhparam.pem" 2048
    
    log_success "SSL证书生成完成: $cert_dir/$domain.crt"
}

# 配置备份加密
configure_backup_encryption() {
    if [ "$BACKUP_ENCRYPTION_ENABLED" != "true" ]; then
        log_info "跳过备份加密配置"
        return 0
    fi
    
    log_info "配置备份加密..."
    
    local key_dir="$(dirname "$BACKUP_ENCRYPTION_KEY_FILE")"
    mkdir -p "$key_dir"
    
    # 生成备份加密密钥
    if [ ! -f "$BACKUP_ENCRYPTION_KEY_FILE" ]; then
        generate_encryption_key "$BACKUP_ENCRYPTION_KEY_FILE" 32
    fi
    
    # 创建加密脚本
    cat > /usr/local/bin/encrypt-backup << 'EOF'
#!/bin/bash
# 备份加密脚本

if [ $# -ne 2 ]; then
    echo "用法: $0 <输入文件> <输出文件>"
    exit 1
fi

INPUT_FILE="$1"
OUTPUT_FILE="$2"
KEY_FILE="${BACKUP_ENCRYPTION_KEY_FILE:-/app/config/backup.key}"

if [ ! -f "$KEY_FILE" ]; then
    echo "错误: 加密密钥文件不存在: $KEY_FILE"
    exit 1
fi

KEY=$(cat "$KEY_FILE")
openssl enc -aes-256-cbc -salt -in "$INPUT_FILE" -out "$OUTPUT_FILE" -k "$KEY"
EOF
    
    chmod +x /usr/local/bin/encrypt-backup
    
    # 创建解密脚本
    cat > /usr/local/bin/decrypt-backup << 'EOF'
#!/bin/bash
# 备份解密脚本

if [ $# -ne 2 ]; then
    echo "用法: $0 <输入文件> <输出文件>"
    exit 1
fi

INPUT_FILE="$1"
OUTPUT_FILE="$2"
KEY_FILE="${BACKUP_ENCRYPTION_KEY_FILE:-/app/config/backup.key}"

if [ ! -f "$KEY_FILE" ]; then
    echo "错误: 加密密钥文件不存在: $KEY_FILE"
    exit 1
fi

KEY=$(cat "$KEY_FILE")
openssl enc -aes-256-cbc -d -in "$INPUT_FILE" -out "$OUTPUT_FILE" -k "$KEY"
EOF
    
    chmod +x /usr/local/bin/decrypt-backup
    
    log_success "备份加密配置完成"
}

# ============================================================================
# 安全检查和报告
# ============================================================================

# 执行安全检查
perform_security_check() {
    log_info "执行安全检查..."
    
    local issues=0
    local report_file="/tmp/security-check-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "申论行测学习系统 - 安全检查报告"
        echo "=============================="
        echo "检查时间: $(date)"
        echo "主机名称: $(hostname)"
        echo "操作系统: $OS $VER"
        echo ""
        
        # 检查SSH配置
        echo "SSH安全检查:"
        if [ -f /etc/ssh/sshd_config ]; then
            if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config; then
                echo "  ✓ 已禁用root登录"
            else
                echo "  ✗ 未禁用root登录"
                issues=$((issues + 1))
            fi
            
            if grep -q "^PasswordAuthentication" /etc/ssh/sshd_config; then
                echo "  ✓ 已配置密码认证策略"
            else
                echo "  ✗ 未配置密码认证策略"
                issues=$((issues + 1))
            fi
        else
            echo "  ✗ SSH配置文件不存在"
            issues=$((issues + 1))
        fi
        echo ""
        
        # 检查防火墙状态
        echo "防火墙检查:"
        if command_exists ufw && ufw status | grep -q "Status: active"; then
            echo "  ✓ UFW防火墙已启用"
        elif command_exists firewall-cmd && firewall-cmd --state 2>/dev/null | grep -q "running"; then
            echo "  ✓ firewalld防火墙已启用"
        elif iptables -L | grep -q "Chain INPUT (policy DROP)"; then
            echo "  ✓ iptables防火墙已配置"
        else
            echo "  ✗ 防火墙未启用或配置不当"
            issues=$((issues + 1))
        fi
        echo ""
        
        # 检查Fail2Ban状态
        echo "Fail2Ban检查:"
        if command_exists fail2ban-client && systemctl is-active fail2ban >/dev/null 2>&1; then
            echo "  ✓ Fail2Ban服务正在运行"
            echo "  当前封禁IP数量: $(fail2ban-client status | grep "Jail list" | wc -w)"
        else
            echo "  ✗ Fail2Ban服务未运行"
            issues=$((issues + 1))
        fi
        echo ""
        
        # 检查文件权限
        echo "文件权限检查:"
        if [ "$(stat -c %a /etc/passwd)" = "644" ]; then
            echo "  ✓ /etc/passwd权限正确"
        else
            echo "  ✗ /etc/passwd权限不正确"
            issues=$((issues + 1))
        fi
        
        if [ "$(stat -c %a /etc/shadow)" = "600" ]; then
            echo "  ✓ /etc/shadow权限正确"
        else
            echo "  ✗ /etc/shadow权限不正确"
            issues=$((issues + 1))
        fi
        echo ""
        
        # 检查系统更新
        echo "系统更新检查:"
        case "$OS" in
            *Ubuntu*|*Debian*)
                local updates=$(apt list --upgradable 2>/dev/null | wc -l)
                if [ "$updates" -gt 1 ]; then
                    echo "  ⚠ 有 $((updates - 1)) 个可用更新"
                else
                    echo "  ✓ 系统已是最新版本"
                fi
                ;;
            *CentOS*|*RedHat*|*Rocky*|*AlmaLinux*)
                if command_exists dnf; then
                    local updates=$(dnf check-update 2>/dev/null | grep -c "^[a-zA-Z]" || echo "0")
                elif command_exists yum; then
                    local updates=$(yum check-update 2>/dev/null | grep -c "^[a-zA-Z]" || echo "0")
                fi
                if [ "$updates" -gt 0 ]; then
                    echo "  ⚠ 有 $updates 个可用更新"
                else
                    echo "  ✓ 系统已是最新版本"
                fi
                ;;
        esac
        echo ""
        
        # 检查运行的服务
        echo "服务检查:"
        local dangerous_services=("telnet" "ftp" "rsh" "rlogin")
        for service in "${dangerous_services[@]}"; do
            if systemctl is-active "$service" >/dev/null 2>&1; then
                echo "  ✗ 危险服务 $service 正在运行"
                issues=$((issues + 1))
            fi
        done
        
        if [ $issues -eq 0 ]; then
            echo "  ✓ 未发现危险服务"
        fi
        echo ""
        
        # 检查网络连接
        echo "网络连接检查:"
        local suspicious_connections=$(netstat -tuln | grep LISTEN | wc -l)
        echo "  监听端口数量: $suspicious_connections"
        
        # 显示监听端口
        echo "  监听端口列表:"
        netstat -tuln | grep LISTEN | awk '{print "    " $1 " " $4}' | sort
        echo ""
        
        # 总结
        echo "检查总结:"
        if [ $issues -eq 0 ]; then
            echo "  ✓ 安全检查通过，未发现安全问题"
        else
            echo "  ✗ 发现 $issues 个安全问题，建议立即修复"
        fi
        
    } | tee "$report_file"
    
    log_success "安全检查完成，报告已保存到: $report_file"
    
    return $issues
}

# 生成安全报告
generate_security_report() {
    local report_type="${1:-summary}"
    local report_file="/tmp/security-report-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "申论行测学习系统 - 安全状态报告"
        echo "================================"
        echo "生成时间: $(date)"
        echo "主机名称: $(hostname)"
        echo "操作系统: $OS $VER"
        echo "内核版本: $(uname -r)"
        echo ""
        
        # 系统信息
        echo "系统信息:"
        echo "  运行时间: $(uptime -p 2>/dev/null || uptime)"
        echo "  CPU核心: $(nproc)"
        echo "  总内存: $(free -h | grep Mem: | awk '{print $2}')"
        echo "  磁盘使用: $(df -h / | tail -1 | awk '{print $5}')"
        echo ""
        
        # 安全服务状态
        echo "安全服务状态:"
        
        # SSH状态
        if systemctl is-active sshd >/dev/null 2>&1; then
            echo "  SSH: 运行中 (端口: $SSH_PORT)"
        else
            echo "  SSH: 未运行"
        fi
        
        # 防火墙状态
        if command_exists ufw && ufw status | grep -q "Status: active"; then
            echo "  防火墙: UFW (活跃)"
        elif command_exists firewall-cmd && firewall-cmd --state 2>/dev/null | grep -q "running"; then
            echo "  防火墙: firewalld (运行中)"
        else
            echo "  防火墙: 未配置或未运行"
        fi
        
        # Fail2Ban状态
        if command_exists fail2ban-client && systemctl is-active fail2ban >/dev/null 2>&1; then
            echo "  Fail2Ban: 运行中"
            if [ "$report_type" = "detailed" ]; then
                echo "    监狱状态:"
                fail2ban-client status 2>/dev/null | grep "Jail list" | sed 's/.*://; s/,/\n/g' | while read jail; do
                    if [ -n "$jail" ]; then
                        local banned=$(fail2ban-client status "$jail" 2>/dev/null | grep "Currently banned" | awk '{print $4}')
                        echo "      $jail: $banned 个IP被封禁"
                    fi
                done
            fi
        else
            echo "  Fail2Ban: 未运行"
        fi
        
        # 审计状态
        if command_exists auditctl && systemctl is-active auditd >/dev/null 2>&1; then
            echo "  审计: 运行中"
            if [ "$report_type" = "detailed" ]; then
                echo "    规则数量: $(auditctl -l | wc -l)"
            fi
        else
            echo "  审计: 未运行"
        fi
        echo ""
        
        # 用户和权限
        echo "用户和权限:"
        echo "  系统用户数量: $(cat /etc/passwd | wc -l)"
        echo "  具有shell的用户: $(grep -v '/nologin\|/false' /etc/passwd | wc -l)"
        echo "  sudo用户: $(grep -c '^sudo:' /etc/group 2>/dev/null || echo '0')"
        
        if [ "$report_type" = "detailed" ]; then
            echo "  最近登录:"
            last -n 5 | head -5 | while read line; do
                echo "    $line"
            done
        fi
        echo ""
        
        # 网络安全
        echo "网络安全:"
        echo "  监听端口数量: $(netstat -tuln 2>/dev/null | grep LISTEN | wc -l)"
        echo "  活跃连接数量: $(netstat -tun 2>/dev/null | grep ESTABLISHED | wc -l)"
        
        if [ "$report_type" = "detailed" ]; then
            echo "  开放端口:"
            netstat -tuln 2>/dev/null | grep LISTEN | awk '{print "    " $1 " " $4}' | sort
        fi
        echo ""
        
        # 文件系统安全
        echo "文件系统安全:"
        echo "  SUID文件数量: $(find / -type f -perm -4000 2>/dev/null | wc -l)"
        echo "  SGID文件数量: $(find / -type f -perm -2000 2>/dev/null | wc -l)"
        echo "  世界可写文件: $(find / -type f -perm -002 2>/dev/null | wc -l)"
        
        if [ "$report_type" = "detailed" ]; then
            echo "  关键文件权限:"
            echo "    /etc/passwd: $(stat -c %a /etc/passwd)"
            echo "    /etc/shadow: $(stat -c %a /etc/shadow)"
            echo "    /etc/ssh/sshd_config: $(stat -c %a /etc/ssh/sshd_config)"
        fi
        echo ""
        
        # 日志和监控
        echo "日志和监控:"
        echo "  系统日志大小: $(du -sh /var/log 2>/dev/null | cut -f1)"
        echo "  认证失败次数(今日): $(grep "$(date +'%b %d')" /var/log/auth.log 2>/dev/null | grep -c "authentication failure" || echo '0')"
        
        if [ "$report_type" = "detailed" ]; then
            echo "  最近的安全事件:"
            grep "$(date +'%b %d')" /var/log/auth.log 2>/dev/null | grep -E "(Failed|Invalid|authentication failure)" | tail -5 | while read line; do
                echo "    $line"
            done
        fi
        echo ""
        
        # 建议
        echo "安全建议:"
        echo "  1. 定期更新系统和软件包"
        echo "  2. 定期检查和轮转日志文件"
        echo "  3. 监控异常登录和网络活动"
        echo "  4. 定期备份重要数据"
        echo "  5. 定期执行安全扫描和检查"
        
    } | tee "$report_file"
    
    log_success "安全报告生成完成: $report_file"
}

# ============================================================================
# 主函数
# ============================================================================

# 执行完整安全加固
perform_full_hardening() {
    log_info "开始执行完整安全加固..."
    
    local start_time=$(date +%s)
    
    # 检查环境
    check_root
    detect_os
    
    # 创建日志目录
    mkdir -p "$LOG_PATH"
    
    # 执行加固步骤
    update_system
    install_security_tools
    configure_ssh_security
    configure_firewall
    configure_fail2ban
    configure_password_policy
    configure_file_permissions
    configure_kernel_parameters
    configure_audit
    configure_intrusion_detection
    configure_backup_encryption
    
    # 生成SSL证书
    generate_ssl_certificate "localhost"
    
    # 计算总耗时
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_success "安全加固完成，耗时 ${duration} 秒"
    
    # 执行安全检查
    log_info "执行安全检查验证..."
    if perform_security_check; then
        log_success "安全检查通过"
    else
        log_warn "安全检查发现问题，请查看报告"
    fi
}

# 显示帮助信息
show_help() {
    cat << EOF
申论行测学习系统 - 安全加固脚本

用法:
  $0 <命令> [选项]

命令:
  harden                        执行完整安全加固
  check                         执行安全检查
  report [summary|detailed]     生成安全报告
  ssh                          配置SSH安全
  firewall                     配置防火墙
  fail2ban                     配置Fail2Ban
  password                     配置密码策略
  permissions                  配置文件权限
  kernel                       配置内核参数
  audit                        配置审计
  ids                          配置入侵检测
  ssl <domain>                 生成SSL证书
  backup-encryption            配置备份加密
  help                         显示帮助信息

示例:
  $0 harden                    执行完整安全加固
  $0 check                     执行安全检查
  $0 report detailed           生成详细安全报告
  $0 ssl example.com           为域名生成SSL证书

环境变量:
  SSH_PORT                     SSH端口号
  FIREWALL_ENABLED             是否启用防火墙
  FAIL2BAN_ENABLED             是否启用Fail2Ban
  PASSWORD_MIN_LENGTH          密码最小长度
  AUDIT_ENABLED                是否启用审计
EOF
}

# 主函数
main() {
    # 确保日志目录存在
    mkdir -p "$LOG_PATH"
    
    case "${1:-help}" in
        "harden")
            perform_full_hardening
            ;;
        "check")
            perform_security_check
            ;;
        "report")
            generate_security_report "${2:-summary}"
            ;;
        "ssh")
            check_root
            detect_os
            configure_ssh_security
            ;;
        "firewall")
            check_root
            detect_os
            configure_firewall
            ;;
        "fail2ban")
            check_root
            detect_os
            configure_fail2ban
            ;;
        "password")
            check_root
            configure_password_policy
            ;;
        "permissions")
            check_root
            configure_file_permissions
            ;;
        "kernel")
            check_root
            configure_kernel_parameters
            ;;
        "audit")
            check_root
            detect_os
            configure_audit
            ;;
        "ids")
            check_root
            detect_os
            configure_intrusion_detection
            ;;
        "ssl")
            check_root
            if [ -z "$2" ]; then
                log_error "请指定域名"
                exit 1
            fi
            generate_ssl_certificate "$2"
            ;;
        "backup-encryption")
            check_root
            configure_backup_encryption
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