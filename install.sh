#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MarkdownViewer"
APP_SRC="build/$APP_NAME.app"
APP_DEST="/Applications/$APP_NAME.app"
BUNDLE_ID="com.marcello.$APP_NAME"

if [ ! -d "$APP_SRC" ]; then
    echo "Building first..."
    ./build.sh
fi

echo "Installing to /Applications..."
rm -rf "$APP_DEST"
cp -R "$APP_SRC" "$APP_DEST"

echo "Registering with Launch Services..."
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREG" -f "$APP_DEST"

echo "Setting MarkdownViewer as default handler for Markdown UTIs..."
swift - <<EOF
import Foundation

let bundleID = "$BUNDLE_ID" as CFString
let utis = [
    "net.daringfireball.markdown",
    "public.markdown",
]

for uti in utis {
    let status = LSSetDefaultRoleHandlerForContentType(uti as CFString, .all, bundleID)
    print("  \(uti) -> \(status == 0 ? "OK" : "error \(status)")")
}
EOF

echo ""
echo "Refreshing Finder icon cache..."
killall Finder >/dev/null 2>&1 || true
killall Dock >/dev/null 2>&1 || true

echo ""
echo "Installed: $APP_DEST"
echo "Double-click any .md file to open in MarkdownViewer."
