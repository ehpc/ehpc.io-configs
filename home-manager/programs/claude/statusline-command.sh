#!/usr/bin/env bash
# Status line inspired by Starship Catppuccin Mocha config
# Reads JSON from Claude Code via stdin

input=$(cat)

# --- Claude Code context ---
MODEL=$(echo "$input" | jq -r '.model.display_name')
CWD=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# --- Directory: truncate to last 3 path segments (mirrors starship truncation_length=3) ---
DIR=$(echo "$CWD" | awk -F'/' '{
  n=split($0,a,"/");
  if(n<=3) print $0;
  else { out=a[n-2] "/" a[n-1] "/" a[n]; print ".../" out }
}')

# --- Git info (skip locks to avoid blocking) ---
GIT_BRANCH=""
GIT_STATUS=""
if git -C "$CWD" rev-parse --is-inside-work-tree --no-optional-locks 2>/dev/null | grep -q true; then
  GIT_BRANCH=$(git -C "$CWD" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null \
               || git -C "$CWD" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  if [ -n "$(git -C "$CWD" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
    GIT_STATUS="*"
  fi
fi

# --- Catppuccin Mocha ANSI colors ---
RED='\033[38;2;243;139;168m'
PEACH='\033[38;2;250;179;135m'
YELLOW='\033[38;2;249;226;175m'
GREEN='\033[38;2;166;227;161m'
LAVENDER='\033[38;2;180;190;254m'
RESET='\033[0m'

# --- Assemble status line ---
# Format:  user |  dir |  branch* |   time | model | ctx%
USER_PART=" $(whoami)"
DIR_PART=" $DIR "
TIME_PART="  $(date +%H:%M) "
MODEL_PART=" $MODEL"
CTX_PART=""
if [ -n "$PCT" ]; then
  PCT_INT=$(printf "%.0f" "$PCT")
  CTX_PART=" | ${PCT_INT}% ctx"
fi

printf "${RED}${USER_PART}${RESET}"
printf " ${PEACH}${DIR_PART}${RESET}"
if [ -n "$GIT_BRANCH" ]; then
  printf " ${YELLOW}  ${GIT_BRANCH}${GIT_STATUS} ${RESET}"
fi
printf " ${LAVENDER}${TIME_PART}${RESET}"
printf " ${GREEN}${MODEL_PART}${CTX_PART} ${RESET}"
