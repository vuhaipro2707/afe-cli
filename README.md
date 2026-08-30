# 🚀 AFE CLI (Ask • Fix • Explain)

> **Zero-latency, lightweight, native AI assistant integrated directly into your Terminal.**  
> Convert natural language into commands, auto-diagnose errors from your screen, and explain complex commands with zero context switching.

<p align="center">
  <img src="https://github.com/vuhaipro2707/afe-cli/blob/main/assets/demo-afe.gif?raw=true" alt="AFE CLI Demo" width="100%" />
</p>

---

## ✨ Features

- ⚡ **Zero Context Switching**: Ask AI, fix errors, and explain technical commands without ever leaving your terminal.
- ☁️ **Hybrid Architecture**:
  - **Cloud Mode**: Ultra-fast responses powered by **Google Gemini API** (Streaming output, minimal latency).
  - **Local Mode**: 100% private, offline assistant powered by **Ollama** (e.g., `gemma4:e2b`, `qwen2.5-coder`).
- ⌨️ **Smart Paste (`Ctrl + G`)**: Instantly pastes the generated command directly at your cursor position—no mouse copy-pasting required.
- 🛡️ **Collision-Proof**: Automatically detects if short command names (`a`, `f`, `fe`, `e`) already exist on your system and falls back to safe prefixes (`afe-a`, `afe-f`, etc.).
- 🌐 **Multilingual Support**: Supports English, Vietnamese, or any custom language for technical explanations.
- 🪶 **100% Pure Shell**: Zero background daemon overhead, zero RAM consumption when idle, instant shell startup (0ms).

---

## ⚡ Quick Install

### Option 1: One-Line cURL Install (Fastest - Like Homebrew/nvm)
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/vuhaipro2707/afe-cli/main/install.sh)"
```

### Option 2: Git Clone & Run
```bash
git clone https://github.com/vuhaipro2707/afe-cli.git ~/.afe-cli
cd ~/.afe-cli && bash install.sh
```

### Option 3: Run Direct Script
- **macOS**:
  ```bash
  bash macos.sh
  ```
- **Linux** (Ubuntu, Debian, Fedora, Arch):
  ```bash
  bash linux.sh
  ```

After installation finishes, activate it immediately in your current terminal:
```bash
source ~/.zshrc    # or source ~/.bashrc on Linux
```

---

## 📖 Command Cheat Sheet (`afe-help`)

Run `afe-help` (or `ai-help` / `ai`) at any time to view the interactive manual:

```text
╭──────────────────────────────────────────────────────────────────────────╮
│                             🚀 AFE CLI Help                              │
╰──────────────────────────────────────────────────────────────────────────╯

  ☁️  Cloud Commands (Gemini API):
    a <request>       Generate executable terminal command from prompt
    f [question]      Generate fix command for the last failed command
    fe [question]     Explain root cause & fix for the last error concisely
    e [command]       Explain command manual (default: last AI generated cmd)

  💻 Local Commands (Ollama Offline):
    al <request>      Generate command using Ollama local model
    alt <request>     Generate command with live thinking stream
    fl [question]     Generate fix command using Ollama local
    flt [question]    Generate fix command with live thinking stream
    el [command]      Explain command manual using Ollama local

  ⌨️  Shortcuts & Tips:
    Ctrl + G          Paste last AI generated command at cursor position
    e / el (no args)  Directly explain the command that AI just suggested

  ℹ️  Help & Info:
    afe-help          Display this help message
────────────────────────────────────────────────────────────────────────────
```

---

## 💡 Practical Workflows

### 1. Generate & Run a Command
```bash
$ a create a docker container for postgresql on port 5432
docker run -d --name postgres-db -p 5432:5432 -e POSTGRES_PASSWORD=mysecretpassword postgres

$ [Press Ctrl + G]   <-- Command is instantly pasted at cursor
$ docker run -d --name postgres-db -p 5432:5432 -e POSTGRES_PASSWORD=mysecretpassword postgres [Press Enter]
```

### 2. Auto-Fix a Failed Command
```bash
$ python3 app.py
ModuleNotFoundError: No module named 'fastapi'

$ f                  <-- AI reads the error directly from your screen
pip install fastapi

$ [Press Ctrl + G]   <-- Paste and run immediately
$ pip install fastapi
```

### 3. Explain Error & Cause Concurrently
```bash
$ git push origin main
! [rejected] main -> main (fetch first)

$ fe                 <-- Short 2-line root cause and fix
Cause: Remote repository has commits that your local branch does not have.
Fix: git pull --rebase origin main && git push origin main
```

### 4. Explain Any Command or Concept
```bash
# Explain a command:
$ e iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080

# Or explain the command AI just suggested (without typing anything):
$ a find files larger than 100MB
find . -type f -size +100M

$ e                  <-- Automatically explains the command above!
```

---

## ⚙️ Configuration

Your settings are securely stored in your shell profile (`~/.zshrc` or `~/.bashrc`) and `~/.env`:

| Setting | Location | Description |
| :--- | :--- | :--- |
| `GEMINI_API_KEY` | `~/.env` | Your Google Gemini API Key (chmod 600) |
| `GEMINI_MODEL_ID` | `~/.zshrc` / `~/.bashrc` | Cloud model (default: `gemma-4-26b-a4b-it`) |
| `AI_RESPONSE_LANG` | `~/.zshrc` / `~/.bashrc` | Response language (`English`, `Vietnamese`, etc.) |

---

## 🗑️ Uninstallation

To completely remove AFE CLI and restore your shell to its original state:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/vuhaipro2707/afe-cli/main/install.sh)" -- uninstall
```

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details. Free for personal and commercial use.
