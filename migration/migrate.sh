#!/bin/bash
set -e

# 服务器迁移脚本
# 从 api.ai.org.kg 迁移到 grokapi.ai.org.kg

OLD_SERVER="root@api.ai.org.kg"
NEW_SERVER="root@grokapi.ai.org.kg"
DOMAIN="grokapi.ai.org.kg"
OLD_PATH="/opt/grok2api"
NEW_PATH="/opt/grok2api"
BACKUP_DIR="/tmp/grok2api_backup_$(date +%Y%m%d_%H%M%S)"

echo "========================================="
echo "Grok2API 服务器迁移脚本"
echo "从: $OLD_SERVER"
echo "到: $NEW_SERVER"
echo "域名: $DOMAIN"
echo "========================================="
echo ""

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Step 1: 检查新服务器连接
log_info "步骤 1/9: 检查服务器连接..."
if ! ssh -o ConnectTimeout=10 $NEW_SERVER "echo 'Connection OK'" &>/dev/null; then
    log_error "无法连接到新服务器 $NEW_SERVER"
    exit 1
fi
log_info "✓ 新服务器连接正常"

if ! ssh -o ConnectTimeout=10 $OLD_SERVER "echo 'Connection OK'" &>/dev/null; then
    log_error "无法连接到旧服务器 $OLD_SERVER"
    exit 1
fi
log_info "✓ 旧服务器连接正常"

# Step 2: 检查旧服务器状态
log_info "步骤 2/9: 检查旧服务器状态..."
ssh $OLD_SERVER "cd $OLD_PATH && pwd"
log_info "✓ 旧服务器 grok2api 目录存在"

# Step 3: 停止旧服务器服务
log_info "步骤 3/9: 停止旧服务器 grok2api 服务..."
read -p "确认停止旧服务器服务? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ssh $OLD_SERVER "pkill -f 'granian.*grok2api' || true"
    sleep 3
    log_info "✓ 旧服务器服务已停止"
else
    log_warn "跳过停止服务"
fi

# Step 4: 备份数据
log_info "步骤 4/9: 备份旧服务器数据..."
mkdir -p $BACKUP_DIR
log_info "备份目录: $BACKUP_DIR"

# 备份 data 目录
log_info "正在备份 data 目录（约 496MB）..."
scp -r $OLD_SERVER:$OLD_PATH/data/ $BACKUP_DIR/
log_info "✓ data 目录备份完成"

# 备份配置文件
log_info "正在备份配置文件..."
scp $OLD_SERVER:$OLD_PATH/config.defaults.toml $BACKUP_DIR/ 2>/dev/null || true
scp $OLD_SERVER:$OLD_PATH/.env $BACKUP_DIR/ 2>/dev/null || true
log_info "✓ 配置文件备份完成"

# Step 5: 在新服务器安装依赖
log_info "步骤 5/9: 在新服务器安装依赖..."
ssh $NEW_SERVER "bash -s" << 'ENDSSH'
set -e

# 更新系统
apt update

# 安装基础工具
apt install -y curl wget git nginx certbot python3-certbot-nginx

# 安装 Docker
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    systemctl enable docker
    systemctl start docker
    rm get-docker.sh
fi

# 安装 uv (Python 包管理器)
if ! command -v uv &> /dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
fi

echo "依赖安装完成"
ENDSSH
log_info "✓ 新服务器依赖安装完成"

# Step 6: 部署代码到新服务器
log_info "步骤 6/9: 部署代码到新服务器..."
ssh $NEW_SERVER "bash -s" << ENDSSH
set -e

# 创建目录
mkdir -p $NEW_PATH
cd $NEW_PATH

# 克隆最新代码
if [ -d ".git" ]; then
    git pull
else
    git clone https://github.com/jiangmuran/grok2api_pro.git .
fi

# 安装 Python 依赖
export PATH="\$HOME/.local/bin:\$PATH"
uv sync

echo "代码部署完成"
ENDSSH
log_info "✓ 代码部署完成"

# Step 7: 传输数据到新服务器
log_info "步骤 7/9: 传输数据到新服务器..."
scp -r $BACKUP_DIR/data/ $NEW_SERVER:$NEW_PATH/
log_info "✓ 数据传输完成"

# Step 8: 生成配置文件
log_info "步骤 8/9: 生成配置文件..."

# 创建 .env 文件
cat > /tmp/grok2api.env << 'EOF'
LOG_LEVEL=INFO
LOG_FILE_ENABLED=true
DATA_DIR=./data
SERVER_HOST=127.0.0.1
SERVER_PORT=18080
SERVER_WORKERS=3
SERVER_STORAGE_TYPE=local
SERVER_STORAGE_URL=
EOF

scp /tmp/grok2api.env $NEW_SERVER:$NEW_PATH/.env
log_info "✓ .env 文件已创建"

# 创建 systemd service 文件
ssh $NEW_SERVER "cat > /etc/systemd/system/grok2api.service" << 'EOF'
[Unit]
Description=Grok2API Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/grok2api
Environment="PATH=/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/root/.local/bin/uv run granian --interface asgi --host 127.0.0.1 --port 18080 --workers 3 main:app
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=grok2api

[Install]
WantedBy=multi-user.target
EOF

ssh $NEW_SERVER "systemctl daemon-reload && systemctl enable grok2api"
log_info "✓ systemd 服务已配置"

# Step 9: 配置 Nginx
log_info "步骤 9/9: 配置 Nginx 反向代理和 SSL..."

# 创建 Nginx 配置
ssh $NEW_SERVER "cat > /etc/nginx/sites-available/grok2api" << EOF
# Grok2API Nginx 配置
# 域名: $DOMAIN

# HTTP -> HTTPS 重定向
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    # Let's Encrypt ACME 验证
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # 重定向到 HTTPS
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

# HTTPS 服务器配置
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;

    # SSL 证书（稍后由 certbot 自动配置）
    # ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    # SSL 优化配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # 安全头
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # 日志
    access_log /var/log/nginx/grok2api_access.log;
    error_log /var/log/nginx/grok2api_error.log;

    # 客户端上传大小限制（用于图片/视频上传）
    client_max_body_size 100M;

    # 反向代理到 grok2api
    location / {
        proxy_pass http://127.0.0.1:18080;
        proxy_http_version 1.1;
        
        # WebSocket 支持
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # 代理头
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # 超时设置（适配长时间运行的请求，如视频生成）
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
        
        # 缓冲设置
        proxy_buffering off;
        proxy_request_buffering off;
    }

    # 静态文件缓存
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
        proxy_pass http://127.0.0.1:18080;
        expires 7d;
        add_header Cache-Control "public, immutable";
    }
}
EOF

# 启用站点
ssh $NEW_SERVER "ln -sf /etc/nginx/sites-available/grok2api /etc/nginx/sites-enabled/"
ssh $NEW_SERVER "nginx -t && systemctl reload nginx"
log_info "✓ Nginx 配置完成"

# 申请 SSL 证书
log_info "正在申请 SSL 证书..."
read -p "请确认域名 $DOMAIN 已解析到新服务器 IP，然后按回车继续..."

ssh $NEW_SERVER "certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN || true"
log_info "✓ SSL 证书配置完成"

# 启动服务
log_info "启动 grok2api 服务..."
ssh $NEW_SERVER "systemctl start grok2api"
sleep 5
ssh $NEW_SERVER "systemctl status grok2api --no-pager"
log_info "✓ grok2api 服务已启动"

# 完成
echo ""
echo "========================================="
log_info "迁移完成！"
echo "========================================="
echo ""
echo "备份目录: $BACKUP_DIR"
echo "新服务器地址: https://$DOMAIN"
echo ""
echo "后续步骤："
echo "1. 测试新服务器: curl https://$DOMAIN/admin"
echo "2. 检查日志: ssh $NEW_SERVER 'journalctl -u grok2api -f'"
echo "3. 如果测试正常，可以关闭旧服务器"
echo ""
echo "常用命令："
echo "  启动服务: ssh $NEW_SERVER 'systemctl start grok2api'"
echo "  停止服务: ssh $NEW_SERVER 'systemctl stop grok2api'"
echo "  重启服务: ssh $NEW_SERVER 'systemctl restart grok2api'"
echo "  查看日志: ssh $NEW_SERVER 'journalctl -u grok2api -f'"
echo "  查看状态: ssh $NEW_SERVER 'systemctl status grok2api'"
echo ""
