#!/usr/bin/env python3
"""将sub2api代理JSON转换为grok2api配置格式"""

import json
import sys
from pathlib import Path

def convert_proxies(json_file: str) -> str:
    """
    将sub2api的代理JSON转换为逗号分隔的代理URL列表
    
    格式: protocol://username:password@host:port
    """
    with open(json_file, 'r') as f:
        data = json.load(f)
    
    proxies = data.get('proxies', [])
    active_proxies = [p for p in proxies if p.get('status') == 'active']
    
    proxy_urls = []
    for proxy in active_proxies:
        protocol = proxy.get('protocol', 'socks5')
        host = proxy.get('host')
        port = proxy.get('port')
        username = proxy.get('username', '')
        password = proxy.get('password', '')
        
        if not host or not port:
            continue
        
        # 构建代理URL
        if username and password:
            proxy_url = f"{protocol}://{username}:{password}@{host}:{port}"
        else:
            proxy_url = f"{protocol}://{host}:{port}"
        
        proxy_urls.append(proxy_url)
    
    return ','.join(proxy_urls)

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <proxy-json-file>")
        sys.exit(1)
    
    json_file = sys.argv[1]
    if not Path(json_file).exists():
        print(f"Error: File not found: {json_file}")
        sys.exit(1)
    
    proxy_list = convert_proxies(json_file)
    
    print("=== 代理配置 ===")
    print(f"总代理数: {len(proxy_list.split(','))}")
    print("\n逗号分隔的代理列表 (用于config.toml):")
    print(proxy_list)
    
    print("\n\n=== 格式化输出 (方便阅读) ===")
    for i, proxy in enumerate(proxy_list.split(','), 1):
        # 隐藏密码显示
        if '@' in proxy:
            protocol, rest = proxy.split('://', 1)
            auth, location = rest.split('@', 1)
            username = auth.split(':', 1)[0]
            print(f"{i}. {protocol}://{username}:***@{location}")
        else:
            print(f"{i}. {proxy}")
