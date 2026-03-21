#!/bin/bash

echo "========================================"
echo "Grok2API 快速状态检查"
echo "========================================"
echo ""

# 服务状态
echo "1. 服务状态:"
ssh root@grokapi.ai.org.kg "systemctl is-active grok2api" | while read status; do
    if [ "$status" = "active" ]; then
        echo "   ✓ 服务运行中"
    else
        echo "   ✗ 服务未运行: $status"
    fi
done

# Worker数量
workers=$(ssh root@grokapi.ai.org.kg "ps aux | grep 'granian.*main:app' | grep -v grep | wc -l")
echo "   Workers: $workers 个"

# 内存使用
mem_info=$(ssh root@grokapi.ai.org.kg "free -h | grep Mem")
mem_used=$(echo "$mem_info" | awk '{print $3}')
mem_total=$(echo "$mem_info" | awk '{print $2}')
echo "   内存: $mem_used / $mem_total"

echo ""

# Token池状态
echo "2. Token池状态:"
ssh root@grokapi.ai.org.kg "python3 -c \"
import json
from pathlib import Path
from collections import Counter

data = json.loads(Path('/opt/grok2api/data/token.json').read_text())
tokens = data.get('ssoBasic', [])

total = len(tokens)
status_counter = Counter(t.get('status') for t in tokens)
active = status_counter.get('active', 0)
quotas = [t.get('quota', 0) for t in tokens]
avg_quota = sum(quotas) / len(quotas) if quotas else 0

print(f'   总数: {total}')
print(f'   Active: {active} ({active/total*100:.1f}%)')
print(f'   平均Quota: {avg_quota:.2f}')

if status_counter.get('cooling', 0) > 0:
    print(f'   ⚠ Cooling: {status_counter[\"cooling\"]}')
if status_counter.get('expired', 0) > 0:
    print(f'   ⚠ Expired: {status_counter[\"expired\"]}')
\"" 2>/dev/null || echo "   ✗ 无法读取token池"

echo ""

# 代理状态
echo "3. 代理配置:"
proxy_enabled=$(ssh root@grokapi.ai.org.kg "grep '^enabled' /opt/grok2api/data/config.toml | head -1" | grep -o 'true\|false')
if [ "$proxy_enabled" = "true" ]; then
    echo "   ⚠ 代理已启用"
else
    echo "   ✓ 代理已禁用"
fi

echo ""

# 最近错误
echo "4. 最近错误 (最近5分钟):"
error_count=$(ssh root@grokapi.ai.org.kg "journalctl -u grok2api --since '5 minutes ago' --no-pager | grep -c ERROR" 2>/dev/null || echo "0")
if [ "$error_count" -eq 0 ]; then
    echo "   ✓ 无错误"
else
    echo "   ⚠ $error_count 个错误"
    ssh root@grokapi.ai.org.kg "journalctl -u grok2api --since '5 minutes ago' --no-pager | grep ERROR | tail -3" 2>/dev/null | sed 's/^/     /'
fi

echo ""

# 图片生成状态（简单测试）
echo "5. 快速功能测试:"
echo "   测试API连接..."
api_test=$(curl -s -o /dev/null -w "%{http_code}" https://grokapi.ai.org.kg/v1/models 2>/dev/null || echo "000")
if [ "$api_test" = "200" ]; then
    echo "   ✓ API可访问"
else
    echo "   ✗ API不可访问 (HTTP $api_test)"
fi

echo ""
echo "========================================"
echo "检查完成"
echo "========================================"
