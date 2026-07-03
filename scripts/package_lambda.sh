#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/lambda"
ZIP_FILE="$ROOT_DIR/build/lambda.zip"
rm -rf "$ROOT_DIR/build"
mkdir -p "$BUILD_DIR"
# Build dependencies for the Lambda environment, not for the developer machine.
# Terraform uses Python 3.12 and Lambda defaults to Linux x86_64.
python3 -m pip install \
  --requirement "$ROOT_DIR/app/requirements.txt" \
  --target "$BUILD_DIR" \
  --platform manylinux2014_x86_64 \
  --implementation cp \
  --python-version 3.12 \
  --abi cp312 \
  --only-binary=:all: \
  --quiet
cp "$ROOT_DIR/app/main.py" "$BUILD_DIR/main.py"
cd "$BUILD_DIR"
zip -qr "$ZIP_FILE" .
echo "Created $ZIP_FILE"
