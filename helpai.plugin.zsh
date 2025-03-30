# Oh My Zsh plugin file for 'helpai' - defines the helpai() function.

# --- Global variable and Hook for capturing last status ---
# Global variable to store the exit status reliably before the prompt overwrites $?
_HELP_AI_LAST_STATUS=0

# Hook function executed before each prompt using Zsh's precmd hook mechanism
_helpai_capture_status() {
  _HELP_AI_LAST_STATUS=$?
}

# Register the hook function to run before the command prompt appears.
# Uses add-zsh-hook if available (standard in OMZ), otherwise modifies precmd_functions array.
if command -v add-zsh-hook >/dev/null 2>&1; then
    add-zsh-hook precmd _helpai_capture_status
else
    # Fallback for older Zsh versions lacking add-zsh-hook
    if [[ -z "${precmd_functions[(r)_helpai_capture_status]}" ]]; then
        precmd_functions=(_helpai_capture_status "${precmd_functions[@]}")
    fi
fi
# --- End Hook Setup ---


# --- Main helpai function ---
helpai() {
  # --- Configuration ---
  local CLAUDE_API_ENDPOINT="https://api.anthropic.com/v1/messages"
  local CLAUDE_MODEL="claude-3-7-sonnet-20250219" # Ensure this model is valid for your key
  local MAX_TOKENS=1024
  # --- End Configuration ---

  # Prerequisite checks
  if ! command -v jq &> /dev/null; then echo "Error: 'jq' not found." >&2; return 1; fi
  if ! command -v curl &> /dev/null; then echo "Error: 'curl' not found." >&2; return 1; fi
  if [[ -z "$CLAUDE_API_KEY" ]]; then echo "Error: CLAUDE_API_KEY env var not set." >&2; return 1; fi

  # Read the exit status reliably captured by the precmd hook.
  # Default to -1 if the global var isn't set (shouldn't happen after first prompt).
  local last_exit_status=${_HELP_AI_LAST_STATUS:--1}

  local last_command
  last_command=$(fc -ln -1 | sed 's/^[[:space:]]*//')

  # Avoid analyzing the 'helpai' command itself if run consecutively.
  # Status read will be from the *first* helpai call in this case.
  if [[ "$last_command" == "helpai" ]]; then
     last_command=$(fc -ln -2 | head -n 1 | sed 's/^[[:space:]]*//')
     echo "Warning: Analyzing command before the previous 'helpai'. Exit status ($last_exit_status) might be inaccurate for that specific prior command." >&2
  fi

  # Get OS Type using Zsh's $OSTYPE, fallback to `uname` if needed.
  local os_type=${OSTYPE:-$(uname -s)}

  echo "Analyzing command: $last_command"
  echo "Exit status: $last_exit_status" # Should now be correct for failed commands too
  echo "Asking Claude for help (Model: $CLAUDE_MODEL)..."

  local prompt_text
  # Updated prompt text to include the detected OS type
  prompt_text="I ran the following command in my Zsh terminal (OS type: $os_type):\n\n"
  prompt_text+="\`\`\`bash\n$last_command\n\`\`\`\n\n"
  prompt_text+="It finished with exit status: $last_exit_status\n\n"
  prompt_text+="Please analyze this command and exit status. What might have gone wrong? How can I fix it or achieve the intended goal?"
  prompt_text+="\n(Note: I don't have the command's output available to provide automatically)."
  prompt_text+="Try to be concise in your answer. The user may be frustrated and won't want to read pages."
  prompt_text+="Pick your most plausible solution and pitch it."

  local json_payload
  json_payload=$(jq -n --arg model "$CLAUDE_MODEL" --argjson max_tokens "$MAX_TOKENS" --arg prompt "$prompt_text" \
    '{model: $model, max_tokens: $max_tokens, messages: [{"role": "user", "content": $prompt}]}')

  if [[ $? -ne 0 ]]; then echo "Error: Failed to create JSON payload." >&2; return 1; fi

  local response
  response=$(curl -s "$CLAUDE_API_ENDPOINT" \
    -H "x-api-key: $CLAUDE_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$json_payload")

  local curl_exit_status=$?
  if [[ $curl_exit_status -ne 0 ]]; then
    echo "Error: curl command failed with exit status $curl_exit_status." >&2
    echo "Response (if any): $response" >&2
    return 1
  fi

  # Save response to a temporary file for multi-step parsing
  local temp_response_file
  temp_response_file=$(mktemp)
  trap 'rm -f "$temp_response_file"' EXIT INT TERM HUP
  printf "%s" "$response" > "$temp_response_file"

  # Step 1: Validate overall JSON structure
  if ! jq '.' "$temp_response_file" > /dev/null 2>&1; then
      echo "Error: Basic JSON parsing failed on the response." >&2
      echo "Raw response snippet:" >&2; head -c 500 "$temp_response_file" >&2; echo "..." >&2
      rm -f "$temp_response_file"; trap - EXIT INT TERM HUP; return 1
  fi

  # Step 2: Extract the specific message field as a JSON string
  local assistant_message_json_string
  assistant_message_json_string=$(jq '.content[0].text' "$temp_response_file" 2>/dev/null)
  local jq_extract_exit_status=$?

  if [[ $jq_extract_exit_status -ne 0 || -z "$assistant_message_json_string" ]]; then
      echo "Error: Failed to extract '.content[0].text' (jq exit: $jq_extract_exit_status)." >&2
      echo "Response structure might be unexpected. Full structure attempt:" >&2
      if ! jq '.' "$temp_response_file" 2>/dev/null; then
          echo "[jq '.' failed, attempting 'cat -v']" >&2; cat -v "$temp_response_file" >&2
      fi
      echo "--- End of response structure ---"
      rm -f "$temp_response_file"; trap - EXIT INT TERM HUP; return 1
  fi

  # Step 3: Decode the extracted JSON string to raw text
  local assistant_message
  assistant_message=$(printf '%s' "$assistant_message_json_string" | jq -r '.' 2>/dev/null)
  local jq_decode_exit_status=$?

  if [[ $jq_decode_exit_status -ne 0 ]]; then
      echo "Error: Failed to decode the extracted JSON string with 'jq -r .'." >&2
      echo "Extracted JSON string that failed decoding:" >&2
      echo "$assistant_message_json_string" >&2
      rm -f "$temp_response_file"; trap - EXIT INT TERM HUP; return 1
  fi

  # Cleanup on success
  rm -f "$temp_response_file"
  trap - EXIT INT TERM HUP

  echo "\n--- Claude's Suggestion ---"
  printf "%s\n" "$assistant_message"
  echo "---------------------------\n"

  return 0
}

# Ensure no other executable code is outside the function/hook definitions.