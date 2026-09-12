#!/bin/zsh
set -eu
cd "$(dirname "$0")"
swift build -c release
CHAPPIE_BUNDLE="$PWD/dist/Chappie.app"
mkdir -p "$CHAPPIE_BUNDLE/Contents/MacOS"
cp .build/release/Chappie "$CHAPPIE_BUNDLE/Contents/MacOS/Chappie"
cp Info.plist "$CHAPPIE_BUNDLE/Contents/Info.plist"
mkdir -p "$CHAPPIE_BUNDLE/Contents/Resources"
cp Resources/Chappie.icns "$CHAPPIE_BUNDLE/Contents/Resources/Chappie.icns"
codesign --force --sign - "$CHAPPIE_BUNDLE"
codesign --verify --strict "$CHAPPIE_BUNDLE"
echo "作成しました: $CHAPPIE_BUNDLE"
