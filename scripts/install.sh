#!/bin/sh
# Download a prebuilt GitHub preview. No Xcode, sudo, or shell-profile changes.
set -eu
fail() { printf 'Blobby Cam: %s\n' "$*" >&2; exit 1; }
repository=${1:-}
version=${2:-v0.1.0-preview.1}
no_run=${3:-}
[ -n "$repository" ] || fail 'Usage: install.sh OWNER/REPO [RELEASE_TAG] [--no-run]'
case "$repository" in *[!a-zA-Z0-9_./-]*|/*|*..*|*/|*/*/*) fail 'Invalid GitHub repository.';; */*) ;; *) fail 'Use OWNER/REPO.';; esac
case "$version" in ''|*[!a-zA-Z0-9._-]*) fail 'Invalid release tag.';; esac
case "$no_run" in ''|--no-run) ;; *) fail 'The third argument must be --no-run.';; esac
[ "$(uname -s)" = Darwin ] || fail 'This tiny creature needs macOS.'
# This preview is verified on Apple silicon; do not imply Intel support.
[ "$(uname -m)" = arm64 ] || fail 'This preview requires Apple silicon. Intel support has not been verified.'
for tool in curl ditto shasum mktemp; do command -v "$tool" >/dev/null 2>&1 || fail "Missing tool: $tool"; done
stage=$(mktemp -d "${TMPDIR:-/tmp}/blobby-download.XXXXXX")
cleanup() { rm -rf "$stage"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
archive_name=BlobbyCam-macos-arm64-unsigned.zip
base="https://github.com/$repository/releases/download/$version"
printf '\033[38;2;255;112;184m'
cat <<'BANNER'
     _           _
  __| | ___   __| | ___  _ __    ___  _ __   ___
 / _` |/ _ \ / _` |/ _ \| '_ \  / _ \| '_ \ / _ \
| (_| | (_) | (_| | (_) | | | || (_) | | | |  __/
 \__,_|\___/ \__,_|\___/|_| |_(_)___/|_| |_|\___|

     ヽ(◕‿◕)ノ         __
                    __/ o\_____.,>     hello from dodon.one!
                    \____________.-'
                    ~~~~~~~~~~~~~~~~~~~
BANNER
printf '\033[0mBLOBBY CAM — downloading %s...\n' "$version"

curl --fail --location --retry 2 --proto '=https' --tlsv1.2 "$base/$archive_name" -o "$stage/$archive_name" || fail 'Release download failed. Check the repository/tag and your connection.'
curl --fail --location --retry 2 --proto '=https' --tlsv1.2 "$base/$archive_name.sha256" -o "$stage/$archive_name.sha256" || fail 'Could not download the release checksum.'
# Accept exactly the expected archive's digest, rather than arbitrary paths in a manifest.
expected=$(awk -v name="$archive_name" 'NF == 2 && $2 == name && length($1) == 64 && $1 !~ /[^0-9a-fA-F]/ {print tolower($1)}' "$stage/$archive_name.sha256")
[ "${#expected}" -eq 64 ] || fail 'Invalid checksum file.'
actual=$(shasum -a 256 "$stage/$archive_name" | awk '{print $1}')
[ "$expected" = "$actual" ] || fail 'Checksum mismatch. Nothing was installed.'
mkdir "$stage/unpacked"
ditto -x -k "$stage/$archive_name" "$stage/unpacked" || fail 'Could not unpack release.'
[ -f "$stage/unpacked/install-preview.sh" ] || fail 'Release is missing its installer.'
if [ "$no_run" = --no-run ]; then
    sh "$stage/unpacked/install-preview.sh" "$stage/$archive_name" --no-run
else
    # A curl | sh pipe is not a TTY. Reattach stdin before launching the TUI.
    if [ -t 1 ] && [ -r /dev/tty ]; then
        sh "$stage/unpacked/install-preview.sh" "$stage/$archive_name" </dev/tty >/dev/tty
    else
        sh "$stage/unpacked/install-preview.sh" "$stage/$archive_name" --no-run
        printf 'No interactive Terminal attached; installed without launching.\n'
    fi
fi
