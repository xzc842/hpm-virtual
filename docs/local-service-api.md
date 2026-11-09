# hpm-gui 本地调试服务 API

hpm-gui 启动时会监听 `127.0.0.1:17321`（端口占用时向后尝试），
并把地址写入 `~/.config/hpm-gui/service.json`。该服务原本供 VSCode 插件使用，
下面这些新增接口面向其他外部程序；VSCode 插件不需要改动。

服务地址也可以通过 `HPM_GUI_SERVICE_URL` 或 VSCode 设置
`hpmDebug.serviceUrl` 指定。

## 调试器状态

```http
GET /debugger
GET /debugger/status
```

返回示例：

```json
{
  "ok": true,
  "active": true,
  "pid": 12345,
  "project": "/path/to/project",
  "protocol": "hpm-debug/2",
  "features": ["device.list", "device.snapshot"],
  "status": {
    "status": "running",
    "pc": 297,
    "halted": false
  },
  "pc": 297,
  "source": { "file": "main.c", "line": 80, "addr": 297 },
  "breakpoints": [],
  "device_count": 1,
  "info": { "service": "hpm-gui-debug", "version": 2 }
}
```

`GET /status` 保留原有行为，未启动时返回 `ok:false`；
`/debugger` 即使没有会话也会返回 `ok:true` 和 `active:false`。

## 项目设备清单

```http
GET /devices
GET /devices/input
GET /devices/output
GET /devices/<device-name>
```

设备清单以项目 `project.json` 的 `devices` 为准，并合并当前调试会话里的
在线状态、输入/输出角色、控件描述和值：

```json
{
  "ok": true,
  "project": "/path/to/project",
  "active": true,
  "role": "",
  "count": 1,
  "devices": [
    {
      "name": "serial",
      "device": "serial",
      "driver": "usb_cdc",
      "config": {},
      "present": true,
      "online": true,
      "role": "input",
      "title": "USB CDC",
      "channels": [
        { "id": "tx", "name": "发送内容", "type": "string", "widget": "textarea" }
      ],
      "values": { "send": false },
      "source": "project"
    }
  ]
}
```

没有调试会话时，仍会返回项目清单，只是 `present`/`online` 为 `false`，
且没有会话运行时才有的 `role`、`channels`、`values`。

## 向输入设备发送输入

```http
POST /devices/input
Content-Type: application/json
```

按通道设置值：

```json
{
  "device": "serial",
  "channel": "tx",
  "value": "hello\n"
}
```

触发按钮/动作通道：

```json
{
  "device": "serial",
  "channel": "send",
  "action": "invoke"
}
```

一次设置多个通道：

```json
{
  "device": "serial",
  "values": { "tx": "hello", "send": true }
}
```

原始数据：

```json
{
  "device": "serial",
  "action": "raw",
  "data": { "cmd": "set", "channel": "tx", "value": "hello" }
}
```

成功返回：

```json
{ "ok": true, "device": "serial", "channel": "tx", "action": "set" }
```

未启动调试会话时返回 HTTP 400，错误码为 `not_running`。

## 长连接读取输出设备值

```http
GET /outputs/stream
GET /output/stream
```

这是给外部程序读取**输出设备值**的长连接：

- 连接建立时先发送一帧 `snapshot`，包含所有输出设备的当前值；
- 之后只在输出设备值变化时推送；
- 引脚和输入设备（`role=input`）不会进入这个流；
- 支持 SSE（默认）和 NDJSON。

SSE：

```bash
curl -N 'http://127.0.0.1:17321/outputs/stream'
```

```text
event: snapshot
data: {"type":"snapshot","active":true,
       "devices":[{"device":"led","values":{"power":true}}]}

id: 18
data: {"cursor":18,"type":"device","device":"led","values":{"power":true}}
```

NDJSON：

```bash
curl -N 'http://127.0.0.1:17321/outputs/stream?format=ndjson'
```

```text
{"type":"snapshot","devices":[...]}
{"cursor":18,"type":"device","device":"led","values":{"power":true}}
```

查询参数：

| 参数 | 说明 |
|---|---|
| `cursor` | 从哪个事件之后开始；不传时从当前快照之后开始，避免重复回放 |
| `format` | `sse`（默认）或 `ndjson` |

## 长连接读取完整调试事件

```http
GET /events/stream
GET /stream
```

用于读取日志、断点、设备、引脚等全部事件；参数和格式与 `/outputs/stream` 相同，
并支持 `types=log,event,state` 过滤。

默认使用 SSE（`text/event-stream`），连接建立后持续推送，不需要轮询。
VSCode 插件仍然使用原来的 `/events?cursor=N` 轮询接口，未做改动。

查询参数：

| 参数 | 说明 |
|---|---|
| `cursor` | 从哪个事件序号之后开始，默认 0 |
| `types` | 逗号分隔的事件类型，例如 `log,event,state`；留空为全部 |
| `format` | `sse`（默认）或 `ndjson`/`jsonl` |

SSE 示例：

```text
retry: 1000
event: hello
data: {"ok":true,"stream":"sse","cursor":0,...}

id: 12
data: {"cursor":12,"message":{"type":"log","level":"info","message":"..."}}

: ping
```

NDJSON 示例：

```bash
curl -N 'http://127.0.0.1:17321/events/stream?format=ndjson&types=log'
```

```text
{"ok": true, "stream": "ndjson", "cursor": 0, ...}
{"cursor": 12, "message": {"type": "log", "level": "info", "message": "..."}}
{"ok": true, "heartbeat": true, "active": true, "time": 123}
```

- 每 10 秒发送一次心跳，防止连接被中间层断开；
- 服务端事件缺口会发送 `reset` 事件；
- 连接断开由客户端负责重连，SSE 会自动使用 `retry: 1000`；
- `/events` 轮询接口保持原样。

## 其他原有接口

- `GET /health`：服务信息、能力列表
- `GET /events?cursor=N`：调试事件
- `GET /memory?space=iram&addr=0&length=256`
- `GET /variables`
- `GET /dump?spaces=code,iram,xram,sfr`
- `POST /start`、`POST /stop`
- `POST /control`，`action` 为 `run`/`pause`/`step`/`reset`
- `POST /breakpoints`、`POST /breakpoints/clear`

所有响应都是 JSON，并带有 CORS 头，方便本机其他程序直接调用。
