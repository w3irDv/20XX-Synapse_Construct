#!/bin/zsh
# Build Synapse ISO.command - double-click wrapper for Finder: asks for the source ISO, runs
# build-synapse-iso.zsh on it (output next to it as <name>.aionly.iso) and keeps the window open.
# Only built-in tools (osascript). See README.md.
cd -- "${0:A:h}" || exit 2
iso=$(osascript -e 'POSIX path of (choose file with prompt "Choose your clean Melee NTSC 1.02 ISO (.iso or .gcm)")' 2>/dev/null)
if [[ -z $iso ]]; then
    echo 'No ISO chosen.'
    read -k1 '?Press any key to close this window.'
    exit 1
fi
zsh ./build-synapse-iso.zsh --source "$iso"
rc=$?
echo
read -k1 "?Finished (exit code $rc). Press any key to close this window."
exit $rc
