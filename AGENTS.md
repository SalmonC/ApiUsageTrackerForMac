# API Usage Tracker for Mac - Agent Guide

## Project Overview

**API Usage Tracker for Mac** is a macOS menu bar application that tracks API usage quotas from various AI providers (MiniMax, GLM/智谱AI, Tavily). It provides both a menu bar interface and desktop widgets for monitoring remaining credits, usage, and plan limits.

- **Bundle ID**: `com.mactools.apiusagetracker`
- **App Group**: `group.com.mactools.apiusagetracker`
- **Minimum macOS**: 14.0 (Sonoma)
- **Swift Version**: 5.9
- **Xcode Version**: 15.0+

## Project Structure

```
MacUsageTracker/
├── project.yml                  # XcodeGen project configuration
├── VERSION                      # Version file (VERSION=1.0.10, BUILD=11)
├── README.md                    # User documentation (English/Chinese)
├── Sources/
│   ├── App/                     # Main application target
│   │   ├── MacUsageTrackerApp.swift      # App entry point & AppDelegate
│   │   ├── Views/
│   │   │   ├── MainView.swift            # Menu bar popover UI
│   │   │   └── SettingsView.swift        # Settings window UI
│   │   ├── Services/
│   │   │   └── AppViewModel.swift        # Main view model & business logic
│   │   └── Resources/
│   │       ├── Info.plist                # App Info.plist
│   │       └── ApiUsageTrackerForMac.entitlements  # App sandbox entitlements
│   ├── Shared/                  # Shared code between app and widget
│   │   ├── SharedModels.swift            # Data models, storage, settings
│   │   └── MiniMaxService.swift          # API service implementations
│   └── Widget/                  # Widget extension target
│       ├── UsageWidget.swift             # WidgetKit implementation
│       ├── Info.plist                    # Widget Info.plist
│       └── UsageWidget.entitlements      # Widget entitlements
└── ApiUsageTrackerForMac.xcodeproj/      # Generated Xcode project
```

## Technology Stack

- **Language**: Swift 5.9
- **UI Framework**: SwiftUI
- **Platform**: macOS 14.0+
- **Project Generation**: XcodeGen (configured via `project.yml`)
- **Data Persistence**: UserDefaults with App Groups
- **Architecture**: MVVM (Model-View-ViewModel)

## Build System

The project uses **XcodeGen** for project file generation. Do not manually edit `.xcodeproj` files.

### Build Commands

```bash
# Generate Xcode project from project.yml
xcodegen generate

# Build Debug version
xcodebuild -project ApiUsageTrackerForMac.xcodeproj \
  -scheme ApiUsageTrackerForMac \
  -configuration Debug build

# Build Release version
xcodebuild -project ApiUsageTrackerForMac.xcodeproj \
  -scheme ApiUsageTrackerForMac \
  -configuration Release build

# Create DMG (after building)
APP_PATH=~/Library/Developer/Xcode/DerivedData/ApiUsageTrackerForMac-*/Build/Products/Debug/API\ Tracker.app
hdiutil create -srcfolder "$APP_PATH" -volname "ApiUsageTrackerForMac" -fs HFS+ -format UDZO ApiUsageTrackerForMac.dmg
```

### Key Build Settings

- **App Target**: `ApiUsageTrackerForMac` (type: application)
- **Widget Target**: `UsageWidget` (type: app-extension)
- **Code Signing**: Manual (CODE_SIGN_IDENTITY: "-", CODE_SIGNING_ALLOWED: NO for local development)
- **Sandbox**: Enabled with network client and app group capabilities

## Architecture Details

### Targets

1. **ApiUsageTrackerForMac** (Main App)
   - Menu bar only app (`LSUIElement: YES` - no dock icon)
   - Popover interface from status bar
   - Settings window for configuration
   - Global hotkey support (default: ⌘⇧Space)

2. **UsageWidget** (App Extension)
   - WidgetKit-based desktop widgets
   - Supports small, medium, and large sizes
   - Shares data via App Group UserDefaults

### Core Components

| Component | Purpose |
|-----------|---------|
| `AppDelegate` | Menu bar setup, global hotkeys, window management |
| `AppViewModel` | Business logic, API fetching, data caching |
| `MainView` | Menu bar popover UI |
| `SettingsView` | Account management and app preferences |
| `Storage` | UserDefaults wrapper with JSON encoding |
| `UsageService` | Protocol for API provider implementations |

### Data Flow

```
SettingsView → AppViewModel → Storage (UserDefaults)
                    ↓
              [API Services] → WidgetCenter.reloadAllTimelines()
                    ↓
               MainView ← UsageData[]
```

## Supported API Providers

| Provider | Endpoint Pattern | Features |
|----------|-----------------|----------|
| **MiniMax** | `minimaxi.com`, `minimax.chat` | Auto-detects Coding Plan vs Pay-As-You-Go |
| **GLM (智谱AI)** | `open.bigmodel.cn`, `api.z.ai` | Auto-detects platform by API key format |
| **Tavily** | `api.tavily.com` | Credit-based quota tracking |

## Code Style Guidelines

### Swift Conventions

- Use `@MainActor` for UI-related classes
- Prefer `async/await` for asynchronous operations
- Use `ObservableObject` with `@Published` for state management
- Follow Swift naming conventions (camelCase for variables/functions, PascalCase for types)

### Error Handling

- Custom `APIError` enum for API-related errors
- Error messages in Chinese for user-facing errors
- Logging via `Logger.log()` (writes to `~/Documents/api_tracker.log`)

### Example Pattern

```swift
// Service protocol
protocol UsageService {
    var provider: APIProvider { get }
    func fetchUsage(apiKey: String) async throws -> (remaining: Double?, used: Double?, total: Double?, refreshTime: Date?)
}

// ViewModel pattern
@MainActor
final class AppViewModel: ObservableObject {
    @Published var usageData: [UsageData] = []
    @Published var isLoading = false
    
    func refreshAll() async {
        isLoading = true
        // ... fetch logic
        isLoading = false
    }
}
```

## Data Models

### Core Types

```swift
APIProvider: Enum  // miniMax, glm, tavily
APIAccount: Struct // id, name, provider, apiKey, isEnabled
AppSettings: Struct // accounts, refreshInterval, hotkey
UsageData: Struct   // account info + usage statistics
HotkeySetting: Struct // keyCode, modifiers
```

### Storage

- **App Group**: `group.com.mactools.apiusagetracker`
- **Keys**: `usageData`, `appSettings`
- **Format**: JSON-encoded via `JSONEncoder/Decoder`

## Development Notes

### Adding a New API Provider

1. Add case to `APIProvider` enum in `SharedModels.swift`
2. Implement `UsageService` protocol in `MiniMaxService.swift`
3. Add provider icon mapping
4. Update `getService(for:)` factory function

### Key Configuration Files

- `project.yml`: XcodeGen configuration (targets, settings, schemes)
- `Sources/App/Resources/Info.plist`: App metadata (LSUIElement enabled)
- `*.entitlements`: Sandbox and app group capabilities
- `VERSION`: Build version tracking (format: `VERSION=x.x.x\nBUILD=x`)

### UI Patterns

- Collapsible rows with chevron icons
- Color-coded usage status (green < 50%, orange 50-80%, red > 80%)
- Progress bars for visual usage indication
- "K" suffix for numbers >= 1000 (e.g., "1.5K")

## Testing

Currently, this project does not have automated tests. Testing is done manually:

1. Build and run the app in Xcode
2. Configure API accounts in Settings
3. Verify data fetching and display
4. Test widget updates

## Security Considerations

- API keys stored in UserDefaults (not Keychain - consider improvement)
- App Sandbox enabled with minimal entitlements
- Network client capability required for API calls
- No hardcoded API keys in source code

## Localization

- User-facing text is primarily in **Chinese** (e.g., "刷新" for Refresh, "设置" for Settings)
- Error messages from API services are also in Chinese

## Deployment

1. Update `VERSION` file
2. Update `README.md` changelog
3. Generate project: `xcodegen generate`
4. Build release: `xcodebuild -configuration Release`
5. Create DMG for distribution
6. Tag release in git

## Dependencies

No external dependencies. Uses only Apple frameworks:
- SwiftUI
- WidgetKit
- ServiceManagement (for launch at login)
- Carbon (for global hotkeys)
- AppKit
