#!/bin/bash
# TY1100-NX 一键巡检脚本

echo "=== TY1100-NX 巡检报告 ==="
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "主机: $(hostname)"
echo ""

echo "=== GPU ==="
if command -v ixsmi >/dev/null 2>&1; then
  ixsmi 2>/dev/null | head -25
else
  echo "ixsmi 不可用"
fi
echo ""

echo "=== Docker 容器 ==="
if command -v docker >/dev/null 2>&1; then
  sudo docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" 2>/dev/null || docker ps -a
else
  echo "docker 不可用"
fi
echo ""

echo "=== 8081 推理 API ==="
if curl -s --max-time 30 -o /dev/null -w "HTTP %{http_code} | 耗时 %{time_total}s\n" \
  http://127.0.0.1:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"ping"}],"max_tokens":8,"chat_template_kwargs":{"enable_thinking":false}}' 2>/dev/null; then
  :
else
  echo "8081 API 不可达或超时"
fi
echo ""

echo "=== 内存 ==="
free -h
echo ""

echo "=== 磁盘 (/) ==="
df -h /
echo ""

echo "=== 8090 庭审 Web ==="
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://127.0.0.1:8090/api/health 2>/dev/null || echo "8090 不可达"
echo ""

echo "=== 监听端口 (8081/8090/18789) ==="
ss -tlnp 2>/dev/null | grep -E '8081|8090|18789' || sudo ss -tlnp 2>/dev/null | grep -E '8081|8090|18789' || echo "无相关端口监听"
echo ""

echo "=== 巡检完成 ==="
