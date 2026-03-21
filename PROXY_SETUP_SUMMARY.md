# 代理配置完成总结

## 日期
2026-03-19

## 问题诊断

### 原始问题
1. **频繁的429错误** - 图片生成失败率高达40%
2. **所有请求直连** - 未配置代理，所有请求从同一IP发出
3. **触发X (Twitter) API速率限制** - 大量并发请求导致IP被限流

### 诊断结果
- 最近10分钟内63个429错误
- 日志显示: `AppChatReverse proxy is empty, request will use direct network`
- Token池健康 (1681个token，平均quota 79.45)
- 问题不在token调度，而在代理配置

## 解决方案

### 1. 代理池配置

配置了**8个SOCKS5代理**用于负载均衡和故障转移：

```toml
[proxy]
base_proxy_url = "socks5://user1:pass1@108.165.165.245:7778,socks5://user2:pass2@154.44.70.66:7778,..."
enabled = true
```

### 2. 代理列表

| # | 代理服务器 | 端口 | 到期日期 |
|---|-----------|------|----------|
| 1 | 108.165.165.245 | 7778 | 2026-04-08 |
| 2 | 154.44.70.66 | 7778 | 2026-04-10 |
| 3 | 113.212.89.207 | 9532 | 2026-04-11 |
| 4 | 147.189.152.7 | 7778 | 2026-04-11 |
| 5 | 154.44.70.181 | 7778 | 2026-04-12 |
| 6 | 23.231.115.173 | 9060 | 未知 |
| 7 | 104.164.72.231 | 7778 | 未知 |
| 8 | 128.254.145.126 | 7778 | 未知 |

### 3. 工作原理

**Sticky代理选择**:
- 每个请求使用当前激活的代理
- 遇到403/429/502错误时自动切换到下一个代理
- 8个代理轮转使用，分散请求压力

**故障转移**:
```python
# 触发代理切换的状态码
_FAILOVER_STATUS_CODES = frozenset({403, 429, 502})
```

## 配置文件更改

### 备份
```bash
/opt/grok2api/data/config.toml.backup.before_proxy_20260319_045456
```

### 主要更改
```diff
[proxy]
- base_proxy_url = ""
+ base_proxy_url = "socks5://...8个代理..."
- enabled = false
+ enabled = true
```

## 验证

### 服务状态
```bash
systemctl status grok2api
# ✅ Active: active (running)
# ✅ Workers: 5个worker进程正常运行
# ✅ Memory: 257MB
```

### 代理启用确认
日志显示:
```
ProxyPool: proxy.base_proxy_url loaded 8 proxies for failover
AppChatReverse proxy enabled: scheme=socks5h, target=socks5h://y3d4k3H7r6o1:***@108.165.165.245:7778
```

## 预期改进

### 之前 (无代理)
- ❌ 429错误率: ~40%
- ❌ 所有请求同一IP
- ❌ 容易触发速率限制
- ❌ 图片生成失败率高

### 之后 (8代理池)
- ✅ 429错误率: 预计降至<5%
- ✅ 请求分散到8个不同IP
- ✅ 单个代理被限流时自动切换
- ✅ 图片生成成功率提升至95%+

## 监控工具

### 1. 实时监控
```bash
./monitor_improvements.sh
```
- 每分钟统计请求成功率
- 追踪429/502错误数量
- 显示代理切换次数

### 2. 诊断工具
```bash
./diagnose_429.sh
```
- 检查429错误统计
- Token状态检查
- 代理配置验证

### 3. 日志查看
```bash
ssh root@grokapi.ai.org.kg "journalctl -u grok2api -f | grep -E '(proxy|429|502)'"
```

## 后续优化建议

### 1. 代理到期提醒
- 最早到期: 2026-04-08 (代理#1)
- 建议提前1周续费或替换

### 2. 代理健康检查
- 定期测试代理连通性
- 自动移除失效代理
- 可考虑添加更多代理增加冗余

### 3. 监控指标
观察1-2小时后的统计数据:
- 429错误是否显著减少
- 代理切换频率是否合理
- 整体成功率是否提升

## 相关文件

- `/opt/grok2api/data/config.toml` - 主配置文件
- `/Users/jmr/Downloads/sub2api-proxy-20260319115840.json` - 原始代理JSON
- `convert_proxies.py` - 代理格式转换工具
- `monitor_improvements.sh` - 监控脚本
- `diagnose_429.sh` - 诊断脚本

## Model Not Found 错误

这是另一个问题，与代理无关。发生在客户端请求了不支持的模型时。

### 支持的模型
需要检查 `/opt/grok2api/app/services/grok/services/model.py` 中的 `MODELS` 列表。

### 常见支持的模型
- grok-3
- grok-3-mini
- grok-3-thinking
- grok-4
- grok-vision-beta
- grok-imagine (图片生成)
- grok-video (视频生成)

客户端需要使用正确的模型名称才能避免此错误。
