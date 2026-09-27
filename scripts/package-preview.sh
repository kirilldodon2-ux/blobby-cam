#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
architecture=$(uname -m)
derived_data="$project_dir/.build/DerivedData-Release"
app="$derived_data/Build/Products/Release/BlobbyCam.app"
package_dir="$project_dir/dist"
archive_name="BlobbyCam-macos-$architecture-unsigned.zip"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
    xcodebuild -quiet \
        -project "$project_dir/BlobbyCam.xcodeproj" \
        -scheme BlobbyCam \
        -configuration Release \
        -destination "platform=macOS,arch=$architecture" \
        -derivedDataPath "$derived_data" \
        CODE_SIGNING_ALLOWED=NO \
        build

test -x "$app/Contents/MacOS/BlobbyCam"
mkdir -p "$package_dir"
rm -f "$package_dir/$archive_name" "$package_dir/$archive_name.sha256"
ditto -c -k --keepParent "$app" "$package_dir/$archive_name"
(
    cd "$package_dir"
    shasum -a 256 "$archive_name" > "$archive_name.sha256"
)

printf 'Unsigned developer preview: %s\n' "$package_dir/$archive_name"
du -sh "$app" "$package_dir/$archive_name"
