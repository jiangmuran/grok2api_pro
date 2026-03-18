# Grok2API 服务器迁移指南

从 `api.ai.org.kg` 迁移到 `grokapi.ai.org.kg`

## 📋 迁移概况

- **旧服务器**: root@api.ai.org.kg
- **新服务器**: root@grokapi.ai.org.kg  
- **域名**: grokapi.ai.org.kg
- **服务路径**: /opt/grok2api
- **数据大小**: ~496MB
- **当前配置**: 5 workers → **新配置**: 3 workers（适配 4核/3.83GB 配置）

## 🚀 快速迁移（自动脚本）

```bash
cd /Users/jmr/projects/grok2api/migration
chmod +x migrate.sh
./migrate.sh
```

## 📝 手动迁移步骤

### 步骤 1: 准备工作

```bash
# 1.1 检查旧服务器连接
ssh root@api.ai.org.kg "hostname && uptime"

# 1.2 检查新服务器连接  
ssh root@grokapi.ai.org.kg "hostname && uptime"

# 1.3 创建本地备份目录
mkdir -p ~/grok2api_backup_$(date +%Y%m%d)
cd ~/grok2api_backup_$(date +%Y%m%d)
```

### 步骤 2: 停止旧服务器

```bash
# 2.1 检查当前运行状态
ssh root@api.ai.org.kg "ps aux | grep granian | grep grok2api"

# 2.2 停止服务
ssh root@api.ai.org.kg "pkill -f 'granian.*grok2api'"

# 2.3 确认已停止
ssh root@api.ai.org.kg "ps aux | grep granian | grep grok2api"
```

### 步骤 3: 备份数据

```bash
# 3.1 备份 data 目录（约 496MB）
scp -r root@api.ai.org.kg:/opt/grok2api/data/ ./

# 3.2 备份配置文件
scp root@api.ai.org.kg:/opt/grok2api/data/config.toml ./config.toml.backup

# 3.3 检查备份
ls -lh
du -sh data/
```

### 步骤 4: 安装新服务器依赖

```bash
# 4.1 更新系统并安装基础工具
ssh root@grokapi.ai.org.kg << 'EOF'
apt update && apt upgrade -y
apt install -y curl wget git nginx certbot python3-certbot-nginx build-essential
EOF

# 4.2 安装 uv（Python 包管理器）
ssh root@grokapi.ai.org.kg << 'EOF'
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.bashrc
uv --version
EOF
```

### 步骤 5: 部署代码

```bash
# 5.1 克隆项目
ssh root@grokapi.ai.org.kg << 'EOF'
mkdir -p /opt/grok2api
cd /opt/grok2api
git clone https://github.com/jiangmuran/grok2api_pro.git .
EOF

# 5.2 安装依赖
ssh root@grokapi.ai.org.kg << 'EOF'
cd /opt/grok2api
export PATH="$HOME/.local/bin:$PATH"
uv sync
EOF
```

### 步骤 6: 传输数据

```bash
# 6.1 传输 data 目录
scp -r ./data/ root@grokapi.ai.org.kg:/opt/grok2api/

# 6.2 验证数据
ssh root@grokapi.ai.org.kg "ls -lh /opt/grok2api/data/ && du -sh /opt/grok2api/data/"
```

### 步骤 7: 配置环境变量

```bash
# 7.1 创建 .env 文件
ssh root@grokapi.ai.org.kg "cat > /opt/grok2api/.env" << 'EOF'
LOG_LEVEL=INFO
LOG_FILE_ENABLED=true
DATA_DIR=./data
SERVER_HOST=127.0.0.1
SERVER_PORT=18080
SERVER_WORKERS=3
SERVER_STORAGE_TYPE=local
SERVER_STORAGE_URL=
EOF

# 7.2 验证配置
ssh root@grokapi.ai.org.kg "cat /opt/grok2api/.env"
```

### 步骤 8: 配置 Systemd 服务

```bash
# 8.1 创建 service 文件
scp grok2api.service root@grokapi.ai.org.kg:/etc/systemd/system/

# 8.2 启用并启动服务
ssh root@grokapi.ai.org.kg << 'EOF'
systemctl daemon-reload
systemctl enable grok2api
systemctl start grok2api
systemctl status grok2api
EOF
```

### 步骤 9: 配置 Nginx

```bash
# 9.1 上传 Nginx 配置
scp nginx-config.conf root@grokapi.ai.org.kg:/etc/nginx/sites-available/grok2api

# 9.2 启用站点
ssh root@grokapi.ai.org.kg << 'EOF'
ln -sf /etc/nginx/sites-available/grok2api /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx
EOF
```

### 步骤 10: 配置 SSL 证书

```bash
# 10.1 确认域名已解析到新服务器
# 检查 DNS: dig grokapi.ai.org.kg

# 10.2 申请 SSL 证书
ssh root@grokapi.ai.org.kg << 'EOF'
certbot --nginx -d grokapi.ai.org.kg --non-interactive --agree-tos --email admin@ai.org.kg
EOF

# 10.3 测试证书自动续期
ssh root@grokapi.ai.org.kg "certbot renew --dry-run"
```

### 步骤 11: 测试服务

```bash
# 11.1 检查服务状态
ssh root@grokapi.ai.org.kg "systemctl status grok2api"

# 11.2 检查端口监听
ssh root@grokapi.ai.org.kg "netstat -tlnp | grep 18080"

# 11.3 测试 HTTP 访问
curl http://grokapi.ai.org.kg

# 11.4 测试 HTTPS 访问
curl https://grokapi.ai.org.kg/admin

# 11.5 查看日志
ssh root@grokapi.ai.org.kg "journalctl -u grok2api -n 50 --no-pager"
```

## 🔍 验证清单

- [ ] 旧服务器服务已停止
- [ ] 数据已完整备份（496MB）
- [ ] 新服务器依赖已安装（uv, nginx, certbot）
- [ ] 代码已部署到 /opt/grok2api
- [ ] data 目录已传输
- [ ] .env 配置文件已创建
- [ ] systemd 服务已配置并运行
- [ ] Nginx 反向代理已配置
- [ ] SSL 证书已申请并配置
- [ ] HTTP 自动跳转 HTTPS
- [ ] 管理后台可访问
- [ ] API 接口正常响应

## 🛠️ 常用命令

### 服务管理

```bash
# 启动服务
ssh root@grokapi.ai.org.kg "systemctl start grok2api"

# 停止服务
ssh root@grokapi.ai.org.kg "systemctl stop grok2api"

# 重启服务
ssh root@grokapi.ai.org.kg "systemctl restart grok2api"

# 查看状态
ssh root@grokapi.ai.org.kg "systemctl status grok2api"

# 查看日志
ssh root@grokapi.ai.org.kg "journalctl -u grok2api -f"

# 查看最近 100 行日志
ssh root@grokapi.ai.org.kg "journalctl -u grok2api -n 100"
```

### Nginx 管理

```bash
# 测试配置
ssh root@grokapi.ai.org.kg "nginx -t"

# 重载配置
ssh root@grokapi.ai.org.kg "systemctl reload nginx"

# 重启 Nginx
ssh root@grokapi.ai.org.kg "systemctl restart nginx"

# 查看错误日志
ssh root@grokapi.ai.org.kg "tail -f /var/log/nginx/grok2api_error.log"

# 查看访问日志
ssh root@grokapi.ai.org.kg "tail -f /var/log/nginx/grok2api_access.log"
```

### 监控命令

```bash
# 查看内存使用
ssh root@grokapi.ai.org.kg "free -h"

# 查看进程
ssh root@grokapi.ai.org.kg "ps aux | grep granian"

# 查看网络连接
ssh root@grokapi.ai.org.kg "netstat -an | grep :18080"

# 查看系统负载
ssh root@grokapi.ai.org.kg "uptime"

# 实时监控（需要 htop）
ssh root@grokapi.ai.org.kg "htop"
```

## 📊 性能配置说明

### Workers 配置（3 workers）

基于新服务器配置（4核 CPU，3.83GB 内存）：

- **CPU**: 4 核心，留 1 核给系统 → 3 workers
- **内存**: 3.83 GB，每个 worker 约占 500-800MB
- **预期并发**: 25-35 并发请求
- **峰值并发**: 50 左右（不建议长时间维持）

### 性能优化建议

1. **添加 Swap（推荐）**
   ```bash
   ssh root@grokapi.ai.org.kg << 'EOF'
   fallocate -l 2G /swapfile
   chmod 600 /swapfile
   mkswap /swapfile
   swapon /swapfile
   echo '/swapfile none swap sw 0 0' >> /etc/fstab
   EOF
   ```

2. **限制缓存大小**
   编辑 `/opt/grok2api/data/config.toml`:
   ```toml
   [cache]
   enable_auto_clean = true
   limit_mb = 256
   ```

3. **使用外部数据库（可选）**
   对于高负载场景，建议使用 PostgreSQL 或 Redis：
   ```env
   SERVER_STORAGE_TYPE=pgsql
   SERVER_STORAGE_URL=postgresql+asyncpg://user:pass@localhost/grok2api
   ```

## ⚠️ 故障排查

### 服务无法启动

```bash
# 查看详细错误
ssh root@grokapi.ai.org.kg "journalctl -u grok2api -xe"

# 检查端口占用
ssh root@grokapi.ai.org.kg "lsof -i :18080"

# 手动测试启动
ssh root@grokapi.ai.org.kg "cd /opt/grok2api && /root/.local/bin/uv run granian --interface asgi --host 127.0.0.1 --port 18080 --workers 3 main:app"
```

### SSL 证书问题

```bash
# 重新申请证书
ssh root@grokapi.ai.org.kg "certbot --nginx -d grokapi.ai.org.kg --force-renewal"

# 查看证书信息
ssh root@grokapi.ai.org.kg "certbot certificates"
```

### 内存不足

```bash
# 检查内存
ssh root@grokapi.ai.org.kg "free -h && ps aux --sort=-%mem | head -10"

# 减少 workers
ssh root@grokapi.ai.org.kg "sed -i 's/--workers 3/--workers 2/' /etc/systemd/system/grok2api.service"
ssh root@grokapi.ai.org.kg "systemctl daemon-reload && systemctl restart grok2api"
```

## 🔄 回滚方案

如果新服务器出现问题，可以快速回滚到旧服务器：

```bash
# 1. 启动旧服务器
ssh root@api.ai.org.kg << 'EOF'
cd /opt/grok2api
screen -dmS grok bash -c '/opt/grok2api/.venv/bin/granian --interface asgi --host 127.0.0.1 --port 18080 --workers 5 main:app'
EOF

# 2. 验证旧服务器
curl http://api.ai.org.kg/admin

# 3. 修改 DNS 指向旧服务器（如果已切换）
```

## 📞 支持

如遇问题，请查看：
- 项目文档: https://github.com/jiangmuran/grok2api_pro
- Issue: https://github.com/jiangmuran/grok2api_pro/issues
