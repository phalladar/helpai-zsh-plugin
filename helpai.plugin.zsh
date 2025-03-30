# Oh My Zsh plugin file for 'helpai'

# --- Global variable and Hook for capturing last status ---
_HELP_AI_LAST_STATUS=0
_helpai_capture_status() { _HELP_AI_LAST_STATUS=$?; }
if command -v add-zsh-hook >/dev/null 2>&1; then add-zsh-hook precmd _helpai_capture_status; else if [[ -z "${precmd_functions[(r)_helpai_capture_status]}" ]]; then precmd_functions=(_helpai_capture_status "${precmd_functions[@]}"); fi; fi
# --- End Hook Setup ---


# --- Main helpai function ---
helpai() {
  # --- Configuration ---
  local CLAUDE_API_ENDPOINT="https://api.anthropic.com/v1/messages"
  local CLAUDE_MODEL="claude-3-7-sonnet-20250219" # Ensure valid model
  local MAX_TOKENS=1024
  # --- End Configuration ---

  # Prerequisite checks
  if ! command -v jq &> /dev/null; then echo "Error: 'jq' not found." >&2; return 1; fi
  if ! command -v curl &> /dev/null; then echo "Error: 'curl' not found." >&2; return 1; fi
  if [[ -z "$CLAUDE_API_KEY" ]]; then echo "Error: CLAUDE_API_KEY env var not set." >&2; return 1; fi

  # Read exit status captured by the precmd hook
  local last_exit_status=${_HELP_AI_LAST_STATUS:--1}

  local last_command; last_command=$(fc -ln -1 | sed 's/^[[:space:]]*//')

  if [[ "$last_command" == "helpai" ]]; then
     last_command=$(fc -ln -2 | head -n 1 | sed 's/^[[:space:]]*//')
     echo "Warning: Analyzing cmd before prior 'helpai'. Status ($last_exit_status) may be inaccurate." >&2
  fi

  local os_type=${OSTYPE:-$(uname -s)}

  echo "Analyzing command: $last_command"
  echo "Exit status: $last_exit_status"
  echo "Attempting to retrieve last command output via iTerm2 API..."

  # --- Attempt to call Python script to get output ---
  local last_output="" # Initialize empty
  local python_script_path="${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/helpai/get_last_output.py"
  local python_executable="python3"

  # Check prerequisite environment variable only if script exists
  if [[ -x "$python_script_path" ]]; then
      if [[ -z "$ITERM_SESSION_ID" ]]; then
          echo "Warning: ITERM_SESSION_ID not found. Cannot capture output." >&2
      else
          # Run python script, capture stdout, HIDE stderr for normal use
          last_output=$(command $python_executable "$python_script_path" 2>/dev/null)
          if [[ $? -ne 0 ]]; then
              # Python script itself failed execution (permissions, not found, internal crash)
              echo "Warning: Python script for output capture failed to execute correctly." >&2
              last_output="" # Ensure empty on failure
          # elif [[ -z "$last_output" ]]; then
              # Optional: Debug message if script ran ok but found no output (markers missing)
              # echo "Debug: Python script ran but found no output (markers likely missing)." >&2
          fi
      fi
  # else # Don't warn if script doesn't exist - maybe user intentionally removed it
      # echo "Warning: Python script $python_script_path not found or not executable." >&2
  fi
  # --- End Get Output ---

  echo "Asking Claude for help (Model: $CLAUDE_MODEL)..."

  # --- Construct Prompt ---
  local prompt_text
  prompt_text="I ran the following command in my Zsh terminal (OS type: $os_type):\n\n"
  prompt_text+="\`\`\`bash\n$last_command\n\`\`\`\n\n"
  prompt_text+="It finished with exit status: $last_exit_status\n\n"

  # --- Add captured output (truncated) IF it was captured ---
  local output_char_limit=2000; local output_line_limit=50
  local truncated_output=""

  if [[ -n "$last_output" ]]; then
      # Output WAS captured successfully
      echo "Output captured, adding to prompt (truncated if needed)."
      truncated_output=$(echo "$last_output" | tail -n $output_line_limit)
      if [[ ${#truncated_output} -gt $output_char_limit ]]; then
           truncated_output=${truncated_output: -$output_char_limit}
           echo "(Output truncated to last ${output_char_limit} chars for prompt)" >&2
      fi
      prompt_text+="\nThe command produced the following output (potentially truncated):\n\`\`\`\n"
      printf -v prompt_text -- '%s%s\n' "$prompt_text" "$truncated_output"
      prompt_text+="\`\`\`\n"
  else
      # Output was NOT captured (Python script failed or found no markers)
      echo "Warning: Failed to automatically capture command output (requires iTerm2 with working Shell Integration markers)." >&2
      # Do NOT add the output section to the prompt
  fi
  # --- End Add Output ---

  # Add final analysis request and conciseness instructions
  prompt_text+="\nPlease analyze this command, its exit status, and its output (if provided). What might have gone wrong? How can I fix it or achieve the intended goal?"
  prompt_text+="\nTry to be concise in your answer. The user may be frustrated and won't want to read pages."
  prompt_text+="\nPick your most plausible solution and pitch it."
  prompt_text+="\n\nIMPORTANT: If you identify a specific command that is the most likely fix for the user's problem, please append ONLY that command string to the VERY END of your response, enclosed in <userfix> and </userfix> tags. Example: <userfix>git push --set-upstream origin main</userfix>. Do not add any explanation within or after these tags." # <-- ADDED INSTRUCTION
  # --- End Construct Prompt ---

  # Prepare JSON payload
  local json_payload; json_payload=$(jq -n --arg model "$CLAUDE_MODEL" --argjson max_tokens "$MAX_TOKENS" --arg prompt "$prompt_text" '{model: $model, max_tokens: $max_tokens, messages: [{"role": "user", "content": $prompt}]}')
  if [[ $? -ne 0 ]]; then echo "Error: Failed to create JSON payload." >&2; return 1; fi

  # Make API Call
  local response; response=$(curl -s "$CLAUDE_API_ENDPOINT" -H "x-api-key: $CLAUDE_API_KEY" -H "anthropic-version: 2023-06-01" -H "content-type: application/json" -d "$json_payload")
  local curl_exit_status=$?; if [[ $curl_exit_status -ne 0 ]]; then echo "Error: curl failed (status: $curl_exit_status)." >&2; echo "Response: $response" >&2; return 1; fi

  # Save response to temp file, setup cleanup
  local temp_response_file; temp_response_file=$(mktemp)
  # Ensure cleanup happens reliably on exit/signals
  trap 'rm -f "$temp_response_file" >/dev/null 2>&1; trap - EXIT INT TERM HUP' EXIT INT TERM HUP
  printf "%s" "$response" > "$temp_response_file"

  # --- Enhanced Response Processing ---

  # Step 1: Validate JSON structure before extracting anything
  if ! jq -e '.' "$temp_response_file" > /dev/null 2>&1; then
    echo "Error: Invalid JSON received from API." >&2
    # Attempt to show raw response for debugging if it's not too large
    if [[ $(wc -c < "$temp_response_file") -lt 5000 ]]; then
        echo "Raw response:" >&2
        cat "$temp_response_file" >&2
    fi
    # Cleanup is handled by trap
    return 1
  fi

  # Step 2: Extract the main message content safely
  local assistant_message
  # Use jq's exit status (-e) and check for null/empty result
  assistant_message=$(jq -re '.content[0].text // ""' "$temp_response_file")
  local jq_extract_status=$?
  if [[ $jq_extract_status -ne 0 ]]; then
      echo "Error: Failed to extract '.content[0].text' from JSON (jq exit: $jq_extract_status)." >&2
      echo "Raw JSON structure:" >&2
      jq '.' "$temp_response_file" >&2 # Show structure for debugging
      # Cleanup is handled by trap
      return 1
  elif [[ -z "$assistant_message" ]]; then
      echo "Warning: Received empty message content from Claude." >&2
      # Continue, but the message will be empty
  fi

  # --- Feature: Extract <userfix> command, copy to clipboard, hide from output ---
  local fix_command=""
  local display_message="$assistant_message" # Start with the full message

  # Check if the specific tags exist in the message
  if [[ "$assistant_message" == *'<userfix>'* && "$assistant_message" == *'</userfix>'* ]]; then
      # Extract content using Zsh parameter expansion (robust for special chars)
      fix_command=${assistant_message##*<userfix>}   # Remove prefix up to start tag
      fix_command=${fix_command%<\/userfix>*}      # Remove suffix from end tag

      # Prepare the message for display: remove the tag block and trim whitespace
      display_message=${assistant_message%<userfix>*}
      # Trim trailing whitespace/newlines robustly
      display_message=${display_message%%[[:space:]]}

      if [[ -n "$fix_command" ]]; then
          # Determine the appropriate clipboard command
          local clipboard_cmd=""
          local clipboard_tool_name="" # For user message
          if command -v pbcopy >/dev/null 2>&1; then
              clipboard_cmd="pbcopy"
              clipboard_tool_name="pbcopy (macOS)"
          elif command -v wl-copy >/dev/null 2>&1; then
              clipboard_cmd="wl-copy"
              clipboard_tool_name="wl-copy (Wayland)"
          elif command -v xclip >/dev/null 2>&1; then
              # Check if DISPLAY is set for xclip
              if [[ -n "$DISPLAY" ]]; then
                  clipboard_cmd="xclip -selection clipboard"
                  clipboard_tool_name="xclip (X11)"
              else
                  echo "Warning: xclip found, but \$DISPLAY not set. Cannot copy to X11 clipboard." >&2
              fi
          elif command -v xsel >/dev/null 2>&1; then
              # Check if DISPLAY is set for xsel
              if [[ -n "$DISPLAY" ]]; then
                   clipboard_cmd="xsel --clipboard --input"
                   clipboard_tool_name="xsel (X11)"
              else
                   echo "Warning: xsel found, but \$DISPLAY not set. Cannot copy to X11 clipboard." >&2
              fi
          fi

          # Attempt to copy if a command was found and is usable
          if [[ -n "$clipboard_cmd" ]]; then
              printf "%s" "$fix_command" | $clipboard_cmd # Use the detected command string directly
              local copy_exit_status=$?
              if [[ $copy_exit_status -eq 0 ]]; then
                   # Use stderr for the notification so it doesn't interfere with potential scripting
                   echo "[Suggested fix command copied to clipboard via $clipboard_tool_name.]" >&2
              else
                   echo "Warning: Found fix command but failed to copy to clipboard (command: '$clipboard_cmd', status: $copy_exit_status)." >&2
                   echo "Suggested fix was:" >&2 # Show it only if copy failed
                   echo "$fix_command" >&2
              fi
          else
              echo "Warning: Found fix command but no suitable clipboard tool (pbcopy, wl-copy, xclip, xsel) found or usable." >&2
              echo "Suggested fix was:" >&2 # Show it if no tool
              echo "$fix_command" >&2
          fi
      else
          # Tags were present but empty, treat as if no command was provided.
          echo "Debug: <userfix> tags found but were empty." >&2
      fi
  # else
      # Debug: No <userfix> tags found in the response.
      # echo "Debug: No <userfix> tags found." >&2
  fi
  # --- End Feature ---

  # Final cleanup is handled by the trap

  # Print the potentially modified message (without the <userfix> block)
  echo "\n--- Claude's Suggestion ---"
  # Use printf for potentially complex message content
  printf "%s\n" "$display_message"
  echo "---------------------------\n"

  return 0
}