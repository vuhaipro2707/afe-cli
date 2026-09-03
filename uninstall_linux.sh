#!/usr/bin/env bash
set -e

echo "=== [1/3] Cleaning up Shell Profile Configurations ==="

# Check both .bashrc and .zshrc
RC_FILES=()
[[ -f "$HOME/.bashrc" ]] && RC_FILES+=("$HOME/.bashrc")
[[ -f "$HOME/.zshrc" ]] && RC_FILES+=("$HOME/.zshrc")

for rc in "${RC_FILES[@]}"; do
  # Remove AI CLI Assistant configuration blocks
  sed -i '/# --- AI CLI ASSISTANT BASE ---/,/# --- END AI CLI ASSISTANT ---/d' "$rc" 2>/dev/null || true
  sed -i '/# --- GEMINI LINUX CLI ASSISTANT ---/,/# --- END GEMINI LINUX CLI ASSISTANT ---/d' "$rc" 2>/dev/null || true
  sed -i '/# --- OLLAMA LOCAL EXTENSION ---/,/# --- END GEMINI CLOUD EXTENSION ---/d' "$rc" 2>/dev/null || true
  echo "✅ Removed AI CLI Assistant functions and configs from $rc"
done

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

  # Optional: Ask to remove Ollama service/binary
  read -r -p "Do you want to completely stop and remove Ollama from Linux? (y/N): " REMOVE_OLLAMA
  if [[ "$REMOVE_OLLAMA" =~ ^[Yy]$ ]]; then
    echo "Stopping Ollama service..."
    sudo systemctl stop ollama 2>/dev/null || pkill -x ollama 2>/dev/null || true
    sudo systemctl disable ollama 2>/dev/null || true
    
    echo "Removing Ollama binary and service files..."
    sudo rm -f /usr/local/bin/ollama /usr/bin/ollama
    sudo rm -f /etc/systemd/system/ollama.service
    sudo systemctl daemon-reload 2>/dev/null || true
    echo "✅ Ollama completely removed."
  fi
fi

# 2. Clean Gemini API Key from ~/.env
ENV_FILE="$HOME/.env"
if [ -f "$ENV_FILE" ]; then
  if grep -q "^GEMINI_API_KEY=" "$ENV_FILE"; then
    read -r -p "Do you want to remove GEMINI_API_KEY from ~/.env? (y/N): " REMOVE_KEY
    if [[ "$REMOVE_KEY" =~ ^[Yy]$ ]]; then
      sed -i '/^GEMINI_API_KEY=/d' "$ENV_FILE"
      echo "✅ Removed GEMINI_API_KEY from $ENV_FILE"
      # If .env is now empty, remove it
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
if [[ -n "$ZSH_VERSION" ]] || [[ "$SHELL" == *"zsh"* ]]; then
  echo "source ~/.zshrc"
else
  echo "source ~/.bashrc"
fi
