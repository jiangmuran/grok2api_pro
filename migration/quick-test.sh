#!/bin/bash
# 快速测试新服务器部署

NEW_SERVER="root@grokapi.ai.org.kg"
DOMAIN="grokapi.ai.org.kg"

echo "========================================="
echo "Grok2API 新服务器测试"
echo "========================================="
echo ""

# 颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

test_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

test_fail() {
    echo -e "${RED}✗${NC} $1"
}

test_warn() {
    echo -e "${YELLOW}!${NC} $1"
}

# 1. 测试服务器连接
echo "1. 测试服务器连接..."
if ssh -o ConnectTimeout=5 $NEW_SERVER "echo 'OK'" &>/dev/null; then
    test_pass "服务器连接正常"
else
    test_fail "无法连接到服务器"
    exit 1
fi

# 2. 测试服务状态
echo ""
echo "2. 测试 grok2api 服务状态..."
if ssh $NEW_SERVER "systemctl is-active grok2api" | grep -q "active"; then
    test_pass "grok2api 服务运行中"
else
    test_fail "grok2api 服务未运行"
    ssh $NEW_SERVER "systemctl status grok2api --no-pager"
fi

# 3. 测试端口监听
echo ""
echo "3. 测试端口监听..."
if ssh $NEW_SERVER "netstat -tln | grep ':18080'" &>/dev/null; then
    test_pass "端口 18080 正常监听"
else
    test_fail "端口 18080 未监听"
fi

# 4. 测试 Nginx
echo ""
echo "4. 测试 Nginx..."
if ssh $NEW_SERVER "systemctl is-active nginx" | grep -q "active"; then
    test_pass "Nginx 运行中"
else
    test_fail "Nginx 未运行"
fi

# 5. 测试 HTTP 访问
echo ""
echo "5. 测试 HTTP 访问..."
if curl -s -o /dev/null -w "%{http_code}" http://$DOMAIN | grep -q "301\|200"; then
    test_pass "HTTP 访问正常（应该重定向到 HTTPS）"
else
    test_warn "HTTP 访问异常"
fi

# 6. 测试 HTTPS 访问
echo ""
echo "6. 测试 HTTPS 访问..."
if curl -k -s -o /dev/null -w "%{http_code}" https://$DOMAIN | grep -q "200"; then
    test_pass "HTTPS 访问正常"
else
    test_fail "HTTPS 访问失败"
fi

# 7. 测试管理后台
echo ""
echo "7. 测试管理后台..."
if curl -k -s https://$DOMAIN/admin | grep -q "Grok2API\|grok"; then
    test_pass "管理后台可访问"
else
    test_warn "管理后台访问异常"
fi

# 8. 检查 SSL 证书
echo ""
echo "8. 检查 SSL 证书..."
if ssh $NEW_SERVER "test -f /etc/letsencrypt/live/$DOMAIN/fullchain.pem"; then
    test_pass "SSL 证书已安装"
    ssh $NEW_SERVER "certbot certificates | grep -A 3 '$DOMAIN'" || true
else
    test_warn "SSL 证书未找到"
fi

# 9. 检查日志
echo ""
echo "9. 最近日志（最后 10 行）..."
ssh $NEW_SERVER "journalctl -u grok2api -n 10 --no-pager"

# 10. 检查资源使用
echo ""
echo "10. 资源使用情况..."
ssh $NEW_SERVER "free -h && echo '---' && ps aux | grep granian | grep -v grep"

echo ""
echo "========================================="
echo "测试完成"
echo "========================================="
echo ""
echo "访问地址: https://$DOMAIN"
echo "管理后台: https://$DOMAIN/admin"
echo ""
