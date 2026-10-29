#!/usr/bin/env bash
# Build the original Isar 3.1 migration reader, not the app's active store.
# Inputs: Android NDK directory and output jniLibs directory.
set -euo pipefail
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 NDK_DIRECTORY OUTPUT_DIRECTORY" >&2
  exit 2
fi
NDK="$1"
OUT="$2"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ISAR_COMMIT=6643d064abf22606b6c6a741ea873e4781115ef4
MDBX_COMMIT=53177e483c18adf5109aed7a5895915e9798ee24
RUST=1.99.1
case "$(uname -s)" in
  Linux) HOST=linux-x86_64 ;;
  Darwin) HOST=darwin-x86_64 ;;
  *) echo 'Legacy Isar Android builds require a Linux or macOS host with Bash.' >&2; exit 1 ;;
esac
BIN="$NDK/toolchains/llvm/prebuilt/$HOST/bin"
test -x "$BIN/llvm-ar" || { echo "Android NDK toolchain missing: $BIN" >&2; exit 1; }
command -v rustup >/dev/null || { echo "Install rustup and Rust $RUST" >&2; exit 1; }
rustup run "$RUST" rustc --version >/dev/null || { echo "Install Rust $RUST with rustup" >&2; exit 1; }
rustup target add --toolchain "$RUST" aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
WORK="$ROOT/build/legacy_isar_source"
mkdir -p "$WORK" "$OUT"
if [[ ! -d "$WORK/isar/.git" ]]; then
  git clone --no-checkout https://github.com/isar/isar.git "$WORK/isar"
fi
git -C "$WORK/isar" fetch --depth 1 origin "$ISAR_COMMIT"
git -C "$WORK/isar" checkout --detach --force "$ISAR_COMMIT"
if [[ ! -d "$WORK/libmdbx/.git" ]]; then
  git clone --no-checkout https://github.com/isar/libmdbx.git "$WORK/libmdbx"
fi
git -C "$WORK/libmdbx" fetch --depth 1 origin tag v0.12.4
git -C "$WORK/libmdbx" checkout --detach --force "$MDBX_COMMIT"
[[ "$(git -C "$WORK/libmdbx" rev-parse 'v0.12.4^{commit}')" == "$MDBX_COMMIT" ]] || { echo 'Unexpected libmdbx tag revision' >&2; exit 1; }
cp "$ROOT/tool/legacy_isar/Cargo.lock" "$WORK/isar/Cargo.lock"
# Upstream build.rs downloads an unchecked tag itself. Clone our verified
# local repository instead, keeping its original 0.12.4 source and build.
python3 - "$WORK/isar/packages/mdbx_sys/build.rs" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = '.arg(LIBMDBX_REPO)'
assert s.count(old) == 1
p.write_text(s.replace(old, '.arg(std::env::var("ISAR_PINNED_MDBX_REPO").expect("missing pinned MDBX repository"))'))
PY
export ISAR_PINNED_MDBX_REPO="$WORK/libmdbx"
export CARGO_TARGET_DIR="$WORK/target"
export RUSTFLAGS='-C link-arg=-Wl,-z,max-page-size=16384'
for spec in \
  'aarch64-linux-android arm64-v8a aarch64-linux-android21-clang' \
  'armv7-linux-androideabi armeabi-v7a armv7a-linux-androideabi21-clang' \
  'x86_64-linux-android x86_64 x86_64-linux-android21-clang'; do
  read -r target abi compiler <<< "$spec"
  key="${target//-/_}"
  upper="${key^^}"
  export "CC_${key}=$BIN/$compiler" "AR_${key}=$BIN/llvm-ar"
  export "CARGO_TARGET_${upper}_LINKER=$BIN/$compiler"
  clang_target="${compiler%-clang}"
  export BINDGEN_EXTRA_CLANG_ARGS="--target=$clang_target --sysroot=$NDK/toolchains/llvm/prebuilt/$HOST/sysroot"
  (cd "$WORK/isar" && cargo +"$RUST" build --locked --release --package isar --target "$target")
  mkdir -p "$OUT/$abi"
  cp "$CARGO_TARGET_DIR/$target/release/libisar.so" "$OUT/$abi/libisar.so"
done
