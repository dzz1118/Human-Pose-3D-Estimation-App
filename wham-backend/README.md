# NeuroMotion Backend — 启动指南

## 环境概览

| 组件 | 位置 |
|---|---|
| 后端 (FastAPI + WHAM) | WSL2 — Ubuntu 24.04 |
| 前端 (React / Vue / …) | Windows 物理机 `E:\Capstone_app` |
| 后端监听地址 | `0.0.0.0:8000` |
| 前端访问后端的 Base URL | `http://localhost:8000` |

---

## WSL2 网络说明

### 当前模式：NAT（默认）

WSL2 默认使用 NAT 网络。Windows 11 内置了自动 loopback 代理，
因此 **Windows 侧浏览器/前端直接用 `localhost:8000` 即可访问 WSL2 内的服务**，
无需配置端口转发。

> **必须条件**：uvicorn 绑定 `0.0.0.0`，而不是 `127.0.0.1`。
> 绑定 `127.0.0.1` 只监听 WSL 内部回环，Windows 无法穿透。

### 可选升级：Mirrored 网络模式（推荐）

你的环境（WSL 2.6.3 + Windows 11 26200）完整支持 Mirrored 模式。
启用后 WSL2 和 Windows 共享同一网络栈，行为更接近原生 Linux，
不再依赖代理转发，也不会因 WSL IP 变化导致访问失败。

**启用方式**（在 Windows PowerShell 中执行）：

```powershell
# 创建或追加 %USERPROFILE%\.wslconfig
Add-Content "$env:USERPROFILE\.wslconfig" "`n[wsl2]`nnetworkingMode=mirrored"

# 重启 WSL 使配置生效
wsl --shutdown
```

启用后前端 Base URL 不变，仍为 `http://localhost:8000`。

---

## 安装依赖

```bash
# 在 WSL 终端中执行
cd /home/dz/WHAM

# 激活你的 conda/venv 环境（WHAM 已有的环境）
conda activate wham   # 或 source venv/bin/activate

# 安装后端额外依赖
pip install -r backend/requirements.txt
```

---

## 启动后端

```bash
cd /home/dz/WHAM

uvicorn backend.main:app \
    --host 0.0.0.0 \
    --port 8000 \
    --reload
```

| 参数 | 说明 |
|---|---|
| `--host 0.0.0.0` | 监听所有网卡，Windows 侧才能访问 |
| `--port 8000` | 固定端口，与前端 Base URL 一致 |
| `--reload` | 开发模式，代码修改后自动重启；生产环境去掉此参数 |

> **注意**：首次启动时 WHAM 会加载模型权重（约 1–2 分钟），
> 期间 `/health` 会返回 `"model_ready": false`，等待变为 `true` 后再发请求。

### 验证服务正常

在 Windows 浏览器或 PowerShell 中：

```powershell
# 浏览器直接打开
http://localhost:8000/health

# 或 PowerShell
Invoke-RestMethod http://localhost:8000/health
```

期望返回：

```json
{
  "status": "ok",
  "model_ready": true,
  "device": "cuda",
  "gpu": { "name": "...", "memory_total": "... GB", "memory_used": "... GB" }
}
```

---

## 前端配置

在 `E:\Capstone_app` 的前端项目中，将 API Base URL 设置为：

```
http://localhost:8000
```

### 示例（React / Vite）

在 `.env.development` 中：

```env
VITE_API_BASE_URL=http://localhost:8000
```

使用时：

```js
const API = import.meta.env.VITE_API_BASE_URL;

// 上传视频
const form = new FormData();
form.append("file", videoFile);
const { job_id } = await fetch(`${API}/process_video`, {
    method: "POST",
    body: form,
}).then(r => r.json());

// 轮询状态
const poll = setInterval(async () => {
    const status = await fetch(`${API}/status/${job_id}`).then(r => r.json());
    if (status.status === "done") {
        clearInterval(poll);
        // 访问解析结果
        const results = await fetch(`${API}/results/${job_id}`).then(r => r.json());
        // 访问渲染视频
        const videoUrl = `${API}${status.video_url}`;  // e.g. /files/{job_id}/output.mp4
    }
}, 3000);
```

---

## API 接口速查

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/health` | 服务存活探针 + GPU 状态 |
| POST | `/process_video` | 上传 MP4，返回 `job_id` |
| GET | `/status/{job_id}` | 轮询任务状态 |
| GET | `/results/{job_id}` | 获取完整 JSON 解析结果（仅 done） |
| GET | `/files/{job_id}/output.mp4` | 渲染后的视频（静态文件） |
| GET | `/docs` | Swagger 自动文档 |

---

## 常见问题

**Windows 侧访问 `localhost:8000` 超时**

1. 确认 uvicorn 绑定的是 `0.0.0.0`，不是 `127.0.0.1`
2. 检查 Windows 防火墙是否拦截了 8000 端口：
   ```powershell
   netsh advfirewall firewall add rule name="WSL2 Backend 8000" `
       dir=in action=allow protocol=TCP localport=8000
   ```
3. 若仍有问题，改用 WSL2 的实际 IP（每次重启会变）：
   ```bash
   # 在 WSL 中查询当前 IP
   ip addr show eth0 | grep "inet " | awk '{print $2}' | cut -d/ -f1
   ```

**CUDA Out of Memory**

后端会返回具体的错误信息和当前显存占用。
缓解方式：上传更短的视频片段，或先关闭其他占用 GPU 的进程。

**模型一直显示 `model_ready: false`**

查看 uvicorn 终端输出，通常是 checkpoint 路径缺失或 CUDA 初始化失败。
确认 `checkpoints/wham_vit_bedlam_w_3dpw.pth.tar` 文件存在。
