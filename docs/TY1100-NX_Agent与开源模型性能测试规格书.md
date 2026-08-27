# TY1100-NX Agent / 开源模型性能测试规格书

> **测试目标：** 在 TY1100-NX 上评测 **Agent 应用** 与 **开源大模型** 的推理性能  
> **适用设备：** TY1100-NX（130 TOPS，显存 32GB / 64GB）  
> **文档版本：** v1.0 · 2026-08-27  
> **参考：** TY1100 产品文档 v2.4.0 · 边端产品方案 v3.0.1

---

## 1. 测试目标

| 维度 | 要测什么 |
|------|----------|
| **Agent** | OpenClaw 等 Agent 框架的启动、对话响应延迟、并发、稳定性 |
| **开源模型** | Qwen 等开源模型在 vLLM 下的吞吐量（TPS）、首 token 延迟（TTFT）、多并发表现 |
| **边界** | 在 NX 显存限制下，哪些模型/量化精度可跑、性能上限在哪 |

**不测的内容（除非项目另行要求）：** YOLO 视觉、多路视频编解码、机器人 SLAM。

---

## 2. 设备与环境前置条件

### 2.1 硬件

| 项目 | 要求 |
|------|------|
| 设备 | TY1100-NX |
| 显存 | 测试前用 `ixsmi` 确认 32GB 或 64GB |
| 网络 | 设备可访问外网（拉镜像、下模型）或模型已离线放到 `/models` |

### 2.2 软件版本（验收门槛）

```bash
cat /etc/iluvatar-release   # 期望 SSD_V_2.4.0
ixsmi                       # 期望 SDK 4.4.0，GPU 正常
docker --version
```

### 2.3 Docker 配置

```bash
sudo tee /etc/docker/daemon.json << 'EOF'
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "insecure-registries": [
    "harbor.iluvatar.com.cn:10443",
    "zibo.harbor.iluvatar.com.cn:30000"
  ]
}
EOF
sudo systemctl restart docker
```

---

## 3. 测试维度与指标定义

### 3.1 核心指标

| 指标 | 英文 | 含义 | 怎么读 |
|------|------|------|--------|
| **首 token 延迟** | TTFT | 发出请求到收到第一个 token 的时间 | 越低越好，影响「反应快不快」 |
| **输出吞吐** | Output TPS | 每秒生成的 token 数 | 越高越好，影响「吐字快不快」 |
| **端到端延迟** | E2E Latency | 请求发起到完整回复结束 | Agent 体验关键指标 |
| **并发能力** | Concurrency | 同时处理的请求数 | 测 1 / 4 / 8 并发等 |
| **显存占用** | VRAM | 模型加载后 GPU 显存使用 | 用 `ixsmi` 观察 |
| **稳定性** | — | 长时间运行是否 OOM / 崩溃 | 连续跑 30min~1h |

### 3.2 测试输入规格（与官方 Benchmark 对齐）

| 参数 | 标准值 | 说明 |
|------|--------|------|
| 输入 tokens | 1024 | 官方 vLLM benchmark 默认 |
| 输出 tokens | 1024 | 同上 |
| 并发 | 1、8 | 官方文档至少测 1 和 8 |
| 精度 | AWQ / W4A8 / GGUF | 按模型支持情况 |

---

## 4. 测试路线 A：开源模型（vLLM）

### 4.1 镜像与容器

```bash
docker pull harbor.iluvatar.com.cn:10443/saas/mr-bi150-4.4.0-aarch64-ubuntu20.04-py3.10-poc-llm-infer:v1.2.5-ty1100-4.4.0

docker run -itd --name vllm --privileged \
  -v /models:/models --shm-size=16g \
  --pid=host --net=host \
  harbor.iluvatar.com.cn:10443/saas/mr-bi150-4.4.0-aarch64-ubuntu20.04-py3.10-poc-llm-infer:v1.2.5-ty1100-4.4.0 bash

docker exec -it vllm bash
```

### 4.2 待测开源模型清单

| 编号 | 模型 | ModelScope | NX 32GB | NX 64GB | 优先级 |
|------|------|------------|---------|---------|--------|
| M-01 | Qwen3.6-27B-AWQ | `tclf90/Qwen3.6-27B-AWQ` | ✅ | ✅ | P0 |
| M-02 | Qwen3.6-35B-A3B-AWQ | `tclf90/Qwen3.6-35B-A3B-AWQ` | ✅ 量化 | ✅ | P0 |
| M-03 | Qwen3.6-35B-A3B-W4A8 | `iluvatar-corex/Qwen3.6-35B-A3B-W4A8` | ✅ | ✅ | P1 |
| M-04 | 其他开源模型 | 按项目选定 | 视显存 | 视显存 | P2 |

**模型下载（容器内或宿主机）：**

```bash
pip install -U modelscope
modelscope download --model tclf90/Qwen3.6-27B-AWQ --local_dir /models/Qwen3.6-27B-AWQ
modelscope download --model tclf90/Qwen3.6-35B-A3B-AWQ --local_dir /models/Qwen3.6-35B-A3B-AWQ
modelscope download --model iluvatar-corex/Qwen3.6-35B-A3B-W4A8 --local_dir /models/Qwen3.6-35B-A3B-W4A8
```

### 4.3 测试步骤（单个模型）

#### Step 1：启动 vLLM Server

**Qwen3.6-27B-AWQ 示例：**

```bash
VLLM_ENFORCE_CUDA_GRAPH=1 \
VLLM_KV_DISABLE_CROSS_GROUP_SHARE=1 \
python3 -m vllm.entrypoints.openai.api_server \
  --model /models/Qwen3.6-27B-AWQ \
  --gpu-memory-utilization 0.9 \
  --max-model-len 8192 \
  --tp 1 \
  --host 0.0.0.0 --port 12345 \
  --enable-auto-tool-choice \
  --tool-call-parser qwen3_coder \
  --trust-remote-code \
  --max-num-seqs 8 \
  --compilation_config '{"cudagraph_mode": "FULL_DECODE_ONLY", "level": 0}'
```

**Qwen3.6-35B-A3B-AWQ：** 同上，改 `--model` 路径。

**Qwen3.6-35B-A3B-W4A8：** 额外加环境变量：

```bash
export VLLM_W8A8_MOE_USE_W4A8=1
```

#### Step 2：Client 端压测

```bash
cd ~/apps/llm-modelzoo/benchmark/vllm

# 单并发
python3 benchmark_serving_tokens.py \
  --model /models/Qwen3.6-27B-AWQ \
  --host 127.0.0.1 --port 12345 \
  --num-prompts 1 \
  --input-tokens 1024 --output-tokens 1024

# 8 并发
python3 benchmark_serving_tokens.py \
  --model /models/Qwen3.6-27B-AWQ \
  --host 127.0.0.1 --port 12345 \
  --num-prompts 8 \
  --input-tokens 1024 --output-tokens 1024
```

#### Step 3：记录指标

测试同时在另一终端执行 `ixsmi` 或 `watch -n 1 ixsmi` 记录显存、GPU 利用率。

### 4.4 官方基准值（TY1100 系列，单并发 1024/1024）

| 模型 | Output TPS | TTFT (ms) | 来源 |
|------|------------|-----------|------|
| Qwen3.6-35B-A3B-AWQ | **30.34** | **942.1** | 官方文档 |
| Qwen3.6-27B-AWQ | **14.67** | **1929.5** | 官方文档 |
| Qwen3.6-35B-A3B-W4A8 | 待测 | 待测 | 文档未给基准 |

**通过建议：** 实测值与官方基准偏差 **≤ ±15%**（可据项目调整）；8 并发需 **记录实测** 作为 NX 能力基线。

### 4.5 vLLM 测试记录表

| 模型 | 并发 | 输入 tok | 输出 tok | TTFT(ms) | Output TPS | 显存(GB) | GPU% | 是否 OOM | 备注 |
|------|------|----------|----------|----------|------------|----------|------|----------|------|
| Qwen3.6-27B-AWQ | 1 | 1024 | 1024 | | | | | | |
| Qwen3.6-27B-AWQ | 8 | 1024 | 1024 | | | | | | |
| Qwen3.6-35B-A3B-AWQ | 1 | 1024 | 1024 | | | | | | |
| Qwen3.6-35B-A3B-AWQ | 8 | 1024 | 1024 | | | | | | |
| Qwen3.6-35B-A3B-W4A8 | 1 | 1024 | 1024 | | | | | | |

---

## 5. 测试路线 B：Agent（OpenClaw）

### 5.1 测什么

Agent 不是纯 LLM benchmark，还要覆盖：

| 编号 | 测试项 | 说明 |
|------|--------|------|
| A-01 | 冷启动时间 | 从 `startup.sh` 到 Web 可访问 |
| A-02 | 单轮对话延迟 | 用户发送到完整回复的时间 |
| A-03 | 多轮对话 | 上下文变长后延迟变化 |
| A-04 | Tool / Skill 调用 | 若启用 tool-call，测调用成功率与额外延迟 |
| A-05 | 并发用户 | 多浏览器/多客户端同时访问 |
| A-06 | 长稳运行 | 连续运行 1h 无崩溃 |

### 5.2 镜像与启动

```bash
docker pull harbor.iluvatar.com.cn:10443/saas/mr-bi150-4.4.0-aarch64-ubuntu20.04-py3.10-app-store-openclaw:v1.0-ty1100-4.4.0

docker run -itd --privileged --shm-size=8g --name openclaw \
  -v /opt/:/opt -p 18789:18789 \
  harbor.iluvatar.com.cn:10443/saas/mr-bi150-4.4.0-aarch64-ubuntu20.04-py3.10-app-store-openclaw:v1.0-ty1100-4.4.0

docker exec -it openclaw bash
```

### 5.3 待测 Agent 模型（NX 推荐）

| 编号 | 模型 | 参数量 | 显存参数 | 多模态 |
|------|------|--------|----------|--------|
| A-M01 | Qwen3.5-9B-GGUF | 9B | 32G | Y |
| A-M02 | Qwen3.6-27B-GGUF | 27B | 32G | Y |
| A-M03 | Qwen3.6-35B-A3B-GGUF | 35B-A3B | 32G | Y |

**启动命令：**

```bash
# 用法: ./startup.sh <模型路径> <参数量> <GPU显存> <是否多模态>
bash ./startup.sh /path/to/Qwen3.5-9B-GGUF/ 9B 32G Y
bash ./startup.sh /path/to/Qwen3.6-27B-GGUF/ 27B 32G Y
```

**访问地址：** `http://<设备IP>:18789/chat?token=Iluvatar1!`

### 5.4 Agent 测试用例

| 编号 | 场景 | 输入示例 | 记录指标 |
|------|------|----------|----------|
| A-T01 | 短问答 | 「你好，介绍一下你自己」 | 首字延迟、总耗时 |
| A-T02 | 长回答 | 「写一份 500 字的技术总结」 | 总耗时、TPS 估算 |
| A-T03 | 代码生成 | 「用 Python 写快速排序」 | 总耗时、正确性（人工） |
| A-T04 | 多轮上下文 | 连续 5 轮追问同一话题 | 每轮延迟是否递增 |
| A-T05 | 知识库（如有） | 上传文档后提问 | 检索+生成总延迟 |
| A-T06 | 稳定性 | 每 30s 发一条，持续 1h | 失败次数、OOM |

### 5.5 Agent 测试记录表

| 模型 | 用例 | 首字延迟(s) | 总耗时(s) | 回复质量(1-5) | 显存(GB) | 异常 |
|------|------|-------------|-----------|---------------|----------|------|
| Qwen3.5-9B | A-T01 | | | | | |
| Qwen3.5-9B | A-T02 | | | | | |
| Qwen3.6-27B | A-T01 | | | | | |
| Qwen3.6-27B | A-T04 | | | | | |

> Agent 官方文档 **未给 TTFT/TPS 基准**，需建立 **NX 实测基线** 写入报告。

---

## 6. 扩展：OpenAI 兼容 API 压测（可选）

vLLM 启动后可按 OpenAI API 格式压测，便于和 Agent 框架对接：

```bash
curl http://127.0.0.1:12345/v1/models

curl http://127.0.0.1:12345/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/models/Qwen3.6-27B-AWQ",
    "messages": [{"role": "user", "content": "你好"}],
    "max_tokens": 256
  }'
```

可用工具：**curl + 计时**、**locust**、官方 `benchmark_serving_tokens.py`。

---

## 7. 推荐测试顺序（TodoList）

```
阶段 0 · 环境
  [ ] SSH 连上 TY1100-NX
  [ ] ixsmi / SSD 版本确认
  [ ] Docker 配置 + 能 pull 镜像
  [ ] 确认显存 32G 或 64G

阶段 1 · 开源模型（vLLM）— 核心
  [ ] 拉 vllm 镜像，下载 Qwen3.6-27B-AWQ
  [ ] 跑 benchmark：并发 1 + 8，记录 TTFT / TPS
  [ ] 下载 Qwen3.6-35B-A3B-AWQ，重复 benchmark
  [ ] （可选）Qwen3.6-35B-A3B-W4A8
  [ ] 与官方基准对比，填记录表

阶段 2 · Agent（OpenClaw）
  [ ] 拉 openclaw 镜像
  [ ] 测 Qwen3.5-9B：冷启动 + A-T01~T04
  [ ] 测 Qwen3.6-27B：同上
  [ ] （可选）35B-A3B
  [ ] 长稳 A-T06

阶段 3 · 报告
  [ ] 汇总：模型 × 并发 × TTFT × TPS 对比表
  [ ] 结论：NX 最适合的模型规格与并发上限
  [ ] 问题清单：OOM、超时、无法加载的模型
```

---

## 8. 报告输出建议

### 8.1 必含图表

1. **模型性能对比柱状图**：横轴模型，纵轴 Output TPS / TTFT  
2. **并发扩展曲线**：1 / 4 / 8 并发下 TPS 变化  
3. **Agent 延迟对比**：9B vs 27B 各场景端到端延迟  
4. **显存占用表**：各模型加载后 VRAM

### 8.2 结论模板

```text
1. TY1100-NX（32GB）在 vLLM 下可稳定运行：<模型列表>
2. 单并发最优吞吐：<模型> @ <TPS> tokens/s
3. 8 并发下性能衰减：<X>%
4. Agent（OpenClaw）推荐部署：<9B/27B>，平均对话延迟 <X>s
5. 不推荐在 NX 上部署：<过大模型>，原因：OOM / 延迟过高
```

---

## 9. 风险与注意事项

| 项 | 说明 |
|----|------|
| 显存 | 32GB 不要强上未量化 35B+ 模型 |
| numpy | 必须 `< 2.0`，否则依赖可能崩 |
| 天数包 | 带 `corex` 的 pip 包勿覆盖 |
| 测试环境 | 尽量固定 `--gpu-memory-utilization 0.9`，便于对比 |
| 散热 | 长时间压测注意温度，`ixsmi` 可看 |
| 网络 | 首次需下载模型，体积大，预留时间 |

---

## 10. 参考命令速查

```bash
# 环境
ixsmi
watch -n 1 ixsmi

# vLLM server（另开终端）
docker exec -it vllm bash

# benchmark
cd ~/apps/llm-modelzoo/benchmark/vllm
python3 benchmark_serving_tokens.py --help

# Agent
docker exec -it openclaw bash
bash ./startup.sh <模型路径> <参数量> 32G Y
```

---

## 11. 文档关联

| 文档 | 路径 |
|------|------|
| 项目操作指南 | `TY1100-NX项目指南.md` |
| 通用硬件测试规格 | `TY1100-NX测试技术规格书.md` |
| 官方镜像说明 | 文档站 `6_image_info.html` |

---

*本文档聚焦 Agent 与开源模型性能测试；视觉/YOLO/视频类测试见通用技术规格书。*
