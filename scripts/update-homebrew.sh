#!/bin/bash
set -euo pipefail

VERSION="${1:?Usage: scripts/update-homebrew.sh <version>}"
ZIP_PATH="${2:?Usage: scripts/update-homebrew.sh <version> <zip-path>}"

SHA=$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')

TEMP=$(mktemp -d)
git clone https://github.com/lukasfroehlich1/homebrew-tap "$TEMP" 2>/dev/null

cat > "$TEMP/Casks/weave.rb" << EOF
cask "weave" do
  version "${VERSION}"
  sha256 "${SHA}"

  url "https://github.com/lukasfroehlich1/weave/releases/download/v#{version}/Weave-#{version}.zip"
  name "Weave"
  desc "Native macOS git worktree manager with embedded terminals"
  homepage "https://github.com/lukasfroehlich1/weave"

  depends_on macos: ">= :sonoma"

  app "Weave.app"

  zap trash: [
    "~/.weave",
    "~/.config/weave",
  ]
end
EOF

cd "$TEMP"
git add -A
git commit -m "Update weave to ${VERSION}"
git push origin main
rm -rf "$TEMP"

echo "Homebrew tap updated to v${VERSION}"
