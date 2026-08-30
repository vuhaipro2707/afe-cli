#!/usr/bin/env bash
set -e

echo "=================================================="
echo "           🚀 AFE CLI Universal Installer        "
echo "=================================================="

OS_TYPE="$(uname -s)"

if [ "$OS_TYPE" = "Darwin" ]; then
  echo "🍏 Detected macOS environment."
  if [ -f "$(dirname "$0")/macos.sh" ]; then
    bash "$(dirname "$0")/macos.sh"
  else
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/vuhaipro2707/afe-cli/main/macos.sh)"
  fi
elif [ "$OS_TYPE" = "Linux" ]; then
  echo "🐧 Detected Linux environment."
  if [ -f "$(dirname "$0")/linux.sh" ]; then
    bash "$(dirname "$0")/linux.sh"
  else
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/vuhaipro2707/afe-cli/main/linux.sh)"
  fi
else
  echo "❌ Unsupported operating system: $OS_TYPE"
  exit 1
fi
