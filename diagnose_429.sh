#!/bin/bash

echo "=== Grok2API 429错误诊断工具 ==="
echo ""

# 检查最近的429错误
echo "1. 最近10分钟的429错误统计:"
ssh root@grokapi.ai.org.kg "journalctl -u grok2api --since '10 minutes ago' | grep -c '429'"

echo ""
echo "2. 最近的429错误详情:"
ssh root@grokapi.ai.org.kg "journalctl -u grok2api --since '10 minutes ago' | grep '429' | tail -5"

echo ""
echo "3. Token状态检查:"
ssh root@grokapi.ai.org.kg "python3 -c \"
import json
from pathlib import Path
from collections import Counter
from datetime import datetime

data = json.loads(Path('/opt/grok2api/data/token.json').read_text())
tokens = data.get('ssoBasic', [])

print(f'总token数: {len(tokens)}')
print(f'状态: {dict(Counter(t.get(\"status\") for t in tokens))}')
print(f'quota=0的token数: {sum(1 for t in tokens if t.get(\"quota\", 0) == 0)}')
print(f'平均quota: {sum(t.get(\"quota\", 0) for t in tokens) / len(tokens):.2f}')

# 检查最近失败的token
recent_fails = [t for t in tokens if t.get('last_fail_at') and t['last_fail_at'] > datetime.now().timestamp() * 1000 - 600000]
if recent_fails:
    print(f'\\n最近10分钟失败的token数: {len(recent_fails)}')
    fail_reasons = Counter(t.get('last_fail_reason', 'unknown') for t in recent_fails)
    print(f'失败原因分布: {dict(fail_reasons)}')
\""

echo ""
echo "4. 服务状态:"
ssh root@grokapi.ai.org.kg "systemctl status grok2api | grep -E '(Active|Memory|Tasks)'"

echo ""
echo "5. 最近的图片请求:"
ssh root@grokapi.ai.org.kg "journalctl -u grok2api --since '5 minutes ago' | grep -E 'images/(generations|edits|variations)' | wc -l"

echo ""
echo "6. 检查是否有代理配置:"
ssh root@grokapi.ai.org.kg "cat /opt/grok2api/data/config.toml | grep -A 5 '\[proxy\]'"
