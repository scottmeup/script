#!/usr/bin/env bash
# Project flow: loads the environment file, downloads and verifies Android NDK r29, clones the pinned Android Dropbear build project, applies an additive Cronos localoptions overlay, runs its Android build, locates the ARMv7 Dropbear server, and writes a verified output manifest.
# Inputs: dropbear-cronos-bootstrap.env; internet access; bash, git, curl or wget, unzip, sha1sum, file, strings, md5sum; BUILD_ROOT, ANDROID_NDK_URL, ANDROID_NDK_SHA1, ANDROID_DROPBEAR_REPOSITORY, ANDROID_DROPBEAR_REF, DEFAULT_ROOT_PATH, and SFTP_WRAPPER configuration entries.
# Outputs: $BUILD_ROOT/output/dropbear; $BUILD_ROOT/output/build-manifest.txt; downloaded NDK and cloned Android build source below BUILD_ROOT.
# Functions: fail exits with an error; require checks prerequisites; fetch downloads without replacing a valid cached file; verify_sha1 validates the NDK; find_server selects an ARMv7 Dropbear server artifact; validate_binary checks architecture and embedded configuration.
# Side effects: creates only BUILD_ROOT content; it does not contact or modify the Echo.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ENV_FILE=${ENV_FILE:-$SCRIPT_DIR/dropbear-cronos-bootstrap.env}
[ -f "$ENV_FILE" ] || { echo "ERROR: missing $ENV_FILE" >&2; exit 1; }
set -a
. "$ENV_FILE"
set +a
fail(){ echo "ERROR: $*" >&2; exit 1; }
require(){ command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"; }
fetch(){
    url=$1
    destination=$2
    [ -s "$destination" ] && return 0
    if command -v curl >/dev/null 2>&1; then curl -fL --retry 3 -o "$destination.part" "$url"; else wget -O "$destination.part" "$url"; fi
    mv "$destination.part" "$destination"
}
verify_sha1(){ printf '%s  %s\n' "$2" "$1" | sha1sum -c -; }
find_server(){
    local candidate identity

    while IFS= read -r -d '' candidate; do
        identity=$(file "$candidate" 2>/dev/null || true)

        if printf '%s\n' "$identity" | grep -q 'ELF 32-bit.*ARM'; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done < <(find "$BUILD_ROOT/android-dropbear" -type f -name dropbear -print0)

    return 1
}
validate_binary(){
    binary=$1
    file "$binary" | grep -q 'ELF 32-bit.*ARM' || fail "output is not 32-bit ARM"
    strings "$binary" | grep -F "$DEFAULT_ROOT_PATH" >/dev/null || fail "compiled root PATH not found"
    strings "$binary" | grep -F "$SFTP_WRAPPER" >/dev/null || fail "compiled SFTP wrapper path not found"
}
for command_name in bash git unzip sha1sum file strings md5sum awk sed grep find; do require "$command_name"; done
command -v curl >/dev/null 2>&1 || require wget
mkdir -p "$BUILD_ROOT/downloads" "$BUILD_ROOT/toolchain" "$BUILD_ROOT/output"
NDK_ARCHIVE=$BUILD_ROOT/downloads/android-ndk-$ANDROID_NDK_VERSION-linux.zip
fetch "$ANDROID_NDK_URL" "$NDK_ARCHIVE"
verify_sha1 "$NDK_ARCHIVE" "$ANDROID_NDK_SHA1"
NDK_DIR=$BUILD_ROOT/toolchain/android-ndk-$ANDROID_NDK_VERSION
if [ ! -x "$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin/${ANDROID_TARGET}${ANDROID_API}-clang" ]; then
    rm -rf "$NDK_DIR"
    unzip -q "$NDK_ARCHIVE" -d "$BUILD_ROOT/toolchain"
fi
[ -x "$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin/${ANDROID_TARGET}${ANDROID_API}-clang" ] || fail "NDK ARM compiler missing"
if [ ! -d "$BUILD_ROOT/android-dropbear/.git" ]; then
    git clone --branch "$ANDROID_DROPBEAR_REF" --depth 1 "$ANDROID_DROPBEAR_REPOSITORY" "$BUILD_ROOT/android-dropbear"
else
    git -C "$BUILD_ROOT/android-dropbear" fetch --depth 1 origin "$ANDROID_DROPBEAR_REF"
    git -C "$BUILD_ROOT/android-dropbear" checkout --detach FETCH_HEAD
fi
git -C "$BUILD_ROOT/android-dropbear" reset --hard HEAD
SOURCE=$BUILD_ROOT/android-dropbear
cp "$SOURCE/localoptions.h" "$SOURCE/localoptions.h.before-cronos" 2>/dev/null || true
cat >> "$SOURCE/localoptions.h" <<OPTIONS

#undef DEFAULT_ROOT_PATH
#define DEFAULT_ROOT_PATH "$DEFAULT_ROOT_PATH"
#undef DEFAULT_PATH
#define DEFAULT_PATH "$DEFAULT_ROOT_PATH"
#undef DROPBEAR_SFTPSERVER
#define DROPBEAR_SFTPSERVER 1
#undef SFTPSERVER_PATH
#define SFTPSERVER_PATH "$SFTP_WRAPPER"
OPTIONS
export ANDROID_NDK_HOME=$NDK_DIR
export ANDROID_HOME=${ANDROID_HOME:-$BUILD_ROOT/android-sdk-placeholder}
export ANDROID_API
export MIN_SDK_VERSION=$ANDROID_API
cd "$SOURCE"
./build
SERVER=$(find_server) || fail "ARMv7 Dropbear server artifact not found"
install -m 0755 "$SERVER" "$BUILD_ROOT/output/dropbear"
validate_binary "$BUILD_ROOT/output/dropbear"
{
    printf 'android_dropbear_ref=%s\n' "$ANDROID_DROPBEAR_REF"
    printf 'android_dropbear_commit=%s\n' "$(git -C "$SOURCE" rev-parse HEAD)"
    printf 'ndk_version=%s\nandroid_api=%s\n' "$ANDROID_NDK_VERSION" "$ANDROID_API"
    printf 'source_artifact=%s\n' "$SERVER"
    file "$BUILD_ROOT/output/dropbear"
    md5sum "$BUILD_ROOT/output/dropbear"
    printf 'default_root_path=%s\nsftp_wrapper=%s\n' "$DEFAULT_ROOT_PATH" "$SFTP_WRAPPER"
} > "$BUILD_ROOT/output/build-manifest.txt"
echo "PASS: candidate Dropbear built at $BUILD_ROOT/output/dropbear"
