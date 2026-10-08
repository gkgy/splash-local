**简体中文** | [English](README.en.md)

# Splash Local

为 Apple Silicon Mac 制作的原生 Splash 桌面应用，使用 Cocoa + WKWebView 连接本机 Splash 服务。独立运行，不依赖 Bionic。本项目是个人制作的客户端，并非 Inco AI 官方应用。

## 功能

- 本地流式聊天、多对话历史、取消生成、JSON 聊天导出。
- 原生服务状态面板、启动/停止服务、查看日志。
- 输出速度、输出 token 数、首字等待统计；生成中为估算，完成后使用服务端统计。
- Thinking 切换、temperature / top_p / top_k / max_tokens / 系统提示词。
- GPU 内存、上下文、磁盘缓存和 KV 精度设置。
- 共享服务思考策略：普通入口、固定关闭思考和固定低思考模型别名。

## 构建与打开

要求 macOS 14 或更新系统，以及 Xcode Command Line Tools。

```sh
bash build.sh
open "build/Splash Local.app"
```

生成的应用使用 ad-hoc 签名，未进行 Apple 公证。仓库只包含客户端源码、图标和本地服务启动辅助脚本，不包含 Splash 引擎、模型权重或用户配置。

## 现有服务依赖

当前版本针对作者的 Splash 1.1.0 + Qwen 27B 本地环境编写，尚不是全自动安装器。在其他 Mac 上，需要先配置兼容的 Splash 服务：

- 地址：`http://127.0.0.1:8000`；模型名：`qwen-uncensored-splash`。
- 认证：`~/.omlx/settings.json` 中的 `auth.api_key`，运行时读取，不随仓库发布。
- 启动辅助：`~/.local/share/splash-qwen/ensure-server.py`。
- launchd：`~/Library/LaunchAgents/local.splash.qwen-uncensored.plist`。
- 服务日志：`~/.local/share/splash-qwen/server.log`。

`service/` 保存当前启动脚本供参考。`serve.py` 默认使用 `~/.local/lib/splash-1.1.0` 的运行时，并从 `~/.local/share/splash-qwen/vision-bundle.txt` 读取模型包路径；包内需有 `target`、`draft` 和 `tokenizer`。需要根据实际安装位置配置 launchd。仓库不会下载模型或修改正在运行的服务。

App 设置存储在 `~/Library/Application Support/Splash Local/preferences.json`。聊天保存在 WKWebView 本地存储。关闭应用会保留共享服务；点击停止会断开其他使用该服务的客户端。

## 共享思考策略

API Base URL：`http://127.0.0.1:8000/v1`。

| 模型别名 | 行为 |
| --- | --- |
| `qwen-uncensored-splash-no-thinking` | 强制 none |
| `qwen-uncensored-splash-thinking` | 强制 low |
| `qwen-uncensored-splash` | 请求指定优先，否则读取共享默认值 |

`local_reasoning_policy.py` 是本地扩展。需在 Splash 服务端 `_prepare_prompt` 中调用其 `resolve(body, fallback)`，并设置 `SPLASH_LOCAL_POLICY_CONFIG` 为上述偏好文件路径。仅注册别名不足以启用此策略。仓库不复制上游 frontend.py；升级服务端时应重新检查接入点。

在服务配置完成后可用 `python3 verify-shared-thinking.py` 发真实请求验证。该脚本会调用本地已加载模型，不属于纯离线测试。

## 范围

图像输入能力取决于服务端模型和前端。该仓库未包含 vision 安装/转换流程，未验证在全新机器上的图像输入。当前不包含 MCP、文件执行代理、语音转录、模型下载管理或项目工作区。

上游引擎和网页聊天界面来自 [Inco AI Splash](https://github.com/incoai/splash)，需要独立安装并遵守其许可。模型也遵循各自许可。

## 隐私与安全

- API Key 仅从本机配置读取；源码中没有内置密钥，请勿提交实际的 `settings.json` 或 `.env`。
- 服务默认绑定 `127.0.0.1`。若要供其他设备使用，需要自行配置认证及安全传输，不建议直接暴露到公网。
- 聊天记录、系统提示词、偏好设置和日志均属于本地用户数据，不包含在本仓库中。导出的聊天 JSON 可能包含私人内容，请自行保管。
- `.gitignore` 排除了构建产物、日志、常见配置、模型权重和旧备份；它不能代替提交前检查。新增文件或截图时请确认不含个人信息。
- 客户端会向本机服务请求推理和 token 统计；`telemetry.js` 用于本地生成指标，未配置外部统计服务。
