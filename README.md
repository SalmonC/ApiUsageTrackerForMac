# API Usage Tracker for Mac

A macOS menu bar application for tracking API usage quotas from various AI providers. Monitor your remaining credits, usage, and plan limits directly from the menu bar or desktop widget.

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014.0+-blue" alt="Platform">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/version-1.2.0-blue" alt="Version">
</p>

---

## 📖 Language / 语言

- [English](#english)
- [中文](#中文)

---

<a name="english"></a>
## 🇺🇸 English

### Features

#### Core Functionality
- **Menu Bar Interface** - Quick access to API usage from the menu bar
- **Desktop Widgets** - View usage on your desktop (small, medium, large sizes)
- **Auto Refresh** - Configurable automatic refresh interval (1-60 minutes)
- **Global Hotkey** - Show/hide window with customizable keyboard shortcut
- **Test Connection** - Verify API keys before saving
- **Low Usage Alerts** - System notifications when usage exceeds 80% or 90%

#### Security
- **Keychain Storage** - API keys are securely stored in macOS Keychain

#### Supported Providers
| Provider | Type | Features |
|----------|------|----------|
| **MiniMax** | Coding Plan / Pay-As-You-Go | Auto-detects API type |
| **GLM (Zhipu AI)** | Subscription / Pay-As-You-Go | Auto-detects platform (open.bigmodel.cn / api.z.ai) |
| **Tavily** | Credits | Search quota tracking |
| **OpenAI** | Pay-As-You-Go | Usage and billing tracking |

#### UI/UX
- **Collapsible Dashboard** - Expand/collapse accounts to see details
- **Usage Progress** - Visual progress bars showing usage percentage
- **Color-coded Status** - Green/Orange/Red based on usage level
- **Error Handling** - Clear error messages with retry options

### Requirements

- macOS 14.0 (Sonoma) or later

### Installation

#### From Release
1. Download the latest `.dmg` from [Releases](https://github.com/SalmonC/ApiUsageTrackerForMac/releases)
2. Open the `.dmg` file
3. Drag `API Tracker.app` to Applications
4. Launch the app

#### From Source
```bash
# Clone repository
git clone https://github.com/SalmonC/ApiUsageTrackerForMac.git
cd ApiUsageTrackerForMac

# Generate Xcode project
xcodegen generate

# Build
xcodebuild -project ApiUsageTrackerForMac.xcodeproj -scheme ApiUsageTrackerForMac -configuration Release build

# Create DMG (optional)
APP_PATH=~/Library/Developer/Xcode/DerivedData/ApiUsageTrackerForMac-*/Build/Products/Release/API\ Tracker.app
hdiutil create -srcfolder "$APP_PATH" -volname "ApiUsageTrackerForMac" -fs HFS+ -format UDZO ApiUsageTrackerForMac.dmg
```

### Configuration

1. Click the menu bar icon
2. Click the **Settings** gear icon
3. Add API accounts:
   - Click **+** to add a new account
   - Select provider (MiniMax, GLM, Tavily, or OpenAI)
   - Enter your API key
   - Click **Test Connection** to verify
   - Configure display preferences (show/hide in menu bar)
4. Click **Save**

### Getting API Keys

- **MiniMax**: [MiniMax Open Platform](https://platform.minimaxi.com) → API Keys
- **GLM (Zhipu AI)**: [Z.ai](https://z.ai) or [BigModel](https://bigmodel.cn) → API Keys
- **Tavily**: [Tavily Dashboard](https://app.tavily.com) → API Keys
- **OpenAI**: [OpenAI Platform](https://platform.openai.com) → API Keys

### Usage

#### Menu Bar
- **Left-click**: Open usage dashboard
- **Right-click**: Context menu (Refresh, Settings, About, Quit)

#### Dashboard
- Expand/collapse rows by clicking the chevron icon
- View remaining credits, used amount, and total quota
- Progress bars show usage percentage

#### Desktop Widget
1. Right-click on desktop → "Edit Widgets"
2. Search for "API Usage"
3. Add preferred size widget

### Keyboard Shortcuts

- **Global Hotkey**: Default is `⌘⇧Space` (configurable in Settings)

---

<a name="中文"></a>
## 🇨🇳 中文

### 功能特性

#### 核心功能
- **菜单栏界面** - 从菜单栏快速查看 API 用量
- **桌面小组件** - 在桌面上查看用量（小、中、大三种尺寸）
- **自动刷新** - 可配置的自动刷新间隔（1-60 分钟）
- **全局快捷键** - 可自定义的快捷键显示/隐藏窗口
- **连接测试** - 保存前验证 API Key 是否有效
- **用量提醒** - 用量超过 80% 或 90% 时发送系统通知

#### 安全性
- **钥匙串存储** - API Key 安全存储在 macOS 钥匙串中

#### 支持的提供商
| 提供商 | 类型 | 功能 |
|--------|------|------|
| **MiniMax** | Coding Plan / 按量付费 | 自动检测 API 类型 |
| **GLM (智谱AI)** | 订阅 / 按量付费 | 自动检测平台 (open.bigmodel.cn / api.z.ai) |
| **Tavily** | 额度 | 搜索配额追踪 |
| **OpenAI** | 按量付费 | 用量和账单追踪 |

#### 界面设计
- **可折叠仪表盘** - 展开/折叠账户查看详情
- **用量进度条** - 可视化显示用量百分比
- **颜色编码状态** - 根据用量级别显示绿/橙/红色
- **错误处理** - 清晰的错误信息和重试选项

### 系统要求

- macOS 14.0 (Sonoma) 或更高版本

### 安装方法

#### 从 Release 安装
1. 从 [Releases](https://github.com/SalmonC/ApiUsageTrackerForMac/releases) 下载最新的 `.dmg` 文件
2. 打开 `.dmg` 文件
3. 将 `API Tracker.app` 拖到应用程序文件夹
4. 启动应用

#### 从源码编译
```bash
# 克隆仓库
git clone https://github.com/SalmonC/ApiUsageTrackerForMac.git
cd ApiUsageTrackerForMac

# 生成 Xcode 项目
xcodegen generate

# 编译
xcodebuild -project ApiUsageTrackerForMac.xcodeproj -scheme ApiUsageTrackerForMac -configuration Release build

# 创建 DMG（可选）
APP_PATH=~/Library/Developer/Xcode/DerivedData/ApiUsageTrackerForMac-*/Build/Products/Release/API\ Tracker.app
hdiutil create -srcfolder "$APP_PATH" -volname "ApiUsageTrackerForMac" -fs HFS+ -format UDZO ApiUsageTrackerForMac.dmg
```

### 配置说明

1. 点击菜单栏图标
2. 点击**设置**齿轮图标
3. 添加 API 账户：
   - 点击 **+** 添加新账户
   - 选择提供商（MiniMax、GLM、Tavily 或 OpenAI）
   - 输入 API Key
   - 点击**测试连接**验证有效性
   - 配置显示偏好（在菜单栏中显示/隐藏）
4. 点击**保存**

### 获取 API Key

- **MiniMax**: [MiniMax 开放平台](https://platform.minimaxi.com) → API Keys
- **GLM (智谱AI)**: [Z.ai](https://z.ai) 或 [BigModel](https://bigmodel.cn) → API Keys
- **Tavily**: [Tavily 控制台](https://app.tavily.com) → API Keys
- **OpenAI**: [OpenAI 平台](https://platform.openai.com) → API Keys

### 使用说明

#### 菜单栏
- **左键点击**：打开用量仪表盘
- **右键点击**：上下文菜单（刷新、设置、关于、退出）

#### 仪表盘
- 点击箭头图标展开/折叠行
- 查看剩余额度、已用量和总额度
- 进度条显示用量百分比

#### 桌面小组件
1. 右键桌面 → "编辑小组件"
2. 搜索 "API Usage"
3. 添加喜欢的小组件尺寸

### 键盘快捷键

- **全局快捷键**：默认 `⌘⇧Space`（可在设置中配置）

---

## Changelog / 更新日志

### v1.2.1 (2026-02-25)
- **Fix / 修复**: GLM Token query returning 0 / GLM Token 余量查询返回 0 的问题
  - Added user info API as primary source / 添加 user info API 作为主要数据来源
  - Improved number parsing for various formats / 改进多种格式的数字解析
- **New / 新增**: Dynamic popover height adjustment / 看板高度根据内容实时调整
  - Height adapts to data count and content / 高度根据数据量和内容自适应
- **Improve / 优化**: Redesigned collapsed/expanded view / 重新设计折叠/展开视图
  - Collapsed: Compact with mini progress ring / 折叠：紧凑布局带迷你进度环
  - Expanded: Detailed stats grid with visual hierarchy / 展开：详细统计网格和视觉层级

### v1.2.0 (2026-02-25)
- **New / 新增**: Add OpenAI API support / 添加 OpenAI API 支持
- **New / 新增**: API Key storage migrated to Keychain / API Key 迁移到钥匙串存储
- **New / 新增**: Add "Test Connection" button / 添加"测试连接"按钮
- **New / 新增**: System notifications for high usage / 高用量时发送系统通知
- **Improve / 优化**: Optimized Logger with buffered writes / 优化 Logger 使用缓冲写入

### v1.1.1 (2026-02-25)
- **Fix / 修复**: Timer memory leak / 修复 Timer 内存泄漏
- **Fix / 修复**: Refresh interval not taking effect / 修复刷新间隔不生效问题
- **Fix / 修复**: Popover recreation memory leak / 修复 Popover 重复创建内存泄漏
- **Fix / 修复**: Widget refresh interval now follows settings / Widget 刷新间隔跟随设置

### v1.1.0 (2026-02-18)
- **New / 新增**: Add Tavily API support / 添加 Tavily API 支持
- **New / 新增**: Auto-detect MiniMax API type / 自动检测 MiniMax API 类型
- **New / 新增**: Auto-detect GLM platform / 自动检测 GLM 平台

---

## License / 许可证

MIT License - See [LICENSE](LICENSE) for details / 查看 [LICENSE](LICENSE) 了解详情

## Acknowledgments / 致谢

- [MiniMax](https://platform.minimaxi.com) - API usage data
- [Z.ai / BigModel](https://z.ai) - GLM API
- [Tavily](https://tavily.com) - Search API credits
- [OpenAI](https://openai.com) - GPT API

---

Built with SwiftUI and WidgetKit for macOS / 使用 SwiftUI 和 WidgetKit 为 macOS 构建
