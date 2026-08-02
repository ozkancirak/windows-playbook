#!/usr/bin/env bash

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || exit 1
pushd "$script_dir" >/dev/null || exit 1
echo "Building Playbook..."
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$script_dir/build-playbook.ps1" -ReplaceOldPlaybook -DontOpenPbLocation
build_exit=$?
if [ "$build_exit" -ne 0 ]; then
    if [ "$#" -eq 0 ]; then
        read -p "Press Enter to exit...: "
    fi
fi
popd >/dev/null || exit 1
exit "$build_exit"
