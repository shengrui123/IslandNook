#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
configuration="${1:-release}"
app_dir="$project_dir/dist/IslandNook.app"

cd "$project_dir"
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.build/swiftpm-cache"
build_args=(-c "$configuration" --disable-sandbox --jobs 2)
if [[ "$configuration" == "release" ]]; then
  build_args+=(-debug-info-format none)
fi
swift build "${build_args[@]}"
binary_dir="$(swift build -c "$configuration" --disable-sandbox --show-bin-path)"

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/IslandNook" "$app_dir/Contents/MacOS/IslandNook"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
if [[ -d "$binary_dir/IslandNook_IslandNook.bundle" ]]; then
  cp -R "$binary_dir/IslandNook_IslandNook.bundle" "$app_dir/Contents/Resources/"
fi
xattr -cr "$app_dir"
codesign --force --deep --sign - "$app_dir"
# File Provider may re-attach Finder metadata while signing inside a synced folder.
# These attributes are not part of the signature and make strict verification fail.
xattr -cr "$app_dir"
for item in "$app_dir" "$app_dir/Contents/Resources/IslandNook_IslandNook.bundle"; do
  xattr -d com.apple.FinderInfo "$item" 2>/dev/null || true
  xattr -d 'com.apple.fileprovider.fpfs#P' "$item" 2>/dev/null || true
done
codesign --verify --deep --strict "$app_dir"
echo "$app_dir"
