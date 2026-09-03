#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo ".")"
AFE_VERSION="1.1.7"
if [ -f "$SCRIPT_DIR/version" ]; then
  AFE_VERSION="1.1.7"
else
  REMOTE_VER="$(curl -fsSL https://raw.githubusercontent.com/vuhaipro2707/afe-cli/main/version 2>/dev/null | tr -d '[:space:]' || true)"
  if [ -n "$REMOTE_VER" ]; then
    AFE_VERSION="1.1.7"
  fi
fi
echo "$AFE_VERSION" > "$HOME/.afe_version" 2>/dev/null || true

echo "=== [1/4] Checking Linux environment & dependencies ==="

# Install curl, python3 if missing
MISSING_PKGS=()
for pkg in curl python3; do
  if ! command -v "$pkg" &>/dev/null; then
    MISSING_PKGS+=("$pkg")
  fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
  echo "Installing missing packages: ${MISSING_PKGS[*]}..."
  if command -v apt-get &>/dev/null; then
    sudo apt-get update && sudo apt-get install -y "${MISSING_PKGS[@]}"
  elif command -v dnf &>/dev/null; then
    sudo dnf install -y "${MISSING_PKGS[@]}"
  elif command -v pacman &>/dev/null; then
    sudo pacman -Sy --noconfirm "${MISSING_PKGS[@]}"
  else
    echo "⚠️  Unrecognized package manager. Please manually install: ${MISSING_PKGS[*]}"
  fi
fi

echo "=== [2/4] Installation options ==="

AFE_CONFIG_FILE="$HOME/.afe_config"
USE_SAVED_CONFIG=false

SAVED_INSTALL_OLLAMA="false"
SAVED_INSTALL_GEMINI="false"
SAVED_AI_LANG="English"
SAVED_BASE_MODEL="gemma4:e2b"
SAVED_CLOUD_MODEL="gemma-4-26b-a4b-it"

if [ -f "$AFE_CONFIG_FILE" ]; then
  # shellcheck source=/dev/null
  source "$AFE_CONFIG_FILE" 2>/dev/null || true
  SAVED_INSTALL_OLLAMA="${INSTALL_OLLAMA:-false}"
  SAVED_INSTALL_GEMINI="${INSTALL_GEMINI:-false}"
  SAVED_AI_LANG="${AI_RESPONSE_LANG:-English}"
  SAVED_BASE_MODEL="${OLLAMA_MODEL:-gemma4:e2b}"
  SAVED_CLOUD_MODEL="${GEMINI_MODEL:-gemma-4-26b-a4b-it}"

  echo "📋 Found existing configuration:"
  echo "  • Local AI (Ollama) : $([ "$SAVED_INSTALL_OLLAMA" = true ] && echo "Enabled ($SAVED_BASE_MODEL)" || echo "Disabled")"
  echo "  • Gemini Cloud      : $([ "$SAVED_INSTALL_GEMINI" = true ] && echo "Enabled ($SAVED_CLOUD_MODEL)" || echo "Disabled")"
  echo "  • AI Language       : $SAVED_AI_LANG"
  echo ""
  read -r -p "Use existing configuration? [Y/n] (Default: Y): " CONFIRM_SAVED
  if [[ -z "$CONFIRM_SAVED" || "$CONFIRM_SAVED" =~ ^[Yy]$ ]]; then
    USE_SAVED_CONFIG=true
    INSTALL_OLLAMA_FLAG="$SAVED_INSTALL_OLLAMA"
    INSTALL_GEMINI_FLAG="$SAVED_INSTALL_GEMINI"
    AI_RESPONSE_LANG="$SAVED_AI_LANG"
    BASE_MODEL="$SAVED_BASE_MODEL"
    USER_GEMINI_MODEL="$SAVED_CLOUD_MODEL"
  fi
fi

if [ "$USE_SAVED_CONFIG" = false ]; then
  # Ask to install Ollama Local
  local_ollama_prompt="y/N"
  [ "$SAVED_INSTALL_OLLAMA" = true ] && local_ollama_prompt="Y/n"
  read -r -p "Do you want to install Local AI (Ollama)? ($local_ollama_prompt): " INSTALL_OLLAMA
  if [ "$SAVED_INSTALL_OLLAMA" = true ] && [ -z "$INSTALL_OLLAMA" ]; then
    INSTALL_OLLAMA="y"
  fi
  INSTALL_OLLAMA_FLAG=false
  if [[ "$INSTALL_OLLAMA" =~ ^[Yy]$ ]]; then
    INSTALL_OLLAMA_FLAG=true
  fi

  # Ask to install Gemini Cloud API
  local_gemini_prompt="y/N"
  [ "$SAVED_INSTALL_GEMINI" = true ] && local_gemini_prompt="Y/n"
  read -r -p "Do you want to install Gemini Cloud API? ($local_gemini_prompt): " INSTALL_GEMINI
  if [ "$SAVED_INSTALL_GEMINI" = true ] && [ -z "$INSTALL_GEMINI" ]; then
    INSTALL_GEMINI="y"
  fi
  INSTALL_GEMINI_FLAG=false
  if [[ "$INSTALL_GEMINI" =~ ^[Yy]$ ]]; then
    INSTALL_GEMINI_FLAG=true
  fi

  if [ "$INSTALL_OLLAMA_FLAG" = false ] && [ "$INSTALL_GEMINI_FLAG" = false ]; then
    echo "⚠️  No components selected for installation. Exiting script."
    exit 0
  fi

  # Ask for AI Response Language
  echo ""
  echo "Select AI explanation language (for e, fe, el, Q&A modes):"
  echo "  1) English"
  echo "  2) Vietnamese (Tiếng Việt)"
  default_lang_choice="1"
  [ "$SAVED_AI_LANG" = "Vietnamese" ] && default_lang_choice="2"
  read -r -p "Enter choice [1/2 or custom language, default: $default_lang_choice]: " USER_LANG_INPUT
  USER_LANG_INPUT="${USER_LANG_INPUT:-$default_lang_choice}"
  case "$USER_LANG_INPUT" in
    2|[Vv]ietnamese|[Vv]i)
      AI_RESPONSE_LANG="Vietnamese"
      ;;
    1|[Ee]nglish|[Ee]n)
      AI_RESPONSE_LANG="English"
      ;;
    *)
      AI_RESPONSE_LANG="$USER_LANG_INPUT"
      ;;
  esac
  echo "Selected AI Language: $AI_RESPONSE_LANG"
  echo ""
fi

# Determine target profile
TARGET_RC="$HOME/.bashrc"
if [[ -n "$ZSH_VERSION" ]] || [[ "$SHELL" == *"zsh"* ]]; then
  TARGET_RC="$HOME/.zshrc"
fi

# --- Check command name collisions & fallbacks ---
echo "--- Checking command name collisions ---"
check_collision() {
  local short_name="$1"
  local target_file="$TARGET_RC"
  local fallback_name="afe-$1"
  local is_taken=false

  if command -v "$short_name" &>/dev/null; then
    is_taken=true
  fi

  if [ -f "$target_file" ]; then
    local clean_rc
    clean_rc=$(sed -e '/# --- AI CLI ASSISTANT BASE ---/,/# --- END AI CLI ASSISTANT ---/d' \
                   -e '/# --- GEMINI LINUX CLI ASSISTANT ---/,/# --- END GEMINI LINUX CLI ASSISTANT ---/d' \
                   -e '/# --- OLLAMA LOCAL EXTENSION ---/,/# --- END GEMINI CLOUD EXTENSION ---/d' \
                   "$target_file" 2>/dev/null || true)
    if echo "$clean_rc" | grep -qE "(alias[[:space:]]+$short_name=|function[[:space:]]+$short_name[[:space:]]*\(|^[[:space:]]*$short_name[[:space:]]*\(\))"; then
      is_taken=true
    fi
  fi

  if [ "$is_taken" = true ]; then
    echo "⚠️  Command '$short_name' is already in use. Falling back to '$fallback_name'." >&2
    echo "$fallback_name"
  else
    echo "$short_name"
  fi
}

CMD_A=$(check_collision "a")
CMD_F=$(check_collision "f")
CMD_FE=$(check_collision "fe")
CMD_E=$(check_collision "e")
CMD_Q=$(check_collision "q")

CMD_AL=$(check_collision "al")
CMD_ALT=$(check_collision "alt")
CMD_FL=$(check_collision "fl")
CMD_FLT=$(check_collision "flt")
CMD_EL=$(check_collision "el")
CMD_QL=$(check_collision "ql")
CMD_QLT=$(check_collision "qlt")
echo "Resolved command names: Cloud=[$CMD_A, $CMD_F, $CMD_FE, $CMD_E, $CMD_Q], Local=[$CMD_AL, $CMD_ALT, $CMD_FL, $CMD_FLT, $CMD_EL, $CMD_QL, $CMD_QLT]"
echo ""

# --- Process Ollama if selected ---
if [ "$INSTALL_OLLAMA_FLAG" = true ]; then
  echo "--- Configuring Ollama Local ---"
  if ! command -v ollama &>/dev/null; then
    echo "Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
  fi

  if ! pgrep -x "ollama" > /dev/null; then
    echo "Starting Ollama service..."
    ollama serve >/dev/null 2>&1 &
    sleep 3
  fi

  if [ "$USE_SAVED_CONFIG" = false ]; then
    read -r -p "Enter Ollama Base Model name [default: ${SAVED_BASE_MODEL:-gemma4:e2b}]: " INPUT_MODEL
    BASE_MODEL="${INPUT_MODEL:-${SAVED_BASE_MODEL:-gemma4:e2b}}"
  else
    BASE_MODEL="${SAVED_BASE_MODEL:-gemma4:e2b}"
  fi

  echo "Pulling base model: $BASE_MODEL..."
  ollama pull "$BASE_MODEL"

  echo "Creating ask-cli model..."
  TMP_ASK_MODELFILE=$(mktemp)
  cat <<EOF > "$TMP_ASK_MODELFILE"
FROM $BASE_MODEL
TEMPLATE {{ .Prompt }}
SYSTEM "
You are a senior DevOps and Linux CLI assistant.
Convert natural language requests into the exact, executable Linux terminal command.

RULES:
1. Output ONLY the raw executable shell command.
2. STRICTLY PROHIBITED: Do NOT use markdown code blocks. Do NOT include any explanations, notes, conversational filler, or quotes.
3. Understand developer tooling: Docker, Docker Compose, Kubernetes, Git, Database, Network/OpenSSL, Node.js, Python, standard Linux tools.
4. Default to Linux (GNU tools) syntax. Preserve exact file paths provided.
5. For text replacement, always use: sed -i 's/old/new/g' filename
6. Never invent non-existent commands.
"
RENDERER gemma4
PARSER gemma4
PARAMETER temperature 0.1
PARAMETER top_k 64
PARAMETER top_p 0.95
EOF
  ollama create ask-cli -f "$TMP_ASK_MODELFILE"
  rm -f "$TMP_ASK_MODELFILE"

  echo "Creating fix-cli model (Response language: $AI_RESPONSE_LANG)..."
  TMP_FIX_MODELFILE=$(mktemp)
  cat <<EOF > "$TMP_FIX_MODELFILE"
FROM $BASE_MODEL
TEMPLATE {{ .Prompt }}
SYSTEM "
You are an expert DevOps engineer and Linux terminal assistant.

RULES:
1. When fixing errors or generating terminal commands:
   - Output ONLY the single raw executable shell command.
   - Do NOT use markdown code blocks or backticks.
   - Output fully resolved, concrete commands using context values. Never use nested subshells to re-evaluate context.
   - Do NOT output explanations, conversational text, or status claims (never say 'Already done' or 'Success').
   - Resolve the root cause (environment, dependencies, permissions, resources, syntax).
2. When answering user requests, questions, or queries:
   - Directly execute the user request using the provided context or piped data.
   - When asked to write a git commit message: synthesize high-level architectural goals into conventional commit format (title, blank line, strictly 4-5 high-impact bullet points, no micro-bullets). Do NOT list each file individually.
   - Match the requested format and language strictly.
   - Output clean plain text without markdown backticks, bold asterisks, or headings. Use '-' for bullet points.
3. Default to Linux (GNU tools) syntax.
"
RENDERER gemma4
PARSER gemma4
PARAMETER temperature 0.1
PARAMETER top_k 64
PARAMETER top_p 0.95
EOF
  ollama create fix-cli -f "$TMP_FIX_MODELFILE"
  rm -f "$TMP_FIX_MODELFILE"
fi

# --- Process Gemini Cloud if selected ---
if [ "$INSTALL_GEMINI_FLAG" = true ]; then
  echo "--- Configuring Gemini Cloud API ---"
  ENV_FILE="$HOME/.env"
  EXISTING_KEY=""
  if [[ -f "$ENV_FILE" ]]; then
    EXISTING_KEY=$(grep -E '^GEMINI_API_KEY=' "$ENV_FILE" | cut -d '=' -f2- | tr -d '"' | tr -d "'")
  fi

  if [ "$USE_SAVED_CONFIG" = false ]; then
    if [[ -n "$EXISTING_KEY" ]]; then
      read -r -p "Found GEMINI_API_KEY in ~/.env. Do you want to update it? (y/N): " CHANGE_KEY
      if [[ "$CHANGE_KEY" =~ ^[Yy]$ ]]; then
        USER_GEMINI_KEY=""
      else
        USER_GEMINI_KEY="$EXISTING_KEY"
      fi
    fi

    while [[ -z "$USER_GEMINI_KEY" ]]; do
      read -r -p "Enter your GEMINI_API_KEY (required): " USER_GEMINI_KEY
      if [[ -z "$USER_GEMINI_KEY" ]]; then
        echo "⚠️  API Key cannot be empty. Please try again!"
      fi
    done

    read -r -p "Enter GEMINI_MODEL_ID [default: ${SAVED_CLOUD_MODEL:-gemma-4-26b-a4b-it}]: " INPUT_CLOUD_MODEL
    USER_GEMINI_MODEL="${INPUT_CLOUD_MODEL:-${SAVED_CLOUD_MODEL:-gemma-4-26b-a4b-it}}"
  else
    USER_GEMINI_KEY="$EXISTING_KEY"
    USER_GEMINI_MODEL="${SAVED_CLOUD_MODEL:-gemma-4-26b-a4b-it}"
  fi

  touch "$ENV_FILE"
  if grep -q "^GEMINI_API_KEY=" "$ENV_FILE"; then
    sed -i "s|^GEMINI_API_KEY=.*|GEMINI_API_KEY=\"$USER_GEMINI_KEY\"|" "$ENV_FILE"
  else
    echo "GEMINI_API_KEY=\"$USER_GEMINI_KEY\"" >> "$ENV_FILE"
  fi
  chmod 600 "$ENV_FILE"
  echo "✅ Successfully saved GEMINI_API_KEY securely to $ENV_FILE (chmod 600)"
fi

# Save configuration for future re-runs and one-click updates
cat <<CONFIG_EOF > "$AFE_CONFIG_FILE"
INSTALL_OLLAMA=$INSTALL_OLLAMA_FLAG
INSTALL_GEMINI=$INSTALL_GEMINI_FLAG
AI_RESPONSE_LANG="$AI_RESPONSE_LANG"
OLLAMA_MODEL="${BASE_MODEL:-gemma4:e2b}"
GEMINI_MODEL="${USER_GEMINI_MODEL:-gemma-4-26b-a4b-it}"
CONFIG_EOF
chmod 600 "$AFE_CONFIG_FILE"

echo "=== [3/4] Updating Shell Profile configuration ==="

# Clean up old blocks to ensure idempotency
if [ -f "$TARGET_RC" ]; then
  sed -i '/# --- AI CLI ASSISTANT BASE ---/,/# --- END AI CLI ASSISTANT ---/d' "$TARGET_RC" 2>/dev/null || true
  sed -i '/# --- GEMINI LINUX CLI ASSISTANT ---/,/# --- END GEMINI LINUX CLI ASSISTANT ---/d' "$TARGET_RC" 2>/dev/null || true
  sed -i '/# --- OLLAMA LOCAL EXTENSION ---/,/# --- END GEMINI CLOUD EXTENSION ---/d' "$TARGET_RC" 2>/dev/null || true
fi

# 1. Write shared Base Config (Buffer, Screen context, Widget Ctrl+G, Language, afe-help)
cat <<EOF >> "$TARGET_RC"

# --- AI CLI ASSISTANT BASE ---
export AFE_CLI_VERSION="$AFE_VERSION"
export AI_RESPONSE_LANG="$AI_RESPONSE_LANG"

# Automatically load environment variables from ~/.env if it exists
if [[ -f "\$HOME/.env" ]]; then
  export \$(grep -v '^#' "\$HOME/.env" | xargs)
fi

# Clean up stale session logs older than 1 day
find /tmp -maxdepth 1 -name "afe_session_*.log" -mtime +1 -exec rm -f {} + 2>/dev/null || true

# Session output auto-buffer (works on VS Code, Cursor, Zed, Terminal, etc.)
if [[ -z "\$AFE_SESSION_LOGGED" && -t 0 && -t 1 && "\$TERM" != "dumb" && -z "\$INSIDE_EMACS" ]]; then
  export AFE_SESSION_LOGGED=1
  export AFE_SESSION_LOG="/tmp/afe_session_\${$}_$(date +%s).log"
  touch "\$AFE_SESSION_LOG" 2>/dev/null || true
  trap 'rm -f "\$AFE_SESSION_LOG" 2>/dev/null' EXIT
  if [[ "\$(uname -s)" == "Darwin" ]]; then
    exec script -q -F "\$AFE_SESSION_LOG"
  else
    exec script -q -f "\$AFE_SESSION_LOG"
  fi
fi

# Capture last command
if [[ -n "\$ZSH_VERSION" ]]; then
  unsetopt nomatch 2>/dev/null || true
  autoload -Uz add-zsh-hook 2>/dev/null || true
  _AFE_IS_AI_CMD=0
  _save_last_cmd() {
    local cmd="\$1"
    cmd=\$(echo "\$cmd" | head -n 1 | sed 's/^[[:space:]]*//')
    local first_word="\${cmd%% *}"
    case "\$first_word" in
      $CMD_A|$CMD_AL|$CMD_ALT|$CMD_F|$CMD_FL|$CMD_FLT|$CMD_FE|$CMD_E|$CMD_EL|$CMD_Q|$CMD_QL|$CMD_QLT|afe-help|ai-help|ai)
        _AFE_IS_AI_CMD=1
        ;;
      *)
        _AFE_IS_AI_CMD=0
        if [[ -n "\$cmd" ]]; then
          export LAST_TERMINAL_CMD="\$cmd"
          if [[ -n "\$AFE_SESSION_LOG" && -f "\$AFE_SESSION_LOG" ]]; then
            export _AFE_LAST_CMD_START_LINE=\$(wc -l < "\$AFE_SESSION_LOG" 2>/dev/null | tr -d ' ' || echo 1)
          fi
        fi
        ;;
    esac
  }
  add-zsh-hook preexec _save_last_cmd 2>/dev/null || true

  _save_last_cmd_end() {
    if [[ "\$_AFE_IS_AI_CMD" != "1" && -n "\$AFE_SESSION_LOG" && -f "\$AFE_SESSION_LOG" ]]; then
      export _AFE_LAST_CMD_END_LINE=\$(wc -l < "\$AFE_SESSION_LOG" 2>/dev/null | tr -d ' ' || echo 1)
    fi
  }
  add-zsh-hook precmd _save_last_cmd_end 2>/dev/null || true
fi

_get_terminal_screen_buffer() {
  if [[ -n "\$AFE_SESSION_LOG" && -f "\$AFE_SESSION_LOG" ]]; then
    local start_line="\${_AFE_LAST_CMD_START_LINE:-1}"
    local total_lines=\$(wc -l < "\$AFE_SESSION_LOG" 2>/dev/null | tr -d ' ' || echo 1)
    local end_line="\${_AFE_LAST_CMD_END_LINE:-\$total_lines}"
    if [[ \$end_line -ge \$start_line ]]; then
      sed -n "\${start_line},\${end_line}p" "\$AFE_SESSION_LOG" | tail -n 60 | sed -E \$'s/\x1B\\[[0-9;]*[a-zA-Z]//g' | tr -d '\r'
    else
      tail -n 60 "\$AFE_SESSION_LOG" | sed -E \$'s/\x1B\\[[0-9;]*[a-zA-Z]//g' | tr -d '\r'
    fi
  elif [[ -n "\$TMUX" ]]; then
    tmux capture-pane -p 2>/dev/null | tail -n 30
  elif [[ -f "\$HOME/.zsh_history" ]]; then
    tail -n 30 "\$HOME/.zsh_history" | sed 's/^: [0-9]*:[0-9];//' 2>/dev/null
  elif [[ -f "\$HOME/.bash_history" ]]; then
    tail -n 30 "\$HOME/.bash_history" 2>/dev/null
  else
    echo ""
  fi
}

_build_fix_prompt() {
  local query="\$*"
  local stdin_data=""
  if [ ! -t 0 ]; then
    stdin_data=\$(head -n 500)
  fi

  local last_cmd="\$LAST_TERMINAL_CMD"

  if [[ -z "\$last_cmd" ]]; then
    if [[ -n "\$ZSH_VERSION" ]]; then
      last_cmd=\$(fc -ln -1 2>/dev/null | sed -E 's/^[[:space:]\x00-\x1F]+//')
      if [[ "\$last_cmd" =~ ^($CMD_F|$CMD_FL|$CMD_FLT|$CMD_FE|$CMD_A|$CMD_AL|$CMD_ALT|$CMD_E|$CMD_EL|$CMD_Q|$CMD_QL|$CMD_QLT|afe|afe-help|ai-help|ai)($|[[:space:]]) ]]; then
        last_cmd=\$(fc -ln -2 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]\x00-\x1F]+//')
      fi
    else
      last_cmd=\$(HISTTIMEFORMAT= history 2 2>/dev/null | head -n 1 | sed 's/^[ ]*[0-9]*[ ]*//')
    fi
  fi

  local output_data="\$stdin_data"
  if [[ -z "\$output_data" ]]; then
    output_data=\$(_get_terminal_screen_buffer | sed -E \$'s/\x1B\\[[0-9;]*[a-zA-Z]//g')
  fi

  if [[ -z "\$query" ]]; then
    echo "Recent terminal context:
\$output_data
Last executed command: \$last_cmd

Task: Output ONLY the exact raw fixed Linux shell command to resolve the error. No markdown, no explanations."
  else
    echo "Recent terminal context:
\$output_data
Last executed command: \$last_cmd
User instruction: \$query

Task: Generate the exact raw executable Linux shell command to fulfill the user instruction. Use concrete values and text from the context. Do NOT use nested subshells to re-evaluate prior steps."
  fi
}

_build_query_prompt() {
  local query="\$*"
  local stdin_data=""
  if [ ! -t 0 ]; then
    stdin_data=\$(head -n 1200)
  fi

  if [[ -n "\$stdin_data" ]]; then
    local effective_query="\$query"
    if [[ -z "\$effective_query" ]]; then
      if echo "\$stdin_data" | grep -q -E '(diff --git|index [0-9a-f]+\.\.[0-9a-f]+|Changes not staged for commit|Changes to be committed)'; then
        effective_query="Write a high-level concise conventional commit message for these git changes"
      else
        effective_query="Analyze and summarize this piped data concisely"
      fi
    fi

    echo "[USER REQUEST / INSTRUCTION]
\$effective_query

[PIPED INPUT DATA]
\$stdin_data

[REMINDER: FULFILL THIS USER REQUEST IN THE REQUESTED LANGUAGE]
\$effective_query"
  else
    local last_cmd="\$LAST_TERMINAL_CMD"
    if [[ -z "\$last_cmd" ]]; then
      if [[ -n "\$ZSH_VERSION" ]]; then
        last_cmd=\$(fc -ln -1 2>/dev/null | sed -E 's/^[[:space:]\x00-\x1F]+//')
        if [[ "\$last_cmd" =~ ^($CMD_F|$CMD_FL|$CMD_FLT|$CMD_FE|$CMD_A|$CMD_AL|$CMD_ALT|$CMD_E|$CMD_EL|$CMD_Q|$CMD_QL|$CMD_QLT|afe|afe-help|ai-help|ai)($|[[:space:]]) ]]; then
          last_cmd=\$(fc -ln -2 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]\x00-\x1F]+//')
        fi
      else
        last_cmd=\$(HISTTIMEFORMAT= history 2 2>/dev/null | head -n 1 | sed 's/^[ ]*[0-9]*[ ]*//')
      fi
    fi

    local output_data=\$(_get_terminal_screen_buffer | sed -E \$'s/\x1B\\[[0-9;]*[a-zA-Z]//g')

    if [[ -n "\$output_data" || -n "\$last_cmd" ]]; then
      echo "[USER REQUEST / INSTRUCTION]
\$query

[RECENT TERMINAL CONTEXT]
Last command: \$last_cmd
Recent screen output:
\$output_data"
    else
      echo "\$query"
    fi
  fi
}

LAST_AI_OUTPUT=""

_check_dangerous_cmd() {
  local cmd="\$1"
  if echo "\$cmd" | grep -qiE '(rm[[:space:]]+.*-[a-zA-Z]*[rR]|mkfs|dd[[:space:]]+.*if=|fdisk|parted|wipefs|DROP[[:space:]]+(DATABASE|TABLE)|TRUNCATE[[:space:]]+TABLE|chmod[[:space:]]+.*-[a-zA-Z]*[rR].*777|git[[:space:]]+push[[:space:]].*(--force|-f\b)|git[[:space:]]+reset[[:space:]]+--hard|>[[:space:]]*/dev/(sd|nvme|disk|hd))'; then
    printf "\033[1;33m⚠️  [CAUTION: This command can modify, overwrite, or delete critical data!]\033[0m\n" >&2
  fi
}

_insert_last_ai_cmd() {
  if [[ -n "\$LAST_AI_OUTPUT" ]]; then
    local clean_cmd=\$(echo "\$LAST_AI_OUTPUT" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*\$//')
    if [[ -n "\$ZSH_VERSION" ]]; then
      LBUFFER="\${LBUFFER}\${clean_cmd}"
      zle redisplay
    elif [[ -n "\$BASH_VERSION" ]]; then
      READLINE_LINE="\${READLINE_LINE:0:\$READLINE_POINT}\${clean_cmd}\${READLINE_LINE:\$READLINE_POINT}"
      READLINE_POINT=\$((READLINE_POINT + \${#clean_cmd}))
    fi
  fi
}

if [[ -n "\$ZSH_VERSION" ]]; then
  zle -N _insert_last_ai_cmd
  bindkey '^G' _insert_last_ai_cmd
elif [[ -n "\$BASH_VERSION" ]]; then
  bind -x '"\C-g": _insert_last_ai_cmd'
fi

afe-help() {
  cat <<'HELP_EOF'
╭──────────────────────────────────────────────────────────────────────────╮
│                             🚀 AFE CLI Help                              │
╰──────────────────────────────────────────────────────────────────────────╯

  ☁️  Cloud Commands (Gemini API):
    $CMD_A <request>       Generate executable Linux command from prompt
    $CMD_F [question]      Generate fix command for the last failed command
    $CMD_FE [question]     Explain root cause & fix for the last error concisely
    $CMD_E [command]       Explain command manual (default: last AI generated cmd)
    $CMD_Q <request>       Query, analyze context/logs, or synthesize knowledge

  💻 Local Commands (Ollama Offline):
    $CMD_AL <request>      Generate command using Ollama local model
    $CMD_ALT <request>     Generate command with live thinking stream
    $CMD_FL [question]     Generate fix command using Ollama local
    $CMD_FLT [question]    Generate fix command with live thinking stream
    $CMD_EL [command]      Explain command manual using Ollama local
    $CMD_QL <request>      Query & synthesize using Ollama local model
    $CMD_QLT <request>     Query & synthesize with live thinking stream

  ⌨️  Shortcuts & Tips:
    Ctrl + G          Paste last AI generated command at cursor position
    $CMD_E / $CMD_EL (no args) Directly explain the command that AI just suggested
    <cmd> | $CMD_Q <req>       Pipe logs/diff/output directly into AI query

  ℹ️  Help & Info:
    afe-help          Display this help message
    afe-version       Display current installed version
    afe-update        Update AFE CLI to latest version (or 'afe update')
    afe-uninstall     Uninstall AFE CLI completely (or 'afe uninstall')
────────────────────────────────────────────────────────────────────────────
HELP_EOF
  _check_afe_update
}

_check_afe_update() {
  local last_check_file="\$HOME/.afe_last_update_check"
  local remote_ver_file="\$HOME/.afe_remote_version"
  local now
  now=\$(date +%s 2>/dev/null || echo 0)
  local last_check=0
  if [[ -f "\$last_check_file" ]]; then
    last_check=\$(cat "\$last_check_file" 2>/dev/null || echo 0)
  fi

  if (( now - last_check > 86400 )); then
    echo "\$now" > "\$last_check_file" 2>/dev/null || true
    (
      local r_ver
      r_ver=\$(curl -fsSL --max-time 2 https://raw.githubusercontent.com/vuhaipro2707/afe-cli/main/version 2>/dev/null | tr -d '[:space:]')
      if [[ -n "\$r_ver" ]]; then
        echo "\$r_ver" > "\$remote_ver_file" 2>/dev/null || true
      fi
    ) &! 2>/dev/null || ( ( curl -fsSL --max-time 2 https://raw.githubusercontent.com/vuhaipro2707/afe-cli/main/version > "\$remote_ver_file" 2>/dev/null ) & ) 2>/dev/null || true
  fi

  if [[ -f "\$remote_ver_file" ]]; then
    local r_ver
    r_ver=\$(cat "\$remote_ver_file" 2>/dev/null | tr -d '[:space:]')
    if [[ -n "\$r_ver" && "\$r_ver" != "\$AFE_CLI_VERSION" ]]; then
      printf "\n\033[1;33m💡 [AFE Update] New version v%s available! (Current: v%s). Run 'afe update' to upgrade.\033[0m\n" "\$r_ver" "\$AFE_CLI_VERSION"
    fi
  fi
}

afe() {
  case "\$1" in
    -v|--version|version)
      afe-version
      ;;
    -u|--update|update)
      afe-update
      ;;
    --uninstall|uninstall)
      afe-uninstall
      ;;
    *)
      afe-help
      ;;
  esac
}
alias ai-help=afe-help
alias ai=afe

afe-version() {
  echo "🚀 AFE CLI v$AFE_VERSION"
  _check_afe_update
}
alias afe-v=afe-version

afe-update() {
  echo "🔄 Checking and updating AFE CLI..."
  /bin/bash -c "\$(curl -fsSL https://raw.githubusercontent.com/vuhaipro2707/afe-cli/main/install.sh)" -- install
}

afe-uninstall() {
  echo "🗑️  Starting AFE CLI Uninstallation..."
  /bin/bash -c "\$(curl -fsSL https://raw.githubusercontent.com/vuhaipro2707/afe-cli/main/install.sh)" -- uninstall
}
EOF

# 2. Write Ollama Block if selected
if [ "$INSTALL_OLLAMA_FLAG" = true ]; then
cat <<EOF >> "$TARGET_RC"

# --- OLLAMA LOCAL EXTENSION ---
_ollama_live_stream() {
  python3 -c '
import sys
in_think = False
for line in sys.stdin:
    stripped = line.strip()
    if "Thinking..." in stripped or "<think>" in stripped:
        in_think = True
        continue
    if "...done thinking." in stripped or "</think>" in stripped:
        in_think = False
        sys.stdout.write("\r\033[K")
        sys.stdout.flush()
        continue
    if in_think:
        if stripped:
            display_text = (stripped[:75] + "...") if len(stripped) > 75 else stripped
            sys.stdout.write(f"\r\033[1;30m🤔 {display_text}\033[0m\033[K")
            sys.stdout.flush()
    else:
        sys.stdout.write(line)
        sys.stdout.flush()
'
}

$CMD_AL() {
  local query="\$*"
  [[ "\$1" == "-h" || "\$1" == "--help" ]] && { afe-help; return 0; }
  [[ -z "\$query" ]] && { echo "Usage: $CMD_AL <question> (or 'afe-help' for help)"; return 1; }
  local tmp_file=\$(mktemp)
  ollama run ask-cli --think=false "\$query" | tee "\$tmp_file"
  LAST_AI_OUTPUT=\$(<"\$tmp_file")
  rm -f "\$tmp_file"
  _check_dangerous_cmd "\$LAST_AI_OUTPUT"
}

$CMD_ALT() {
  local query="\$*"
  [[ "\$1" == "-h" || "\$1" == "--help" ]] && { afe-help; return 0; }
  [[ -z "\$query" ]] && { echo "Usage: $CMD_ALT <question> (or 'afe-help' for help)"; return 1; }
  local tmp_file=\$(mktemp)
  ollama run ask-cli "\$query" | _ollama_live_stream | tee "\$tmp_file"
  LAST_AI_OUTPUT=\$(<"\$tmp_file")
  rm -f "\$tmp_file"
  _check_dangerous_cmd "\$LAST_AI_OUTPUT"
}

$CMD_FL() {
  [[ "\$1" == "-h" || "\$1" == "--help" ]] && { afe-help; return 0; }
  local prompt="\$(_build_fix_prompt "\$*")"
  local tmp_file=\$(mktemp)
  ollama run fix-cli --think=false "\$prompt" | tee "\$tmp_file"
  LAST_AI_OUTPUT=\$(<"\$tmp_file")
  rm -f "\$tmp_file"
  _check_dangerous_cmd "\$LAST_AI_OUTPUT"
}

$CMD_FLT() {
  [[ "\$1" == "-h" || "\$1" == "--help" ]] && { afe-help; return 0; }
  local prompt="\$(_build_fix_prompt "\$*")"
  local tmp_file=\$(mktemp)
  ollama run fix-cli "\$prompt" | _ollama_live_stream | tee "\$tmp_file"
  LAST_AI_OUTPUT=\$(<"\$tmp_file")
  rm -f "\$tmp_file"
  _check_dangerous_cmd "\$LAST_AI_OUTPUT"
}

$CMD_EL() {
  local query="\$*"
  [[ "\$1" == "-h" || "\$1" == "--help" ]] && { afe-help; return 0; }
  if [[ -z "\$query" ]]; then
    if [[ -n "\$LAST_AI_OUTPUT" ]]; then
      query="\$LAST_AI_OUTPUT"
    else
      echo "Usage: $CMD_EL <command or concept> (or 'afe-help' for help)"
      return 1
    fi
  fi
  ollama run ask-cli --think=false "Explain briefly in \${AI_RESPONSE_LANG:-$AI_RESPONSE_LANG} about the following command/concept: \$query"
}

$CMD_QL() {
  [[ "\$1" == "-h" || "\$1" == "--help" ]] && { afe-help; return 0; }
  local query="\$*"
  if [ -t 0 ] && [[ -z "\$query" ]]; then
    echo "Usage: $CMD_QL <request/question> (or 'afe-help' for help)"
    return 1
  fi
  local prompt="\$(_build_query_prompt "\$*")"
  ollama run fix-cli --think=false "\$prompt"
}

$CMD_QLT() {
  [[ "\$1" == "-h" || "\$1" == "--help" ]] && { afe-help; return 0; }
  local query="\$*"
  if [ -t 0 ] && [[ -z "\$query" ]]; then
    echo "Usage: $CMD_QLT <request/question> (or 'afe-help' for help)"
    return 1
  fi
  local prompt="\$(_build_query_prompt "\$*")"
  ollama run fix-cli "\$prompt" | _ollama_live_stream
}
EOF
fi

# 3. Write Gemini Cloud Block if selected
if [ "$INSTALL_GEMINI_FLAG" = true ]; then
cat <<EOF >> "$TARGET_RC"

# --- GEMINI CLOUD EXTENSION ---
export GEMINI_MODEL_ID="$USER_GEMINI_MODEL"

_call_gemini_api() {
  local sys_prompt="\$1"
  local user_prompt="\$2"

  if [[ -z "\$GEMINI_API_KEY" ]]; then
    echo "Error: GEMINI_API_KEY is not set in ~/.env"
    return 1
  fi

  local payload
  payload=\$(python3 -c "
import json, sys
data = {
    'systemInstruction': {'parts': [{'text': sys.argv[1]}]},
    'contents': [{'role': 'user', 'parts': [{'text': sys.argv[2]}]}],
    'generationConfig': {
        'temperature': 0.1,
        'thinkingConfig': {'thinkingLevel': 'MINIMAL'},
    }
}
print(json.dumps(data))
" "\$sys_prompt" "\$user_prompt")

  curl -s -N \
    -X POST \
    -H "Content-Type: application/json" \
    "https://generativelanguage.googleapis.com/v1beta/models/\${GEMINI_MODEL_ID}:streamGenerateContent?key=\${GEMINI_API_KEY}" \
    -d "\$payload" | python3 -u -c "
import sys, json, time
decoder = json.JSONDecoder()
buf = ''
def smooth_print(text):
    try:
        for char in text:
            sys.stdout.write(char)
            sys.stdout.flush()
            time.sleep(0.004)
    except (BrokenPipeError, IOError):
        sys.exit(0)

try:
    while True:
        chunk = sys.stdin.read(1)
        if not chunk:
            break
        buf += chunk
        buf_stripped = buf.lstrip('[\r\n, ]')
        if not buf_stripped:
            continue
        try:
            obj, index = decoder.raw_decode(buf_stripped)
            buf = buf_stripped[index:]
            if 'candidates' in obj and obj['candidates']:
                parts = obj['candidates'][0].get('content', {}).get('parts', [])
                for p in parts:
                    if 'text' in p:
                        smooth_print(p['text'])
            elif 'error' in obj:
                print(f\"\nAPI Error: {obj['error'].get('message', obj['error'])}\", flush=True)
        except json.JSONDecodeError:
            pass
    print()
except (BrokenPipeError, IOError):
    sys.exit(0)
"
}

$CMD_A() {
  local query="\$*"
  [[ "\$1" == "-h" || "\$1" == "--help" ]] && { afe-help; return 0; }
  [[ -z "\$query" ]] && { echo "Usage: $CMD_A <question> (or 'afe-help' for help)"; return 1; }
  local sys_prompt="You are a senior DevOps and Linux CLI assistant. Convert user requests into exact executable Linux terminal commands. Output ONLY the raw executable shell command. STRICT RULES: Do NOT use markdown code blocks. Do NOT include any explanations, notes, quotes, or markdown formatting."
  local tmp_file=\$(mktemp)
  _call_gemini_api "\$sys_prompt" "\$query" | tee "\$tmp_file"
  LAST_AI_OUTPUT=\$(<"\$tmp_file")
  rm -f "\$tmp_file"
  _check_dangerous_cmd "\$LAST_AI_OUTPUT"
}

$CMD_F() {
  [[ "\$1" == "-h" || "\$1" == "--help" ]] && { afe-help; return 0; }
  local prompt="\$(_build_fix_prompt "\$*")"
  local sys_prompt="You are an expert Linux terminal command generator.
STRICT RULES:
- Output ONLY the single raw executable shell command.
- Concrete Execution: Always output fully resolved, concrete commands. Extract and embed any needed values, strings, IDs, or text directly from the screen context. Never use nested subshells to re-evaluate context.
- Zero Chatter: NO conversational text, NO status messages (never claim 'Already done' or 'Success'), NO explanations, NO markdown."
  local tmp_file=\$(mktemp)
  _call_gemini_api "\$sys_prompt" "\$prompt" | tee "\$tmp_file"
  LAST_AI_OUTPUT=\$(<"\$tmp_file")
  rm -f "\$tmp_file"
  _check_dangerous_cmd "\$LAST_AI_OUTPUT"
}

$CMD_FE() {
  [[ "\$1" == "-h" || "\$1" == "--help" ]] && { afe-help; return 0; }
  local prompt="\$(_build_fix_prompt "\$*")"
  local sys_prompt="You are an expert Linux terminal troubleshooting assistant.
STRICT RULES:
- Output clean terminal plain text. STRICTLY NO markdown headings, NO bold asterisks, NO backticks.
- Be extremely concise, direct, and technical.
- NO greetings, pleasantries, apologies, intros, or conversational filler.
- Format:
  Cause: 1 short sentence stating the root cause.
  Fix: The exact single raw executable Linux terminal command needed.
- Language: \${AI_RESPONSE_LANG:-$AI_RESPONSE_LANG}."
  local tmp_file=\$(mktemp)
  _call_gemini_api "\$sys_prompt" "\$prompt" | tee "\$tmp_file"
  local full_output=\$(<"\$tmp_file")
  rm -f "\$tmp_file"
  local fix_cmd=\$(echo "\$full_output" | grep -iE '^[[:space:]]*Fix:[[:space:]]*' | sed -E 's/^[[:space:]]*[Ff][Ii][Xx]:[[:space:]]*//' | head -n 1)
  if [[ -n "\$fix_cmd" ]]; then
    LAST_AI_OUTPUT="\$fix_cmd"
    _check_dangerous_cmd "\$LAST_AI_OUTPUT"
  fi
}

$CMD_E() {
  local prompt="\$*"
  [[ "\$1" == "-h" || "\$1" == "--help" ]] && { afe-help; return 0; }
  if [[ -z "\$prompt" ]]; then
    if [[ -n "\$LAST_AI_OUTPUT" ]]; then
      prompt="\$LAST_AI_OUTPUT"
    else
      echo "Usage: $CMD_E <command or concept> (or 'afe-help' for help)"
      return 1
    fi
  fi
  local sys_prompt="You are a concise Linux technical manual.
STRICT RULES:
- Output clean terminal plain text. STRICTLY NO markdown headings, NO bold asterisks, NO code blocks.
- NEVER say hello, greetings, intros, outros, or pleasantries (No 'Hello', 'Hi', 'Hope this helps').
- NO emojis, NO conversational fluff.
- Jump STRAIGHT into the explanation.
- Structure:
  1. One sentence explaining the overall purpose.
  2. Bullet points with '-' breaking down flags/components directly.
- Language: \${AI_RESPONSE_LANG:-$AI_RESPONSE_LANG}, direct, concise, developer-oriented."
  _call_gemini_api "\$sys_prompt" "\$prompt"
}

$CMD_Q() {
  [[ "\$1" == "-h" || "\$1" == "--help" ]] && { afe-help; return 0; }
  local query="\$*"
  if [ -t 0 ] && [[ -z "\$query" ]]; then
    echo "Usage: $CMD_Q <request/question> (or 'afe-help' for help)"
    echo "Examples:"
    echo "  $CMD_Q \"tổng hợp kết quả vừa chạy\""
    echo "  cat server.log | $CMD_Q \"tổng hợp các lỗi nghiêm trọng\""
    echo "  $CMD_Q so sánh Docker và Podman"
    return 1
  fi
  local prompt="\$(_build_query_prompt "\$*")"
  local sys_prompt="You are a Principal Software Engineer and DevOps architect.
LANGUAGE RULES (STRICT & ABSOLUTE):
- If the user request mentions Vietnamese / tiếng Việt, you MUST output 100% in Vietnamese (including commit title and all bullet points).
- If the user request mentions English / tiếng Anh, you MUST output 100% in English.
- If no specific language is requested, default to \${AI_RESPONSE_LANG:-$AI_RESPONSE_LANG}.

CORE INSTRUCTIONS:
- Directly execute the exact USER REQUEST using the provided terminal context / piped data.

GIT COMMIT MESSAGE RULES (CRITICAL):
- When asked to write a commit message (or if piped data is a git diff/status):
  1. Title line: Format '<type>(<optional-scope>): <summary>' (lowercase, under 72 chars, imperative mood). Choose the single most accurate conventional commit type for the entire change: 'feat', 'fix', 'refactor', 'perf', 'chore', 'docs', 'test'.
  2. Blank line: Exactly one blank line between title and bullet points.
  3. High-Level Architectural Synthesis: Group related code changes by their overarching engineering goal (e.g. Docker environment, Auth refactoring, DB schema migration, API error handling). NEVER list individual files, line numbers, or minute code edits. Strictly consolidate related changes into a maximum of 4 to 5 high-impact bullet points. Do not split one feature into multiple micro-bullets.
  4. Bullet format: Use '- ' followed by an imperative capitalized verb (e.g., '- Implement...', '- Refactor...', '- Fix...', '- Optimize...', '- Enable...'). Do NOT prepend redundant sub-types like 'feat(file):' or 'chore(file):' on each bullet point.
  5. Output ONLY the raw commit message text. Absolutely NO intro/outro, NO analysis explanations, NO markdown code blocks.

GENERAL QUERY RULES:
- If asked a technical question, debugging analysis, or comparison, answer directly with crisp, actionable bullet points.
- STRICT FORMAT: NO greetings, NO intro fluff, NO boilerplate. STRICTLY NO markdown headings (#), NO bold asterisks (**), NO code fences. Output clean terminal plain text."
  _call_gemini_api "\$sys_prompt" "\$prompt"
}
EOF
fi

# Write closing tag
cat <<EOF >> "$TARGET_RC"

# --- END AI CLI ASSISTANT ---
EOF

echo ""
echo "=== [4/4] Installation completed! ==="
echo "Run the following command to activate immediately:"
echo "source $TARGET_RC"
echo ""
echo "Type 'afe-help' anytime to view the command cheat-sheet."