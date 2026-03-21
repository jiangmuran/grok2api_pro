#!/bin/bash

echo "=== Grok2API 代理效果监控 ==="
echo "开始时间: $(date)"
echo ""

echo "代理配置检查:"
ssh root@grokapi.ai.org.kg "cat /opt/grok2api/data/config.toml | grep -A 2 '\[proxy\]' | grep -E '(base_proxy_url|enabled)'"

echo ""
echo "正在监控10分钟内的请求情况..."
echo "按Ctrl+C停止监控"
echo ""

# 计数器
total_requests=0
successful_requests=0
error_429=0
error_502=0
proxy_rotations=0

echo "时间               | 总请求 | 成功 | 429错误 | 502错误 | 代理切换"
echo "-------------------|--------|------|---------|---------|----------"

start_time=$(date +%s)

while true; do
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    
    # 获取最近1分钟的统计
    stats=$(ssh root@grokapi.ai.org.kg "journalctl -u grok2api --since '1 minute ago' --no-pager" 2>/dev/null)
    
    # 统计各种情况
    total=$(echo "$stats" | grep -c "Request: POST" || echo 0)
    success=$(echo "$stats" | grep -c "Response:.*200" || echo 0)
    err429=$(echo "$stats" | grep -c "429" || echo 0)
    err502=$(echo "$stats" | grep -c "502" || echo 0)
    rotations=$(echo "$stats" | grep -c "ProxyPool: rotate" || echo 0)
    
    # 累计
    total_requests=$((total_requests + total))
    successful_requests=$((successful_requests + success))
    error_429=$((error_429 + err429))
    error_502=$((error_502 + err502))
    proxy_rotations=$((proxy_rotations + rotations))
    
    # 计算成功率
    if [ $total_requests -gt 0 ]; then
        success_rate=$((successful_requests * 100 / total_requests))
    else
        success_rate=0
    fi
    
    printf "%-18s | %-6d | %-4d | %-7d | %-7d | %-8d | 成功率: %d%%\n" \
        "$(date '+%H:%M:%S')" \
        $total_requests \
        $successful_requests \
        $error_429 \
        $error_502 \
        $proxy_rotations \
        $success_rate
    
    sleep 60
    
    # 每5分钟显示一次当前使用的代理
    if [ $((elapsed % 300)) -lt 60 ]; then
        echo ""
        echo "当前代理池状态:"
        ssh root@grokapi.ai.org.kg "journalctl -u grok2api --since '1 minute ago' --no-pager | grep 'proxy enabled' | tail -1" 2>/dev/null
        echo ""
    fi
done
