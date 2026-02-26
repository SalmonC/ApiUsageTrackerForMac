# API Account 凭证获取指南

本指南用于说明在 **API Tracker for Mac** 中添加 `API Account` 时，哪些 provider 需要额外凭证、以及去哪里获取。

说明：
- 如果某个 provider 只需要普通 `API Key`（例如 `sk-...`），通常你已经知道如何获取，这里不重复。
- 本文重点说明容易卡住的 `ChatGPT (Subscription)`。

## 各 Provider 需要什么凭证

- `MiniMax`：API Key（即可）
- `GLM (智谱AI)`：API Key（即可）
- `Tavily`：API Key（即可）
- `OpenAI API (Token)`：OpenAI API Key（`sk-...`，用于 API 账单/token 用量）
- `KIMI (Moonshot)`：API Key（即可）
- `ChatGPT (Subscription)`：**ChatGPT Web accessToken（推荐）** 或 **ChatGPT Web session cookie**（应用可自动尝试换取 accessToken）

## ChatGPT (Subscription) 为什么不能用 `sk-...`

`ChatGPT (Subscription)` 查询的是 **ChatGPT 网页版账号/订阅/消息额度**（例如 Plus/Team 的会话限额类信息），不是 OpenAI API 平台的 API 账单。

所以这里需要的是：
- ChatGPT Web 登录态相关凭证（`accessToken` 或 session cookie）
- 不是 OpenAI API 的 `sk-...` Key

如果你想查 OpenAI API token/账单，请使用 `OpenAI API (Token)` provider。

## 获取 ChatGPT accessToken（推荐）

有两种常用方法：

### 方法 A：浏览器控制台（最简单）

前提：你已在浏览器登录 ChatGPT（`chatgpt.com`）。

1. 打开 [https://chatgpt.com](https://chatgpt.com)
2. 打开浏览器开发者工具（DevTools）
3. 切到 `Console`（控制台）
4. 执行以下命令：

```js
fetch('/api/auth/session')
  .then(r => r.json())
  .then(data => console.log(data))
```

5. 在输出结果里查找 `accessToken`
6. 复制 `accessToken` 的字符串值
7. 在应用里添加账号时选择 `ChatGPT (Subscription)`，粘贴到凭证输入框

注意：
- `accessToken` 会过期，过期后重新按上面步骤获取即可。
- 有时接口返回未登录/无 token，请先确认你当前浏览器确实已登录 ChatGPT。

### 方法 B：直接使用 session cookie（应用会自动换 token）

如果你不方便拿到 `accessToken`，可以直接填 ChatGPT 的 session cookie（完整 Cookie 字符串或 session token 值）。

浏览器里一般可在 DevTools 的：
- `Application` / `Storage` -> `Cookies` -> `https://chatgpt.com`

常见字段（可能因版本变化而不同）：
- `__Secure-next-auth.session-token`

你可以填写：
- 完整 cookie 片段，例如：
  - `__Secure-next-auth.session-token=xxxxx`
- 或仅 value（应用会尝试按常见字段名拼接）

注意：
- Cookie 更敏感，建议仅在本机使用。
- Cookie 失效/登录态变化后需要重新获取。

## 常见问题（ChatGPT）

### 1) “access token 根本找不到”

先用“方法 A 控制台”执行 `fetch('/api/auth/session')`。如果返回 JSON 中没有 `accessToken`：
- 你可能当前未登录 ChatGPT
- 登录态已失效（重新登录）
- 浏览器环境拦截了请求（隐私插件、企业策略等）

这时建议：
- 先刷新页面并重新登录
- 再执行一次控制台命令
- 或改用“方法 B”填 session cookie

### 2) 能连通但看不到额度数字

ChatGPT Web 相关接口不是稳定公开 API，字段可能变化。应用会尽量解析：
- 订阅状态
- 消息额度（如可用）
- token 类额度（如接口有返回）

如果只显示订阅状态而没有具体数字，通常是 ChatGPT 当前返回里没有暴露对应数值，或字段名发生变化。

### 3) 填 `sk-...` 报错

这是正常现象。`sk-...` 是 OpenAI API Key，请改用 `OpenAI API (Token)` provider。

## 安全建议

- 不要把 ChatGPT session cookie 发给他人
- 不要把凭证提交到 git 仓库
- 若怀疑泄露，请退出登录/重新登录，使旧登录态失效

## 更新说明

如果后续 ChatGPT 网页接口变化，本文档和应用解析逻辑都可能需要同步更新。
