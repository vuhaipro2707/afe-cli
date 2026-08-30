#!/usr/bin/env bash
set -e

echo "=================================================="
echo "           🚀 AFE CLI Universal Manager          "
echo "=================================================="

OS_TYPE="$(uname -s)"
if [ "$OS_TYPE" != "Darwin" ] && [ "$OS_TYPE" != "Linux" ]; then
  echo "❌ Unsupported operating system: $OS_TYPE"
  exit 1
fi

ACTION="$1"

# If no argument is provided, prompt interactively
if [ -z "$ACTION" ]; then
  echo ""
  echo "Please choose an action:"
  echo "  1) 🚀 Install / Update AFE CLI"
  echo "  2) 🗑️  Uninstall AFE CLI"
  echo "  3) 🚪 Exit"
  echo ""

  if [ -t 0 ]; then
    read -r -p "Enter your choice [1-3] (Default: 1): " USER_CHOICE
  elif { exec 3< /dev/tty; } 2>/dev/null; then
    read -r -p "Enter your choice [1-3] (Default: 1): " USER_CHOICE <&3
    exec 3<&-
  else
    read -r USER_CHOICE 2>/dev/null || USER_CHOICE="1"
  fi

  USER_CHOICE="${USER_CHOICE:-1}"

  case "$USER_CHOICE" in
    1|install|Install|INSTALL)
      ACTION="install"
      ;;
    2|uninstall|Uninstall|UNINSTALL)
      ACTION="uninstall"
      ;;
    3|exit|Exit|q|Q)
      echo "👋 Operation cancelled."
      exit 0
      ;;
    *)
      echo "⚠️  Invalid choice '$USER_CHOICE'. Defaulting to Install."
      ACTION="install"
      ;;
  esac
fi

# Normalize action argument
case "$ACTION" in
  install|--install|-i|1)
    ACTION="install"
    ;;
  uninstall|--uninstall|-u|2)
    ACTION="uninstall"
    ;;
  help|--help|-h)
    echo "Usage: $0 [install|uninstall]"
    exit 0
    ;;
  *)
    echo "❌ Unknown option: $ACTION"
    echo "Usage: $0 [install|uninstall]"
    exit 1
    ;;
esac

SCRIPT_DIR="$(dirname "$0")"

if [ "$ACTION" = "install" ]; then
  if [ "$OS_TYPE" = "Darwin" ]; then
    echo "🍏 Starting AFE CLI Installation for macOS..."
    if [ -f "$SCRIPT_DIR/macos.sh" ]; then
      bash "$SCRIPT_DIR/macos.sh"
    else
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/vuhaipro2707/afe-cli/main/macos.sh)"
    fi
  elif [ "$OS_TYPE" = "Linux" ]; then
    echo "🐧 Starting AFE CLI Installation for Linux..."
    if [ -f "$SCRIPT_DIR/linux.sh" ]; then
      bash "$SCRIPT_DIR/linux.sh"
    else
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/vuhaipro2707/afe-cli/main/linux.sh)"
    fi
  fi
elif [ "$ACTION" = "uninstall" ]; then
  if [ "$OS_TYPE" = "Darwin" ]; then
    echo "🍏 Starting AFE CLI Uninstallation for macOS..."
    if [ -f "$SCRIPT_DIR/uninstall_macos.sh" ]; then
      bash "$SCRIPT_DIR/uninstall_macos.sh"
    else
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/vuhaipro2707/afe-cli/main/uninstall_macos.sh)"
    fi
  elif [ "$OS_TYPE" = "Linux" ]; then
    echo "🐧 Starting AFE CLI Uninstallation for Linux..."
    if [ -f "$SCRIPT_DIR/uninstall_linux.sh" ]; then
      bash "$SCRIPT_DIR/uninstall_linux.sh"
    else
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/vuhaipro2707/afe-cli/main/uninstall_linux.sh)"
    fi
  fi
fi
