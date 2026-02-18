# ApiUsageTrackerForMac

A macOS menu bar application for tracking API usage from various providers, featuring desktop widgets.

## Features

- **Menu Bar Interface**: Quick access to API usage information directly from the menu bar
- **Right-Click Context Menu**:
  - Refresh - Manually refresh all service data
  - Settings - Configure API keys and preferences
  - Launch at Login - Enable/disable auto-start
  - About - View app information
  - Quit - Exit the application
- **Desktop Widget**: View usage data directly on your desktop (small, medium, large sizes)
- **Auto Refresh**: Configurable automatic refresh interval
- **Multi-Provider Support**:
  - MiniMax Coding Plan
  - MiniMax Pay-As-You-Go (coming soon)
  - GLM (智谱AI) (coming soon)

## Requirements

- macOS 14.0 or later

## Installation

1. Download the latest release from [Releases](https://github.com/SalmonC/ApiUsageTrackerForMac/releases)
2. Open the `.dmg` file
3. Drag `ApiUsageTrackerForMac.app` to Applications
4. Launch the app from Applications

## Configuration

1. Click the menu bar icon (chart icon)
2. Click the **Settings** tab
3. Enter your API keys:
   - **MiniMax Coding Plan API Key**: Get from [MiniMax Open Platform](https://platform.minimaxi.com/user-center/basic-information/interface-key)
4. Data will automatically refresh based on your configured interval

## Widget Setup

1. Right-click on your desktop
2. Select "Edit Widgets"
3. Search for "API Usage"
4. Add the widget in your preferred size

## Development

### Prerequisites

- Xcode 15.0+
- XcodeGen

### Build

```bash
cd ApiUsageTrackerForMac
xcodegen generate
xcodebuild -project ApiUsageTrackerForMac.xcodeproj -scheme ApiUsageTrackerForMac -configuration Debug build
```

### Create DMG

```bash
# After building
APP_PATH=~/Library/Developer/Xcode/DerivedData/ApiUsageTrackerForMac-*/Build/Products/Debug/ApiUsageTrackerForMac.app
hdiutil create -srcfolder "$APP_PATH" -volname "ApiUsageTrackerForMac" -fs HFS+ -format UDZO ApiUsageTrackerForMac.dmg
```

## License

MIT License

## Acknowledgments

- [MiniMax Open Platform](https://platform.minimaxi.com) - For providing the API usage data
