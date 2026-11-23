# Local development

## Requirements

- macOS with Xcode 26 or later
- An iOS 26 simulator

## Run the app

Open `FinalApproach/FinalApproach.xcodeproj`, pick an iPhone simulator, and
press Run. Local builds use the dev values in `FinalApproach/Config/App.xcconfig`
and need no secrets.

From the command line:

```sh
# Build for the simulator
xcodebuild build \
  -project FinalApproach/FinalApproach.xcodeproj \
  -scheme FinalApproach \
  -destination 'platform=iOS Simulator,name=iPhone 17'

# Run the app unit tests
xcodebuild test \
  -project FinalApproach/FinalApproach.xcodeproj \
  -scheme FinalApproach \
  -destination 'platform=iOS Simulator,name=iPhone 17'

# Run the core package tests (also works on Linux)
swift test --package-path Packages/FinalApproachCore
```

Run `xcrun simctl list devices available` to see which simulator names exist
on your Mac, and swap the name in the destination if needed.

## Claude Code with the simulator

A Claude Code session on the Mac can build the app, launch it in the
simulator, take screenshots, and tap through screens.

1. Start Claude Code in the repo folder. It reads `CLAUDE.md`.

   ```sh
   cd ~/Documents/GitHub/Final_Approach && claude
   ```

2. Add XcodeBuildMCP, which gives Claude tools to build, launch, screenshot,
   and drive the simulator. It needs macOS 14.5, Xcode 16, and Node 18 or
   later. The environment variable turns off its crash telemetry.

   ```sh
   claude mcp add XcodeBuildMCP -s user -e XCODEBUILDMCP_SENTRY_DISABLED=true -- npx -y xcodebuildmcp@latest mcp
   ```

3. Optionally add Apple's own bridge, which ships with Xcode 26.3 and can
   render SwiftUI previews. Xcode has to be open for it to work.

   ```sh
   claude mcp add --transport stdio xcode -s user -- xcrun mcpbridge
   ```

Both commands come from each tool's public instructions and were not run when
this page was written. Check the tool's own page if one fails.
