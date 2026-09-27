#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
architecture=$(uname -m)
archive="$project_dir/dist/BlobbyCam-macos-$architecture-unsigned.zip"
run_after_install=1

for argument in "$@"; do
    case "$argument" in
        --no-run) run_after_install=0 ;;
        --help)
            printf 'Usage: %s [archive.zip] [--no-run]\n' "$0"
            exit 0
            ;;
        *.zip) archive=$argument ;;
        *)
            printf 'Unknown argument: %s\n' "$argument" >&2
            exit 2
            ;;
    esac
done

archive_dir=$(CDPATH= cd -- "$(dirname -- "$archive")" && pwd)
archive_name=$(basename -- "$archive")
checksum="$archive_dir/$archive_name.sha256"
test -f "$checksum" || { printf 'Missing checksum: %s\n' "$checksum" >&2; exit 1; }
(
    cd "$archive_dir"
    shasum -a 256 -c "$archive_name.sha256"
)

install_root=${BLOBBY_CAM_INSTALL_ROOT:-"$HOME/.local"}
app_parent="$install_root/share/blobby-cam"
app_destination="$app_parent/BlobbyCam.app"
launcher="$install_root/bin/blobby-cam"
mkdir -p "$app_parent" "$install_root/bin"
stage=$(mktemp -d "$app_parent/.install.XXXXXX")
trap 'rm -rf "$stage"' EXIT HUP INT TERM
ditto -x -k "$archive" "$stage"
test -x "$stage/BlobbyCam.app/Contents/MacOS/BlobbyCam" || {
    printf 'Archive does not contain BlobbyCam.app\n' >&2
    exit 1
}
if [ -e "$app_destination" ]; then
    printf 'Already installed at %s; remove it before installing this preview.\n' "$app_destination" >&2
    exit 1
fi
mv "$stage/BlobbyCam.app" "$app_destination"

cat > "$launcher" <<'LAUNCHER'
#!/bin/sh
set -eu
launcher_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$launcher_dir/../share/blobby-cam/BlobbyCam.app/Contents/MacOS/BlobbyCam" "$@"
LAUNCHER
chmod 755 "$launcher"

printf 'Installed app: %s\nLauncher: %s\n' "$app_destination" "$launcher"
if [ "$run_after_install" -eq 1 ]; then
    exec "$launcher"
fi
