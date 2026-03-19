#!/bin/bash
# 502 错误监控脚本

SERVER="root@grokapi.ai.org.kg"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "========================================="
echo "Grok2API 502 错误监控"
echo "========================================="
echo ""

# 1. 最近 5 分钟的 502 错误统计
echo -e "${YELLOW}=== 最近 5 分钟 502 错误统计 ===${NC}"
ssh $SERVER "journalctl -u grok2api --since '5 min ago' | grep -c '502'"
echo ""

# 2. 最近的 rate_limit 错误
echo -e "${YELLOW}=== 最近 10 条 Rate Limit 错误 ===${NC}"
ssh $SERVER "journalctl -u grok2api --since '10 min ago' | grep 'rate_limit' | tail -10"
echo ""

# 3. Cooling 状态的 tokens
echo -e "${YELLOW}=== 最近被标记为 Cooling 的 Tokens ===${NC}"
ssh $SERVER "journalctl -u grok2api --since '10 min ago' | grep -c 'cooling'"
echo "个 tokens 进入冷却"
echo ""

# 4. 成功的请求
echo -e "${YELLOW}=== 最近 5 分钟成功的图片请求 ===${NC}"
ssh $SERVER "journalctl -u grok2api --since '5 min ago' | grep -E 'collected.*final|status_code: 200.*image' | tail -5"
echo ""

# 5. 当前服务状态
echo -e "${YELLOW}=== 服务状态 ===${NC}"
ssh $SERVER "systemctl is-active grok2api && echo -e '${GREEN}✓ Service Running${NC}' || echo -e '${RED}✗ Service Down${NC}'"
echo ""

# 6. 实时监控选项
echo "========================================="
echo "实时监控命令:"
echo ""
echo "监控所有错误:"
echo "  ssh $SERVER 'journalctl -u grok2api -f | grep -E \"502|rate_limit|cooling\"'"
echo ""
echo "监控成功请求:"
echo "  ssh $SERVER 'journalctl -u grok2api -f | grep -E \"status.*200|collected.*final\"'"
echo ""
echo "查看配置:"
echo "  ssh $SERVER 'cat /opt/grok2api/data/config.toml | grep -A 10 \"\\[image\\]\"'"
echo ""
