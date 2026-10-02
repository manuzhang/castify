#!/bin/sh
set -eu

# Pin the generator and official release checksum for repeatable output.
generator_version=2.46.0
generator_checksum=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
generator_cache=${XCODEGEN_CACHE_DIR:-${TMPDIR:-/tmp}/castify-xcodegen-$generator_version}
generator_archive=$generator_cache/xcodegen.zip
generator_binary=$generator_cache/xcodegen/bin/xcodegen
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

mkdir -p "$generator_cache"
if [ ! -f "$generator_archive" ]; then
  curl --fail --location --retry 3 \
    "https://github.com/yonaskolb/XcodeGen/releases/download/$generator_version/xcodegen.zip" \
    --output "$generator_archive.tmp"
  mv "$generator_archive.tmp" "$generator_archive"
fi
printf '%s  %s\n' "$generator_checksum" "$generator_archive" | shasum -a 256 -c -
unzip -q -o "$generator_archive" -d "$generator_cache"

cd "$task_root"
"$generator_binary" generate --spec project.yml
