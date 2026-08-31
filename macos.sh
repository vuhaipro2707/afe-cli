#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo ".")"
AFE_VERSION="1.1.4"
if [ -f "$SCRIPT_DIR/version" ]; then
  AFE_VERSION="1.1.4"
fi
echo "$AFE_VERSION" > "$HOME/.afe_version" 2>/dev/null || true

echo "=== [1/4] Checking macOS environment ==="

# 1. Check & Install Homebrew if missing
if ! command -v brew &>/dev/null; then
  echo "Homebrew is not installed. Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

echo "=== [2/4] Installation options ==="

# Ask to install Ollama Local
read -r -p "Do you want to install Local AI (Ollama)? (y/N): " INSTALL_OLLAMA
INSTALL_OLLAMA_FLAG=false
if [[ "$INSTALL_OLLAMA" =~ ^[Yy]$ ]]; then
  INSTALL_OLLAMA_FLAG=true
fi

# Ask to install Gemini Cloud API
read -r -p "Do you want to install Gemini Cloud API? (y/N): " INSTALL_GEMINI
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
echo "  1) English (default)"
echo "  2) Vietnamese (Tiếng Việt)"
read -r -p "Enter choice [1/2 or custom language, default: 1]: " USER_LANG_INPUT
case "$USER_LANG_INPUT" in
  2|[Vv]ietnamese|[Vv]i)
    AI_RESPONSE_LANG="Vietnamese"
    ;;
  1|[Ee]nglish|[Ee]n|"")
    AI_RESPONSE_LANG="English"
    ;;
  *)
    AI_RESPONSE_LANG="$USER_LANG_INPUT"
    ;;
esac
echo "Selected AI Language: $AI_RESPONSE_LANG"
echo ""

# --- Check command name collisions & fallbacks ---
echo "--- Checking command name collisions ---"
check_collision() {
  local short_name="$1"
  local target_file="$HOME/.zshrc"
  local fallback_name="afe-$1"
  local is_taken=false

  if command -v "$short_name" &>/dev/null; then
    is_taken=true
  fi

  if [ -f "$target_file" ]; then
    local clean_rc
    clean_rc=$(sed -e '/# --- AI CLI ASSISTANT BASE ---/,/# --- END AI CLI ASSISTANT ---/d' \
                   -e '/# --- OLLAMA CLI ASSISTANT CONFIG ---/,/# --- END GEMINI CLOUD EXTENSION ---/d' \
                   -e '/# --- HYBRID AI CLI ASSISTANT ---/,/# --- END HYBRID AI CLI ASSISTANT ---/d' \
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
    echo "Installing Ollama via Homebrew..."
    brew install ollama
  fi

  if ! pgrep -x "ollama" > /dev/null; then
    echo "Starting Ollama service..."
    brew services start ollama 2>/dev/null || (ollama serve >/dev/null 2>&1 &)
    sleep 3
  fi

  read -r -p "Enter Ollama Base Model name [default: gemma4:e2b]: " INPUT_MODEL
  BASE_MODEL="${INPUT_MODEL:-gemma4:e2b}"

  echo "Pulling base model: $BASE_MODEL..."
  ollama pull "$BASE_MODEL"

  echo "Creating ask-cli model..."
  TMP_ASK_MODELFILE=$(mktemp)
  cat <<EOF > "$TMP_ASK_MODELFILE"
FROM $BASE_MODEL
TEMPLATE {{ .Prompt }}
SYSTEM "
You are a senior DevOps and CLI assistant.
Convert natural language requests into the exact, executable terminal command.

RULES:
1. Output ONLY the raw executable shell command.
2. STRICTLY PROHIBITED: Do NOT use markdown code blocks or backticks. Do NOT include any explanations, notes, conversational filler, or quotes.
3. Understand developer tooling: Docker, Docker Compose, Kubernetes, Git, Database, Network/OpenSSL, Node.js, Python, macOS BSD tools.
4. Default to macOS (BSD tools) syntax. Preserve exact file paths provided.
5. For text replacement on macOS, always use: sed -i '' 's/old/new/g' filename
6. For Linux text replacement, use: sed -i 's/old/old/g' filename
7. Never invent non-existent commands.
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
You are an expert DevOps engineer and terminal assistant.

RULES:
1. When fixing errors or generating terminal commands:
   - Output ONLY the single raw executable shell command.
   - Do NOT use markdown code blocks or backticks.
   - Output fully resolved, concrete commands using context values. Never use nested subshells to re-evaluate context.
   - Do NOT output explanations, conversational text, or status claims (never say 'Already done' or 'Success').
   - Resolve the root cause (environment, dependencies, permissions, resources, syntax).
2. When answering user requests, questions, or queries:
   - Directly execute the user request using the provided context or piped data.
   - Match the requested format and language strictly.
   - Output clean plain text without markdown backticks, bold asterisks, or headings. Use '-' for bullet points.
3. Default to macOS (BSD tools) syntax.
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

  touch "$ENV_FILE"
  if grep -q "^GEMINI_API_KEY=" "$ENV_FILE"; then
    sed -i '' "s|^GEMINI_API_KEY=.*|GEMINI_API_KEY=\"$USER_GEMINI_KEY\"|" "$ENV_FILE"
  else
    echo "GEMINI_API_KEY=\"$USER_GEMINI_KEY\"" >> "$ENV_FILE"
  fi
  chmod 600 "$ENV_FILE"
  echo "✅ Successfully saved GEMINI_API_KEY securely to $ENV_FILE (chmod 600)"

  read -r -p "Enter GEMINI_MODEL_ID [default: gemma-4-26b-a4b-it]: " INPUT_CLOUD_MODEL
  USER_GEMINI_MODEL="${INPUT_CLOUD_MODEL:-gemma-4-26b-a4b-it}"
fi

echo "=== [3/4] Updating configuration in ~/.zshrc ==="

# Clean up old blocks to ensure idempotency
if [ -f "$HOME/.zshrc" ]; then
  sed -i '' '/# --- AI CLI ASSISTANT BASE ---/,/# --- END AI CLI ASSISTANT ---/d' "$HOME/.zshrc" 2>/dev/null || true
  sed -i '' '/# --- OLLAMA CLI ASSISTANT CONFIG ---/,/# --- END GEMINI CLOUD EXTENSION ---/d' "$HOME/.zshrc" 2>/dev/null || true
  sed -i '' '/# --- HYBRID AI CLI ASSISTANT ---/,/# --- END HYBRID AI CLI ASSISTANT ---/d' "$HOME/.zshrc" 2>/dev/null || true
fi

# 1. Write shared Base Config (Buffer, Screen context, ZLE Widget Ctrl+G, Language, afe-help)
cat <<EOF >> "$HOME/.zshrc"

# --- AI CLI ASSISTANT BASE ---
unsetopt nomatch  # Disable ? globbing error in zsh
export AFE_CLI_VERSION="$AFE_VERSION"
export AI_RESPONSE_LANG="$AI_RESPONSE_LANG"

# Automatically load environment variables from ~/.env if it exists
if [[ -f "\$HOME/.env" ]]; then
  export \$(grep -v '^#' "\$HOME/.env" | xargs)
fi

autoload -Uz add-zsh-hook
_save_last_cmd() {
  local cmd="\$1"
  cmd=\$(echo "\$cmd" | head -n 1 | sed 's/^[[:space:]]*//')
  local first_word="\${cmd%% *}"
  case "\$first_word" in
    $CMD_A|$CMD_AL|$CMD_ALT|$CMD_F|$CMD_FL|$CMD_FLT|$CMD_FE|$CMD_E|$CMD_EL|$CMD_Q|$CMD_QL|$CMD_QLT|afe-help|ai-help|ai)
      ;;
    *)
      if [[ -n "\$cmd" ]]; then
        export LAST_TERMINAL_CMD="\$cmd"
      fi
      ;;
  esac
}
add-zsh-hook preexec _save_last_cmd

_get_terminal_screen_buffer() {
  if [[ "\$TERM_PROGRAM" == "Apple_Terminal" ]]; then
    osascript -e 'tell application "Terminal" to get history of selected tab of front window' 2>/dev/null | tail -n 30
  elif [[ "\$TERM_PROGRAM" == "iTerm.app" ]]; then
    osascript -e 'tell application "iTerm2" to tell current session of current window to get text' 2>/dev/null | tail -n 30
  else
    echo ""
  fi
}

_build_fix_prompt() {
  local query="\$*"
  local last_cmd="\$LAST_TERMINAL_CMD"

  if [[ -z "\$last_cmd" ]]; then
    last_cmd=\$(fc -ln -1 2>/dev/null | sed -E 's/^[[:space:]\x00-\x1F]+//')
    if [[ "\$last_cmd" == ($CMD_F|$CMD_FL|$CMD_FLT|$CMD_FE|$CMD_A|$CMD_AL|$CMD_ALT|$CMD_E|$CMD_EL|$CMD_Q|$CMD_QL|$CMD_QLT|afe|afe-help|ai-help|ai)\ * || "\$last_cmd" == ($CMD_F|$CMD_FL|$CMD_FLT|$CMD_FE|$CMD_A|$CMD_AL|$CMD_ALT|$CMD_E|$CMD_EL|$CMD_Q|$CMD_QL|$CMD_QLT|afe|afe-help|ai-help|ai) ]]; then
      last_cmd=\$(fc -ln -2 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]\x00-\x1F]+//')
    fi
  fi

  local output_data=\$(_get_terminal_screen_buffer | sed -E \$'s/\x1B\\[[0-9;]*[a-zA-Z]//g')

  if [[ -z "\$query" ]]; then
    echo "Recent terminal screen output:
\$output_data
Last executed command: \$last_cmd

Task: Output ONLY the exact raw executable terminal command to resolve the error. No markdown, no explanations."
  else
    echo "Recent terminal screen output:
\$output_data
Last executed command: \$last_cmd
User instruction: \$query

Task: Generate the exact raw executable terminal command to fulfill the user instruction. Use concrete values and text from the context. Do NOT use nested subshells to re-evaluate prior steps."
  fi
}

_build_query_prompt() {
  local query="\$*"
  local stdin_data=""
  if [ ! -t 0 ]; then
    stdin_data=\$(head -n 500)
  fi

  if [[ -n "\$stdin_data" ]]; then
    echo "[USER REQUEST / INSTRUCTION]
\$query

[PIPED INPUT DATA]
\$stdin_data

[REMINDER: FULFILL THIS USER REQUEST IN THE REQUESTED LANGUAGE]
\$query"
  else
    local last_cmd="\$LAST_TERMINAL_CMD"
    if [[ -z "\$last_cmd" ]]; then
      last_cmd=\$(fc -ln -1 2>/dev/null | sed -E 's/^[[:space:]\x00-\x1F]+//')
      if [[ "\$last_cmd" == ($CMD_F|$CMD_FL|$CMD_FLT|$CMD_FE|$CMD_A|$CMD_AL|$CMD_ALT|$CMD_E|$CMD_EL|$CMD_Q|$CMD_QL|$CMD_QLT|afe|afe-help|ai-help|ai)\ * || "\$last_cmd" == ($CMD_F|$CMD_FL|$CMD_FLT|$CMD_FE|$CMD_A|$CMD_AL|$CMD_ALT|$CMD_E|$CMD_EL|$CMD_Q|$CMD_QL|$CMD_QLT|afe|afe-help|ai-help|ai) ]]; then
        last_cmd=\$(fc -ln -2 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]\x00-\x1F]+//')
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
    LBUFFER="\${LBUFFER}\${clean_cmd}"
    zle redisplay
  fi
}
zle -N _insert_last_ai_cmd
bindkey '^G' _insert_last_ai_cmd

afe-help() {
  cat <<'HELP_EOF'
╭──────────────────────────────────────────────────────────────────────────╮
│                             🚀 AFE CLI Help                              │
╰──────────────────────────────────────────────────────────────────────────╯

  ☁️  Cloud Commands (Gemini API):
    $CMD_A <request>       Generate executable terminal command from prompt
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
    afe-update        Update AFE CLI to latest version
────────────────────────────────────────────────────────────────────────────
HELP_EOF
}
afe() {
  case "\$1" in
    -v|--version|version)
      afe-version
      ;;
    -u|--update|update)
      afe-update
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
}
alias afe-v=afe-version

afe-update() {
  echo "🔄 Checking and updating AFE CLI..."
  /bin/bash -c "\$(curl -fsSL https://raw.githubusercontent.com/vuhaipro2707/afe-cli/main/install.sh)" -- install
}
EOF

# 2. Write Ollama Block if selected
if [ "$INSTALL_OLLAMA_FLAG" = true ]; then
cat <<EOF >> "$HOME/.zshrc"

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
cat <<EOF >> "$HOME/.zshrc"

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
    for char in text:
        sys.stdout.write(char)
        sys.stdout.flush()
        time.sleep(0.004)
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
"
}

$CMD_A() {
  local query="\$*"
  [[ "\$1" == "-h" || "\$1" == "--help" ]] && { afe-help; return 0; }
  [[ -z "\$query" ]] && { echo "Usage: $CMD_A <question> (or 'afe-help' for help)"; return 1; }
  local sys_prompt="You are a senior DevOps and CLI assistant for macOS. Convert user requests into exact executable terminal commands. Output ONLY the raw executable shell command. STRICT RULES: Do NOT use markdown code blocks or backticks. Do NOT include any explanations, notes, quotes, or markdown formatting."
  local tmp_file=\$(mktemp)
  _call_gemini_api "\$sys_prompt" "\$query" | tee "\$tmp_file"
  LAST_AI_OUTPUT=\$(<"\$tmp_file")
  rm -f "\$tmp_file"
  _check_dangerous_cmd "\$LAST_AI_OUTPUT"
}

$CMD_F() {
  [[ "\$1" == "-h" || "\$1" == "--help" ]] && { afe-help; return 0; }
  local prompt="\$(_build_fix_prompt "\$*")"
  local sys_prompt="You are an expert macOS terminal command generator.
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
  local sys_prompt="You are an expert macOS terminal troubleshooting assistant.
STRICT RULES:
- Output clean terminal plain text. STRICTLY NO markdown headings, NO bold asterisks, NO backticks.
- Be extremely concise, direct, and technical.
- NO greetings, pleasantries, apologies, intros, or conversational filler.
- Format:
  Cause: 1 short sentence stating the root cause.
  Fix: The exact terminal command(s) needed.
- Language: \${AI_RESPONSE_LANG:-$AI_RESPONSE_LANG}."
  _call_gemini_api "\$sys_prompt" "\$prompt"
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
  local sys_prompt="You are a concise Unix/macOS technical manual.
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
  local sys_prompt="You are an expert DevOps assistant and software engineer.
LANGUAGE RULES (STRICT & ABSOLUTE):
- If the user request mentions Vietnamese / tiếng Việt, you MUST output 100% in Vietnamese (including commit title and all bullet points).
- If the user request mentions English / tiếng Anh, you MUST output 100% in English.
- If no specific language is requested, default to \${AI_RESPONSE_LANG:-$AI_RESPONSE_LANG}.

CORE INSTRUCTIONS:
- Directly execute the exact USER REQUEST using the provided terminal context / piped data.
- If asked to write a git commit message, output ONLY the conventional commit message (1 title line, 1 empty line, bullet points description). Never output intro analysis or section headers.
- If asked a technical question or comparison, answer directly with crisp bullet points.
- STRICT FORMAT: NO greetings, NO intro fluff, NO boilerplate. STRICTLY NO markdown headings, NO bold asterisks, NO code blocks. Output clean terminal plain text."
  _call_gemini_api "\$sys_prompt" "\$prompt"
}
EOF
fi

# Write closing tag
cat <<EOF >> "$HOME/.zshrc"

# --- END AI CLI ASSISTANT ---
EOF

echo ""
echo "=== [4/4] Installation completed! ==="
echo "Run the following command to activate immediately:"
echo "  source ~/.zshrc"
echo ""
echo "Type 'afe-help' anytime to view the command cheat-sheet."