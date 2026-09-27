#!/bin/sh
set -eu

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

usage() {
    printf 'Usage: %s [archive.zip] [--no-run]\n' "$0"
    printf 'Install a local unsigned preview. The archive needs a matching .sha256 file.\n'
}

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
architecture=$(uname -m)
archive="$project_dir/dist/BlobbyCam-macos-$architecture-unsigned.zip"
run_after_install=1
archive_was_set=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-run)
            run_after_install=0
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *.zip)
            [ "$archive_was_set" -eq 0 ] || fail "Give only one ZIP archive."
            archive=$1
            archive_was_set=1
            ;;
        *)
            usage >&2
            fail "Unknown option or argument: $1"
            ;;
    esac
    shift
done

case "$(uname -s)" in
    Darwin) ;;
    *) fail "The preview installer can only run on macOS." ;;
esac

for tool in ditto shasum mktemp; do
    command -v "$tool" >/dev/null 2>&1 || fail "Required macOS tool not found: $tool"
done

case "$archive" in
    /*) ;;
    *) archive="$PWD/$archive" ;;
esac
[ -f "$archive" ] || fail "Preview ZIP not found: $archive. Build it with ./scripts/package-preview.sh first."

archive_name=$(basename -- "$archive")
archive_dir=$(CDPATH= cd -- "$(dirname -- "$archive")" && pwd) || fail "Could not open the archive folder: $(dirname -- "$archive")"
checksum_name="$archive_name.sha256"
checksum="$archive_dir/$checksum_name"
[ -f "$checksum" ] || fail "Checksum file not found: $checksum. Keep the .sha256 file next to the ZIP."

if ! (cd "$archive_dir" && shasum -a 256 -c "$checksum_name"); then
    fail "Checksum verification failed. The ZIP may be incomplete or changed; create a fresh preview package and try again."
fi

if [ -z "${BLOBBY_CAM_INSTALL_ROOT:-}" ]; then
    [ -n "${HOME:-}" ] || fail "HOME is not set. Set BLOBBY_CAM_INSTALL_ROOT to an install folder and try again."
    install_root="$HOME/.local"
else
    install_root=$BLOBBY_CAM_INSTALL_ROOT
fi
case "$install_root" in
    /*) ;;
    *) install_root="$PWD/$install_root" ;;
esac

app_parent="$install_root/share/blobby-cam"
app_destination="$app_parent/BlobbyCam.app"
bin_parent="$install_root/bin"
launcher="$bin_parent/blobby-cam"

mkdir -p "$app_parent" "$bin_parent" || fail "Could not create the install folders under: $install_root"
if [ -e "$app_destination" ] || [ -L "$app_destination" ]; then
    fail "Blobby Cam is already installed at: $app_destination. Remove that app folder before installing again."
fi
if [ -e "$launcher" ] || [ -L "$launcher" ]; then
    fail "A launcher already exists at: $launcher. Remove it before installing this preview."
fi

stage=$(mktemp -d "$app_parent/.install.XXXXXX") || fail "Could not create a temporary install folder under: $app_parent"
launcher_stage=
cleanup() {
    [ -z "$launcher_stage" ] || rm -f "$launcher_stage"
    [ -z "$stage" ] || rm -rf "$stage"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if ! ditto -x -k "$archive" "$stage"; then
    fail "Could not unpack the preview ZIP. Check that it is a valid, complete ZIP archive."
fi
app_executable="$stage/BlobbyCam.app/Contents/MacOS/BlobbyCam"
[ -f "$stage/BlobbyCam.app/Contents/Info.plist" ] || fail "Archive does not contain a complete BlobbyCam.app bundle."
[ -x "$app_executable" ] || fail "Archive is missing the runnable app at BlobbyCam.app/Contents/MacOS/BlobbyCam."

launcher_stage=$(mktemp "$bin_parent/.blobby-cam.XXXXXX") || fail "Could not prepare the launcher in: $bin_parent"
cat > "$launcher_stage" <<'LAUNCHER'
#!/bin/sh
set -eu
launcher_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$launcher_dir/../share/blobby-cam/BlobbyCam.app/Contents/MacOS/BlobbyCam" "$@"
LAUNCHER
chmod 755 "$launcher_stage" || fail "Could not make the launcher executable."

if ! mv "$stage/BlobbyCam.app" "$app_destination"; then
    fail "Could not install the app under: $app_parent"
fi
if ! mv "$launcher_stage" "$launcher"; then
    rm -rf "$app_destination"
    fail "The app was unpacked, but the launcher could not be installed at: $launcher"
fi
launcher_stage=

rm -rf "$stage"
stage=
trap - EXIT HUP INT TERM

printf 'Installed unsigned local preview.\nApp: %s\nLauncher: %s\n' "$app_destination" "$launcher"
if [ "$run_after_install" -eq 1 ]; then
    printf 'Starting Blobby Cam...\n'
    exec "$launcher"
fi

printf 'To launch it later, run: %s\n' "$launcher"
printf 'To use "blobby-cam" from any folder, add %s to your PATH.\n' "$bin_parent"
