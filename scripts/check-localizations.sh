#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/flowshelf-localization.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT HUP INT TERM
swiftc Sources/FlowShelf/Util/Localization.swift scripts/check-localizations.swift -o "$check_dir/check-localizations"
"$check_dir/check-localizations"
