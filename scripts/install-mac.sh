#!/bin/sh
# Builds an optimized (Release) Glide for Mac and installs it to /Applications,
# so it runs without Xcode. Re-run after pulling updates.
set -e
cd "$(dirname "$0")/.."

[ -f project.yml ] || ./scripts/setup.sh
xcodegen
xcodebuild \
  -project Glide.xcodeproj \
  -scheme GlideMac \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  -allowProvisioningUpdates \
  build

pkill -x Glide 2>/dev/null || true
rm -rf /Applications/Glide.app
cp -R build/Build/Products/Release/Glide.app /Applications/Glide.app
open /Applications/Glide.app
echo "Installed /Applications/Glide.app"
