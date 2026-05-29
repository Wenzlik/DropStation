#!/bin/sh

# Xcode Cloud post-clone hook.
#
# Xcode Cloud expects to find `DropStation.xcodeproj` at the
# repository root immediately after cloning. This project uses
# XcodeGen — the `.xcodeproj` is gitignored and generated from
# `project.yml` — so the file isn't there until we make it.
#
# This script runs after the workspace is cloned and before any
# Xcode action. It installs XcodeGen via Homebrew (preinstalled on
# Xcode Cloud workers) and generates the project file from the
# YAML spec, so `Archive - iOS` (and any other Xcode Cloud
# workflow) can proceed normally.
#
# Local archives don't need this — developers run `xcodegen
# generate` themselves before opening Xcode. The script is
# specifically for the cloud build environment.

set -eu

echo "Xcode Cloud post-clone: bootstrapping DropStation.xcodeproj"
echo "  primary repository path: $CI_PRIMARY_REPOSITORY_PATH"
echo "  pwd before cd:           $(pwd)"

# Homebrew is preinstalled on Xcode Cloud workers. Install
# XcodeGen if it isn't already cached.
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "Installing XcodeGen via Homebrew…"
    brew install xcodegen
else
    echo "XcodeGen already on PATH: $(command -v xcodegen)"
fi

xcodegen --version

# Generate from the repo root. project.yml lives there.
cd "$CI_PRIMARY_REPOSITORY_PATH"
echo "  pwd after cd:            $(pwd)"

xcodegen generate

# Sanity check — fail loudly if the file we promised Xcode Cloud
# still isn't there. Saves a confusing "project does not exist"
# error later in the workflow.
if [ ! -d "DropStation.xcodeproj" ]; then
    echo "error: xcodegen ran but DropStation.xcodeproj was not produced"
    exit 1
fi

echo "Bootstrap complete: DropStation.xcodeproj is ready for Xcode Cloud."
