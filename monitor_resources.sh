#!/bin/bash

echo "=== 服务器资源监控（8 Workers）==="
echo ""

echo "按Ctrl+C停止监控"
echo ""
echo "时间     | CPU负载    | 内存使用      | Swap使用   | Worker进程数 | 活跃连接"
echo "---------|-----------|---------------|------------|-------------|----------"

while true; do
    # 获取系统信息
    timestamp=$(date '+%H:%M:%S')
    
    # CPU负载 (1分钟平均)
    load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    load_remote=$(ssh root@grokapi.ai.org.kg "uptime" | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    
    # 内存使用
    mem_info=$(ssh root@grokapi.ai.org.kg "free -h | grep Mem")
    mem_used=$(echo "$mem_info" | awk '{print $3}')
    mem_total=$(echo "$mem_info" | awk '{print $2}')
    mem_percent=$(ssh root@grokapi.ai.org.kg "free | grep Mem" | awk '{printf \"%.1f\", $3/$2 * 100}')
    
    # Swap使用
    swap_info=$(ssh root@grokapi.ai.org.kg "free -h | grep Swap")
    swap_used=$(echo "$swap_info" | awk '{print $3}')
    
    # Worker进程数
    worker_count=$(ssh root@grokapi.ai.org.kg "ps aux | grep 'granian.*main:app' | grep -v grep | wc -l")
    
    # 活跃连接数（nginx）
    active_conn=$(ssh root@grokapi.ai.org.kg "netstat -an | grep ':18080' | grep ESTABLISHED | wc -l" 2>/dev/null || echo "0")
    
    printf "%-8s | %-9s | %-6s/%-6s (%3.0f%%) | %-10s | %-11s | %-8s\n" \
        "$timestamp" \
        "$load_remote" \
        "$mem_used" \
        "$mem_total" \
        "$mem_percent" \
        "$swap_used" \
        "$worker_count" \
        "$active_conn"
    
    sleep 5
done
