#!/bin/bash
set -euo pipefail

VERSION="${1:?Usage: scripts/release.sh <version> (e.g. 0.1.0)}"
BETA="${2:-}"  # pass "beta" as second arg for beta release

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$HOME/Library/Developer/Xcode/DerivedData/Weave-ctubmypjxmvjnbawrnzysubshqeb/Build/Products/Release"
APP="$BUILD_DIR/Weave.app"
SPARKLE_BIN="$HOME/Library/Developer/Xcode/DerivedData/Weave-ctubmypjxmvjnbawrnzysubshqeb/SourcePackages/artifacts/sparkle/Sparkle/bin"
IDENTITY="Developer ID Application: Lukas Froehlich (TP77KRF2NP)"
DIST_DIR="$PROJECT_DIR/dist"
ZIP_NAME="Weave-${VERSION}.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"

echo "==> Building Weave v${VERSION}..."
cd "$PROJECT_DIR"
xcodebuild -project Weave.xcodeproj -scheme Weave -configuration Release \
    ONLY_ACTIVE_ARCH=YES \
    MARKETING_VERSION="$VERSION" \
    clean build 2>&1 | tail -3

echo "==> Re-signing Sparkle binaries..."
codesign -f -s "$IDENTITY" -o runtime --timestamp \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
codesign -f -s "$IDENTITY" -o runtime --timestamp \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
codesign -f -s "$IDENTITY" -o runtime --timestamp \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
codesign -f -s "$IDENTITY" -o runtime --timestamp \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
codesign -f -s "$IDENTITY" -o runtime --timestamp \
    "$APP/Contents/Frameworks/Sparkle.framework"
codesign -f -s "$IDENTITY" -o runtime --timestamp "$APP"

echo "==> Verifying signature..."
codesign --verify --deep --strict "$APP"

echo "==> Notarizing..."
rm -f /tmp/Weave-notarize.zip
ditto -c -k --keepParent "$APP" /tmp/Weave-notarize.zip
xcrun notarytool submit /tmp/Weave-notarize.zip \
    --keychain-profile "weave-notarize" --wait
rm /tmp/Weave-notarize.zip

echo "==> Stapling..."
xcrun stapler staple "$APP"

echo "==> Creating distribution zip..."
mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP" "$ZIP_PATH"

echo "==> Signing zip for Sparkle..."
SPARKLE_SIG=$("$SPARKLE_BIN/sign_update" "$ZIP_PATH" 2>&1)
echo "$SPARKLE_SIG"

SIGNATURE=$(echo "$SPARKLE_SIG" | grep 'sparkle:edSignature=' | sed 's/.*sparkle:edSignature="\([^"]*\)".*/\1/')
LENGTH=$(echo "$SPARKLE_SIG" | grep 'length=' | sed 's/.*length="\([^"]*\)".*/\1/')

echo "==> Generating appcast..."
PUB_DATE=$(date -R)

for FEED in appcast.xml appcast-beta.xml; do
    FEED_PATH="$DIST_DIR/$FEED"
    if [ "$FEED" = "appcast.xml" ] && [ "$BETA" = "beta" ]; then
        echo "    Skipping stable appcast (beta release)"
        continue
    fi

    python3 - "$FEED_PATH" "$VERSION" "$ZIP_NAME" "$SIGNATURE" "$LENGTH" "$PUB_DATE" << 'PYEOF'
import sys, os
feed_path, version, zip_name, sig, length, pub_date = sys.argv[1:7]
item = f"""        <item>
            <title>{version}</title>
            <pubDate>{pub_date}</pubDate>
            <sparkle:version>{version}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure url="https://github.com/lukasfroehlich1/weave/releases/download/v{version}/{zip_name}"
                       type="application/octet-stream"
                       sparkle:edSignature="{sig}"
                       length="{length}" />
        </item>"""
if not os.path.exists(feed_path):
    content = '''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Weave</title>
    </channel>
</rss>'''
else:
    content = open(feed_path).read()
content = content.replace("    </channel>", item + "\n    </channel>")
open(feed_path, "w").write(content)
PYEOF
    echo "    Updated $FEED"
done

echo "==> Creating GitHub release..."
TAG="v${VERSION}"
PRERELEASE_FLAG=""
if [ "$BETA" = "beta" ]; then
    PRERELEASE_FLAG="--prerelease"
fi

git tag -f "$TAG"
git push origin "$TAG" --force

gh release create "$TAG" "$ZIP_PATH" \
    --title "Weave ${VERSION}" \
    --generate-notes \
    $PRERELEASE_FLAG

echo "==> Uploading appcast files..."
if ! gh release view appcast >/dev/null 2>&1; then
    gh release create appcast --title "Appcast Feed" --notes "Sparkle update feed"
fi

for FEED in appcast.xml appcast-beta.xml; do
    FEED_PATH="$DIST_DIR/$FEED"
    if [ -f "$FEED_PATH" ]; then
        gh release upload appcast "$FEED_PATH" --clobber
    fi
done

if [ "$BETA" != "beta" ]; then
    echo "==> Updating Homebrew tap..."
    "$PROJECT_DIR/scripts/update-homebrew.sh" "$VERSION" "$ZIP_PATH"
else
    echo "==> Skipping Homebrew tap (beta release)"
fi

echo ""
echo "==> Done! Released Weave v${VERSION}"
echo "    GitHub: https://github.com/lukasfroehlich1/weave/releases/tag/${TAG}"
echo "    ZIP:    ${ZIP_PATH}"
