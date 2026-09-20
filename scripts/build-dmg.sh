#!/bin/bash
set -euo pipefail

# Xcode owns the app version, deployment target and entitlements.
# The tag is only the release/asset identifier.
release_tag="${1:?Usage: bash scripts/build-dmg.sh <tag>}"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
asset_tag="$(printf '%s' "$release_tag" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/ratiocrop-release.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

xcodebuild -version
xcodebuild \
  -project ImageAspectCropper.xcodeproj \
  -scheme ImageAspectCropper \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$work_dir/DerivedData" \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  build

app_path="$work_dir/DerivedData/Build/Products/Release/ImageAspectCropper.app"
codesign --verify --deep --strict "$app_path"
architectures="$(xcrun lipo -archs "$app_path/Contents/MacOS/ImageAspectCropper")"
for architecture in arm64 x86_64; do
  if [[ " $architectures " != *" $architecture "* ]]; then
    printf 'Missing architecture: %s\n' "$architecture" >&2
    exit 1
  fi
done

mkdir -p "$work_dir/dmg" "$repo_root/dist"
ditto "$app_path" "$work_dir/dmg/RatioCrop.app"
ln -s /Applications "$work_dir/dmg/Applications"
dmg_name="RatioCrop-${asset_tag}-universal.dmg"
hdiutil create \
  -volname RatioCrop \
  -srcfolder "$work_dir/dmg" \
  -format UDZO \
  -ov "$repo_root/dist/$dmg_name"
hdiutil verify "$repo_root/dist/$dmg_name"
cd "$repo_root/dist"
shasum -a 256 "$dmg_name" > "$dmg_name.sha256"
printf 'Created %s\n' "$repo_root/dist/$dmg_name"
