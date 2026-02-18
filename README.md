# API Usage Tracker for Mac

A macOS menu bar application for tracking API usage quotas from various AI providers. Monitor your remaining credits, usage, and plan limits directly from the menu bar or desktop widget.

![Platform](https://img.shields.io/badge/platform-macOS%2014.0+-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Version](https://img.shields.io/badge/version-1.1.0-blue)

## Features

### Core Functionality
- **Menu Bar Interface** - Quick access to API usage from the menu bar
- **Desktop Widgets** - View usage on your desktop (small, medium, large sizes)
- **Auto Refresh** - Configurable automatic refresh interval (1-60 minutes)
- **Global Hotkey** - Show/hide window with customizable keyboard shortcut

### Supported Providers
| Provider | Type | Features |
|----------|------|----------|
| **MiniMax** | Coding Plan / Pay-As-You-Go | Auto-detects API type |
| **GLM (智谱AI)** | Subscription / Pay-As-You-Go | Auto-detects platform (open.bigmodel.cn / api.z.ai) |
| **Tavily** | Credits | Search quota tracking |

### UI/UX
- **Collapsible Dashboard** - Expand/collapse accounts to see details
- **Usage Progress** - Visual progress bars showing usage percentage
- **Color-coded Status** - Green/Orange/Red based on usage level
- **Error Handling** - Clear error messages with retry options

## Requirements

- macOS 14.0 (Sonoma) or later

## Installation

### From Release
1. Download the latest `.dmg` from [Releases](https://github.com/SalmonC/ApiUsageTrackerForMac/releases)
2. Open the `.dmg` file
3. Drag `API Tracker.app` to Applications
4. Launch the app

### From Source
```bash
# Clone repository
git clone https://github.com/SalmonC/ApiUsageTrackerForMac.git
cd ApiUsageTrackerForMac

# Generate Xcode project
xcodegen generate

# Build
xcodebuild -project ApiUsageTrackerForMac.xcodeproj -scheme ApiUsageTrackerForMac -configuration Debug build

# Create DMG (optional)
APP_PATH=~/Library/Developer/Xcode/DerivedData/ApiUsageTrackerForMac-*/Build/Products/Debug/API\ Tracker.app
hdiutil create -srcfolder "$APP_PATH" -volname "ApiUsageTrackerForMac" -fs HFS+ -format UDZO ApiUsageTrackerForMac.dmg
```

## Configuration

1. Click the menu bar icon
2. Click the **Settings** gear icon
3. Add API accounts:
   - Click **+** to add a new account
   - Select provider (MiniMax, GLM, or Tavily)
   - Enter your API key
   - Configure display preferences (show/hide in menu bar)
4. Click **Save**

### Getting API Keys

- **MiniMax**: [MiniMax Open Platform](https://platform.minimaxi.com) → API Keys
- **GLM (智谱AI)**: [Z.ai](https://z.ai) or [BigModel](https://bigmodel.cn) → API Keys
- **Tavily**: [Tavily Dashboard](https://app.tavily.com) → API Keys

## Usage

### Menu Bar
- **Left-click**: Open usage dashboard
- **Right-click**: Context menu (Refresh, Settings, About, Quit)

### Dashboard
- Expand/collapse rows by clicking the chevron icon
- View remaining credits, used amount, and total quota
- Progress bars show usage percentage

### Desktop Widget
1. Right-click on desktop → "Edit Widgets"
2. Search for "API Usage"
3. Add preferred size widget

## Keyboard Shortcuts

- **Global Hotkey**: Default is `⌘⇧Space` (configurable in Settings)

## Changelog

### v1.1.0 (2026-02-18)
- **New**: Add Tavily API support for credit quota tracking
- **New**: Auto-detect MiniMax API type (Coding Plan vs Pay-As-You-Go)
- **New**: Auto-detect GLM platform (open.bigmodel.cn vs api.z.ai)
- **New**: Simplified provider selection
- **Fix**: GLM quota query using model-usage + quota/limit endpoints
- **Fix**: Tavily JSON parsing for Int/Double types
- **UI**: Collapsible dashboard rows with key info always visible
- **UI**: Auto-set account name based on provider
- **UI**: Save button with visual feedback

### v1.0.x
- Initial releases with MiniMax support
- Basic menu bar interface
- Desktop widget support

## License

MIT License - See [LICENSE](LICENSE) for details.

## Acknowledgments

- [MiniMax](https://platform.minimaxi.com) - API usage data
- [Z.ai / BigModel](https://z.ai) - GLM API
- [Tavily](https://tavily.com) - Search API credits

---

Built with SwiftUI and WidgetKit for macOS
