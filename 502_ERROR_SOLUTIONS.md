# 502 错误解决方案

## 🔍 问题诊断

根据日志分析，502 错误主要由以下原因导致：

### 1. Token 速率限制 (Rate Limit Exceeded) ⚠️

**症状**:
```
WARNING - WebSocket error: rate_limit_exceeded - Image rate limit exceeded
WARNING - Token eyJ0eXAiOi...: marked as rate limited (quota 80 -> 0, status -> cooling)
```

**原因**:
- 大量 tokens 达到速率限制（每 20 小时 80 次）
- Tokens 进入冷却期（cooling 状态）
- 可用 token 不足导致请求失败

### 2. 并发补偿机制触发

**当前配置**:
```toml
[image]
blocked_parallel_attempts = 5    # 遇到审查时并行补偿 5 次
blocked_parallel_enabled = true   # 启用并行补偿
```

这会在单次图片生成失败时，自动并行重试 5 次，快速消耗 tokens。

---

## 🔧 解决方案

### 方案 1: 优化图片生成配置（推荐）

降低并发和重试次数，减少 token 消耗：

```bash
ssh root@grokapi.ai.org.kg "cat > /tmp/update_image_config.sh" << 'EOF'
#!/bin/bash
CONFIG_FILE="/opt/grok2api/data/config.toml"

# 备份配置
cp $CONFIG_FILE ${CONFIG_FILE}.backup

# 优化图片配置
sed -i 's/blocked_parallel_attempts = 5/blocked_parallel_attempts = 2/' $CONFIG_FILE
sed -i 's/final_timeout = 15/final_timeout = 20/' $CONFIG_FILE

echo "配置已更新:"
grep -A 10 '\[image\]' $CONFIG_FILE
EOF

chmod +x /tmp/update_image_config.sh
/tmp/update_image_config.sh

# 重启服务
systemctl restart grok2api
```

**优化后配置**:
- `blocked_parallel_attempts`: 5 → 2（减少并行重试次数）
- `final_timeout`: 15 → 20（增加等待时间）

---

### 方案 2: 添加更多 Tokens

**检查当前 tokens 状态**:
```bash
ssh root@grokapi.ai.org.kg "journalctl -u grok2api | grep 'TokenManager initialized' | tail -1"
```

**如果 cooling 状态的 tokens 过多**:
1. 访问管理后台: https://grokapi.ai.org.kg/admin
2. 查看 Token 状态
3. 添加更多可用 tokens
4. 或等待 cooling tokens 恢复（通常需要几小时）

---

### 方案 3: 启用代理（如果访问受限）

某些地区访问 Grok WebSocket 可能被限制，需要代理：

```bash
ssh root@grokapi.ai.org.kg "cat >> /opt/grok2api/data/config.toml" << 'EOF'

[proxy]
base_proxy_url = "http://127.0.0.1:7897"  # 你的代理地址
asset_proxy_url = "http://127.0.0.1:7897"
EOF

# 重启服务
ssh root@grokapi.ai.org.kg "systemctl restart grok2api"
```

**需要先在服务器上配置代理服务**（如 v2ray、clash 等）

---

### 方案 4: 调整重试策略

编辑 `/opt/grok2api/data/config.toml`:

```toml
[retry]
max_retry = 2              # 从 3 降到 2
retry_status_codes = [429] # 只对 429 重试，不对 502 重试

[image]
blocked_parallel_enabled = false  # 暂时禁用并行补偿
```

然后重启：
```bash
ssh root@grokapi.ai.org.kg "systemctl restart grok2api"
```

---

## 📊 监控和验证

### 1. 实时监控日志

```bash
# 监控 502 错误
ssh root@grokapi.ai.org.kg "journalctl -u grok2api -f | grep -E '502|rate_limit|cooling'"

# 监控成功请求
ssh root@grokapi.ai.org.kg "journalctl -u grok2api -f | grep -E 'status_code: 200|collected.*final'"
```

### 2. 检查 Token 健康状态

```bash
# 查看最近被标记为 cooling 的 tokens
ssh root@grokapi.ai.org.kg "journalctl -u grok2api --since '1 hour ago' | grep 'cooling' | wc -l"

# 查看 TokenManager 初始化信息
ssh root@grokapi.ai.org.kg "journalctl -u grok2api | grep 'TokenManager initialized' | tail -1"
```

### 3. 验证修复效果

测试图片生成：
```bash
curl -X POST https://grokapi.ai.org.kg/v1/images/generations \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -d '{
    "model": "grok-imagine-1.0",
    "prompt": "a simple test image",
    "n": 1
  }'
```

---

## 🎯 推荐配置（生产环境）

基于 1681 个 tokens 的配置优化：

```toml
[retry]
max_retry = 2
retry_status_codes = [429]  # 只重试 429，不重试 502

[image]
timeout = 60
stream_timeout = 60
final_timeout = 20           # 增加到 20 秒
blocked_parallel_attempts = 2 # 减少到 2 次
blocked_parallel_enabled = true
nsfw = true

[token]
fail_threshold = 3           # 降低失败阈值，快速切换 token
auto_refresh = true
```

---

## ⚠️ 注意事项

1. **不要频繁重试**: 502 错误通常是 token 问题，重试只会加速 token 耗尽
2. **监控 token 池**: 定期检查有多少 tokens 处于 cooling 状态
3. **错峰使用**: 如果可能，避免在高峰时段大量生成图片
4. **考虑代理**: 如果持续 502，可能需要通过代理访问

---

## 🔄 快速修复脚本

```bash
#!/bin/bash
# 一键优化配置

ssh root@grokapi.ai.org.kg << 'ENDSSH'
# 备份配置
cp /opt/grok2api/data/config.toml /opt/grok2api/data/config.toml.backup

# 优化配置
sed -i 's/max_retry = 3/max_retry = 2/' /opt/grok2api/data/config.toml
sed -i 's/blocked_parallel_attempts = 5/blocked_parallel_attempts = 2/' /opt/grok2api/data/config.toml
sed -i 's/final_timeout = 15/final_timeout = 20/' /opt/grok2api/data/config.toml
sed -i 's/fail_threshold = 5/fail_threshold = 3/' /opt/grok2api/data/config.toml

# 重启服务
systemctl restart grok2api

echo "✓ 配置已优化并重启服务"
echo "查看日志: journalctl -u grok2api -f"
ENDSSH
```

保存为 `fix_502.sh`，然后运行：
```bash
chmod +x fix_502.sh
./fix_502.sh
```

---

## 📞 如果问题仍然存在

1. 检查是否有足够的可用 tokens
2. 考虑添加代理配置
3. 查看是否需要刷新 tokens
4. 检查网络连接是否稳定
