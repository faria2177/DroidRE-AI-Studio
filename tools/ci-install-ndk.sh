#!/usr/bin/env bash
# Hosted Linux CI only: preinstall the NDK required by Flutter 3.47.4.
set -euo pipefail
[[ "$GITHUB_ACTIONS" == true && "$(uname -s)" == Linux ]] || {
    echo "This script is intended for hosted Linux GitHub Actions." >&2
    exit 1
}
sdk="$(realpath "${ANDROID_HOME:-${ANDROID_SDK_ROOT:?Android SDK missing}}")"
version=28.2.13676358
manager="$sdk/cmdline-tools/latest/bin/sdkmanager"
ndk="$sdk/ndk/$version"
[[ -x "$manager" && "$sdk" != / ]] || exit 1
valid() {
    [[ -f "$ndk/source.properties" && -x "$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-objdump" ]] &&
        grep -Eq "^Pkg.Revision[[:space:]]*=[[:space:]]*$version[[:space:]]*$" "$ndk/source.properties"
}
for attempt in 1 2 3; do
    if valid; then
        echo "NDK $version ready."
        exit 0
    fi
    echo "NDK installation attempt $attempt/3"
    # Clean only the known incomplete version on this disposable runner.
    if [[ -d "$ndk" && ! -L "$ndk" && "$(realpath "$ndk")" == "$ndk" ]]; then
        rm -rf -- "$ndk"
    fi
    if timeout 600 "$manager" --sdk_root="$sdk" --install "ndk;$version" && valid; then
        exit 0
    fi
    if [[ "$attempt" != 3 ]]; then sleep 10; fi
done
echo "NDK installation failed after three attempts." >&2
exit 1
