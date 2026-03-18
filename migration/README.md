# Grok2API 服务器迁移文件包

这个目录包含了从旧服务器迁移到新服务器的所有必要文件和脚本。

## 📁 文件清单

### 1. `migrate.sh` - 自动迁移脚本
**完整的自动化迁移脚本，包含所有步骤**

```bash
chmod +x migrate.sh
./migrate.sh
```

**功能:**
- 自动停止旧服务器
- 备份并传输数据
- 安装新服务器依赖
- 部署代码和配置
- 配置 Nginx 和 SSL
- 启动新服务

**适用场景:** 想要一键完成整个迁移过程

---

### 2. `MIGRATION_GUIDE.md` - 详细迁移指南
**完整的手动迁移步骤文档**

```bash
cat MIGRATION_GUIDE.md
# 或在编辑器中打开查看
```

**内容包括:**
- 11 个详细步骤
- 每步的命令和说明
- 验证清单
- 常用管理命令
- 故障排查指南
- 回滚方案

**适用场景:** 需要手动控制每个步骤，或理解迁移过程

---

### 3. `nginx-config.conf` - Nginx 配置文件
**生产环境的 Nginx 反向代理配置**

**位置:** `/etc/nginx/sites-available/grok2api`

**功能:**
- HTTP 到 HTTPS 自动重定向
- SSL/TLS 配置
- WebSocket 支持
- 反向代理到 127.0.0.1:18080
- 静态文件缓存
- 安全头设置
- 大文件上传支持（100MB）

**部署方法:**
```bash
scp nginx-config.conf root@grokapi.ai.org.kg:/etc/nginx/sites-available/grok2api
ssh root@grokapi.ai.org.kg "ln -sf /etc/nginx/sites-available/grok2api /etc/nginx/sites-enabled/"
ssh root@grokapi.ai.org.kg "nginx -t && systemctl reload nginx"
```

---

### 4. `grok2api.service` - Systemd 服务配置
**Linux 系统服务配置文件**

**位置:** `/etc/systemd/system/grok2api.service`

**功能:**
- 自动启动 grok2api
- 服务崩溃自动重启
- 3 workers 配置
- 日志记录到 journald
- 资源限制设置

**部署方法:**
```bash
scp grok2api.service root@grokapi.ai.org.kg:/etc/systemd/system/
ssh root@grokapi.ai.org.kg "systemctl daemon-reload && systemctl enable grok2api && systemctl start grok2api"
```

**管理命令:**
```bash
# 启动
systemctl start grok2api

# 停止
systemctl stop grok2api

# 重启
systemctl restart grok2api

# 查看状态
systemctl status grok2api

# 查看日志
journalctl -u grok2api -f
```

---

### 5. `.env.production` - 环境变量配置
**生产环境的环境变量配置示例**

**位置:** `/opt/grok2api/.env`

**配置项:**
- 日志级别和文件日志
- 服务器地址和端口
- Workers 数量（3）
- 存储类型配置
- 代理配置（可选）

**部署方法:**
```bash
scp .env.production root@grokapi.ai.org.kg:/opt/grok2api/.env
```

---

### 6. `quick-test.sh` - 快速测试脚本
**部署后的快速验证脚本**

```bash
chmod +x quick-test.sh
./quick-test.sh
```

**测试项:**
1. 服务器连接
2. grok2api 服务状态
3. 端口监听（18080）
4. Nginx 状态
5. HTTP 访问
6. HTTPS 访问
7. 管理后台
8. SSL 证书
9. 服务日志
10. 资源使用

**适用场景:** 迁移完成后快速验证所有功能是否正常

---

## 🚀 快速开始

### 方式一：使用自动脚本（推荐）

```bash
cd /Users/jmr/projects/grok2api/migration
./migrate.sh
```

脚本会引导你完成整个迁移过程。

### 方式二：手动迁移

1. 阅读 `MIGRATION_GUIDE.md`
2. 按照步骤 1-11 逐步执行
3. 使用 `quick-test.sh` 验证结果

## 📊 服务器配置

### 旧服务器（api.ai.org.kg）
- 当前 workers: 5
- 端口: 18080
- 数据大小: ~496MB

### 新服务器（grokapi.ai.org.kg）
- CPU: 4 核 Intel Xeon E5-2699 v4
- 内存: 3.83 GB
- 磁盘: 48.29 GB
- 推荐 workers: **3**
- 端口: 18080

### Workers 配置说明

**为什么是 3 workers？**

1. **CPU 限制**: 4 核 - 1（系统预留）= 3 workers
2. **内存限制**: 
   - 总内存: 3.83 GB
   - 系统预留: ~500 MB
   - 每个 worker: 500-800 MB
   - 3 workers = 1.5-2.4 GB
   - 剩余内存: 1-1.8 GB（缓存+系统）

3. **性能预期**:
   - 普通并发: 25-35 请求
   - 峰值并发: 50 左右
   - 响应时间: 1-5 秒（对话）

## 🔧 迁移后配置

### 必做事项

1. **修改配置文件**
   ```bash
   ssh root@grokapi.ai.org.kg "vim /opt/grok2api/data/config.toml"
   ```
   
   需要修改的字段:
   - `app.app_url = "https://grokapi.ai.org.kg"`
   - `app.app_key` - 管理后台密码
   - `app.api_key` - API 调用密钥

2. **添加 Swap（强烈推荐）**
   ```bash
   ssh root@grokapi.ai.org.kg << 'EOF'
   fallocate -l 2G /swapfile
   chmod 600 /swapfile
   mkswap /swapfile
   swapon /swapfile
   echo '/swapfile none swap sw 0 0' >> /etc/fstab
   EOF
   ```

3. **限制缓存大小**
   编辑 `/opt/grok2api/data/config.toml`:
   ```toml
   [cache]
   enable_auto_clean = true
   limit_mb = 256  # 从 512 降到 256
   ```

### 可选优化

1. **使用外部数据库**
   ```env
   SERVER_STORAGE_TYPE=pgsql
   SERVER_STORAGE_URL=postgresql+asyncpg://user:pass@localhost/db
   ```

2. **配置代理**（如果需要）
   ```toml
   [proxy]
   base_proxy_url = "http://127.0.0.1:7897"
   ```

3. **监控设置**
   - 设置 UptimeRobot 或类似服务监控 https://grokapi.ai.org.kg
   - 配置日志轮转（logrotate）
   - 设置磁盘空间告警

## 📝 验证清单

迁移完成后，请验证：

- [ ] 旧服务器已停止
- [ ] 数据已完整传输
- [ ] 新服务器服务运行正常
- [ ] Nginx 配置正确
- [ ] SSL 证书已配置
- [ ] HTTP → HTTPS 重定向工作
- [ ] 管理后台可访问
- [ ] API 接口正常响应
- [ ] Token 数据完整
- [ ] 缓存目录正常
- [ ] 日志正常输出
- [ ] 内存使用正常（< 90%）

## 🆘 获取帮助

如果遇到问题：

1. 查看日志
   ```bash
   ssh root@grokapi.ai.org.kg "journalctl -u grok2api -n 100"
   ```

2. 检查 Nginx 日志
   ```bash
   ssh root@grokapi.ai.org.kg "tail -f /var/log/nginx/grok2api_error.log"
   ```

3. 查看详细的故障排查指南
   ```bash
   cat MIGRATION_GUIDE.md | grep -A 20 "故障排查"
   ```

4. 提交 Issue
   https://github.com/jiangmuran/grok2api_pro/issues

## 📞 联系方式

- GitHub: https://github.com/jiangmuran/grok2api_pro
- Issues: https://github.com/jiangmuran/grok2api_pro/issues
