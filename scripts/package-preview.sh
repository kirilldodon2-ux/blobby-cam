#!/bin/sh
set -eu

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
case "$(uname -s)" in
    Darwin) ;;
    *) fail "Preview packages can only be built on macOS." ;;
esac

architecture=$(uname -m)
case "$architecture" in
    arm64|x86_64) ;;
    *) fail "Unsupported Mac architecture: $architecture" ;;
esac

command -v xcodebuild >/dev/null 2>&1 || fail "Full Xcode is required to build the preview. Install Xcode and select it with xcode-select, or set DEVELOPER_DIR."
command -v shasum >/dev/null 2>&1 || fail "shasum is required to create the package checksum."

if [ -n "${DEVELOPER_DIR:-}" ]; then
    developer_dir=$DEVELOPER_DIR
    [ -d "$developer_dir" ] || fail "Xcode developer directory does not exist: $developer_dir"
    DEVELOPER_DIR="$developer_dir" xcodebuild -version >/dev/null 2>&1 || \
        fail "DEVELOPER_DIR does not point to a full Xcode installation: $developer_dir"
else
    selected_developer_dir=
    if command -v xcode-select >/dev/null 2>&1; then
        selected_developer_dir=$(xcode-select -p 2>/dev/null || true)
    fi
    if [ -n "$selected_developer_dir" ] && \
        DEVELOPER_DIR="$selected_developer_dir" xcodebuild -version >/dev/null 2>&1; then
        developer_dir=$selected_developer_dir
    elif [ -d "/Applications/Xcode.app/Contents/Developer" ] && \
        DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild -version >/dev/null 2>&1; then
        developer_dir="/Applications/Xcode.app/Contents/Developer"
    else
        fail "Full Xcode is required. Select Xcode with xcode-select -s /Applications/Xcode.app/Contents/Developer, or set DEVELOPER_DIR to Xcode.app/Contents/Developer."
    fi
fi

derived_data="$project_dir/.build/DerivedData-Release"
app="$derived_data/Build/Products/Release/BlobbyCam.app"
package_dir="$project_dir/dist"
archive_name="BlobbyCam-macos-$architecture-unsigned.zip"

if ! DEVELOPER_DIR="$developer_dir" xcodebuild -quiet \
        -project "$project_dir/BlobbyCam.xcodeproj" \
        -scheme BlobbyCam \
        -configuration Release \
        -destination "platform=macOS,arch=$architecture" \
        -derivedDataPath "$derived_data" \
        CODE_SIGNING_ALLOWED=NO \
        build; then
    fail "Xcode could not build the unsigned preview. Check the Xcode installation and try again."
fi

[ -x "$app/Contents/MacOS/BlobbyCam" ] || fail "Xcode finished without producing the Blobby Cam app at: $app"
mkdir -p "$package_dir"
stage=$(mktemp -d "$package_dir/.package.XXXXXX") || fail "Could not create a temporary package folder in: $package_dir"
cleanup() {
    rm -rf "$stage"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if ! ditto -c -k --keepParent "$app" "$stage/$archive_name"; then
    fail "Could not create the preview ZIP. Check that the app build is complete and the disk has space."
fi
(
    cd "$stage"
    shasum -a 256 "$archive_name" > "$archive_name.sha256"
)

rm -f "$package_dir/$archive_name" "$package_dir/$archive_name.sha256"
mv "$stage/$archive_name" "$package_dir/$archive_name"
mv "$stage/$archive_name.sha256" "$package_dir/$archive_name.sha256"

printf 'Unsigned local preview package created. It is not a public release.\nZIP: %s\nSHA-256: %s\n' \
    "$package_dir/$archive_name" "$package_dir/$archive_name.sha256"
du -sh "$app" "$package_dir/$archive_name"
