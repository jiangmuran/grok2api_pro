#!/bin/bash

echo "=== Token 使用分布监控 ==="
echo ""

echo "1. Token quota 分布："
ssh root@grokapi.ai.org.kg "python3 -c \"
import json
from pathlib import Path
from collections import Counter

data = json.loads(Path('/opt/grok2api/data/token.json').read_text())
tokens = data.get('ssoBasic', [])

quota_dist = Counter(t.get('quota', 0) for t in tokens)
print('Quota值 | 数量')
print('--------|------')
for quota in sorted(quota_dist.keys(), reverse=True):
    print(f'{quota:6d}  | {quota_dist[quota]}')

print(f'\\n总token数: {len(tokens)}')
print(f'最高quota: {max(t.get(\"quota\", 0) for t in tokens)}')
print(f'quota=80的token数: {sum(1 for t in tokens if t.get(\"quota\") == 80)}')
\""

echo ""
echo "2. 最近使用的token（通过last_used_at）："
ssh root@grokapi.ai.org.kg "python3 -c \"
import json
from pathlib import Path
from datetime import datetime, timedelta
from collections import Counter

data = json.loads(Path('/opt/grok2api/data/token.json').read_text())
tokens = data.get('ssoBasic', [])

now_ms = int(datetime.now().timestamp() * 1000)
five_min_ago = now_ms - 5 * 60 * 1000

recent_tokens = [
    t for t in tokens 
    if t.get('last_used_at') and t['last_used_at'] > five_min_ago
]

print(f'最近5分钟使用过的token数: {len(recent_tokens)}')
print(f'总token数: {len(tokens)}')
print(f'使用率: {len(recent_tokens) / len(tokens) * 100:.1f}%')

if recent_tokens:
    use_counts = [t.get('use_count', 0) for t in recent_tokens]
    print(f'\\n这些token的use_count统计:')
    print(f'  最小: {min(use_counts)}')
    print(f'  最大: {max(use_counts)}')
    print(f'  平均: {sum(use_counts) / len(use_counts):.1f}')
    
    # 显示前10个最近使用的token
    recent_sorted = sorted(recent_tokens, key=lambda t: t.get('last_used_at', 0), reverse=True)[:10]
    print(f'\\n最近使用的10个token:')
    print('Token前缀    | Quota | Use Count | 最后使用时间')
    print('-------------|-------|-----------|-------------')
    for t in recent_sorted:
        token_prefix = t['token'][:12] + '...'
        quota = t.get('quota', 0)
        use_count = t.get('use_count', 0)
        last_used = datetime.fromtimestamp(t.get('last_used_at', 0) / 1000).strftime('%H:%M:%S')
        print(f'{token_prefix} | {quota:5d} | {use_count:9d} | {last_used}')
\""

echo ""
echo "3. 监控实时请求（按Ctrl+C停止）："
echo "观察是否所有请求都用同一个token..."
ssh root@grokapi.ai.org.kg "timeout 30 journalctl -u grok2api -f --no-pager 2>&1 | grep -E 'TokenManager initialized|consumed.*quota'" || true
