#!/usr/bin/env bash
set -e

echo "=== [1/3] Cleaning up Shell Configurations (~/.zshrc) ==="

ZSHRC="$HOME/.zshrc"
if [ -f "$ZSHRC" ]; then
  # Remove AI CLI Assistant configuration blocks
  sed -i '' '/# --- AI CLI ASSISTANT BASE ---/,/# --- END AI CLI ASSISTANT ---/d' "$ZSHRC" 2>/dev/null || true
  sed -i '' '/# --- OLLAMA CLI ASSISTANT CONFIG ---/,/# --- END GEMINI CLOUD EXTENSION ---/d' "$ZSHRC" 2>/dev/null || true
  sed -i '' '/# --- HYBRID AI CLI ASSISTANT ---/,/# --- END HYBRID AI CLI ASSISTANT ---/d' "$ZSHRC" 2>/dev/null || true
  echo "✅ Removed AI CLI Assistant functions and configs from $ZSHRC"
else
  echo "ℹ️  $ZSHRC not found. Skipping shell cleanup."
fi

echo "=== [2/3] Cleaning up AI Models & Secrets ==="

# 1. Clean Ollama Custom Models
if command -v ollama &>/dev/null; then
  echo "Checking Ollama models..."
  for model in ask-cli fix-cli; do
    if ollama list 2>/dev/null | grep -q "^$model"; then
      echo "Removing custom model: $model..."
      ollama rm "$model" 2>/dev/null || true
    fi
  done
  echo "✅ Cleaned up custom Ollama CLI models (ask-cli, fix-cli)."

  # Optional: Ask to remove Ollama completely
  read -r -p "Do you want to completely uninstall Ollama and its service? (y/N): " REMOVE_OLLAMA
  if [[ "$REMOVE_OLLAMA" =~ ^[Yy]$ ]]; then
    echo "Stopping Ollama service..."
    brew services stop ollama 2>/dev/null || pkill -x ollama 2>/dev/null || true
    if command -v brew &>/dev/null && brew list ollama &>/dev/null; then
      echo "Uninstalling Ollama via Homebrew..."
      brew uninstall ollama
    fi
    echo "✅ Ollama uninstalled."
  fi
fi

# 2. Clean Gemini API Key from ~/.env
ENV_FILE="$HOME/.env"
if [ -f "$ENV_FILE" ]; then
  if grep -q "^GEMINI_API_KEY=" "$ENV_FILE"; then
    read -r -p "Do you want to remove GEMINI_API_KEY from ~/.env? (y/N): " REMOVE_KEY
    if [[ "$REMOVE_KEY" =~ ^[Yy]$ ]]; then
      sed -i '' '/^GEMINI_API_KEY=/d' "$ENV_FILE"
      echo "✅ Removed GEMINI_API_KEY from $ENV_FILE"
      # If .env is now empty, offer to delete it
      if [ ! -s "$ENV_FILE" ]; then
        rm -f "$ENV_FILE"
        echo "ℹ️  $ENV_FILE was empty and has been removed."
      fi
    fi
  fi
fi

# 3. Clean up version tracking & config files
rm -f "$HOME/.afe_version" "$HOME/.afe_config" "$HOME/.afe_last_update_check" "$HOME/.afe_remote_version"

echo "=== [3/3] Uninstallation Complete! ==="
echo "To apply changes in your current terminal session, run:"
echo "source ~/.zshrc"
