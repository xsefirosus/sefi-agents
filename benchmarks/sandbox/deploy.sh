#!/usr/bin/env bash
# deploy.sh -- frozen benchmark sandbox fixture for case sh-strict-mode.
# Starting (pre-task) state: no strict-mode line. A completed trial adds one.

TARGET_DIR="${1:-./dist}"

mkdir -p "$TARGET_DIR"
cp -r ./build/. "$TARGET_DIR/"
echo "deployed to $TARGET_DIR"
