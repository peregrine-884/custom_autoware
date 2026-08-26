#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${1:-autoware.log}"

if [[ ! -f "$LOG_FILE" ]]; then
  echo "Log file not found: $LOG_FILE" >&2
  echo
  echo "Usage:"
  echo "  $0 [LOG_FILE]"
  exit 1
fi

show_menu() {
  cat <<'EOF'

Select information to display:

  1) ERROR
  2) FAILED
  3) Process died
  4) Process exited
  5) WARN
  6) ERROR + FAILED
  7) Node/process failures
  8) All problems
  9) Custom keyword
  0) Exit

EOF
}

run_grep() {
  local pattern="$1"
  local title="$2"

  echo
  echo "============================================================"
  echo "$title"
  echo "============================================================"
  echo

  if ! grep \
      --color=always \
      -Ein \
      "$pattern" \
      "$LOG_FILE"; then
    echo "No matching entries found."
  fi
}

while true; do
  clear

  echo "Autoware Log Viewer"
  echo "Log: $LOG_FILE"

  show_menu

  read -rp "Selection: " selection

  case "$selection" in
    1)
      run_grep \
        '\berror\b|\[ERROR\]' \
        "ERROR"
      ;;

    2)
      run_grep \
        '\bfailed\b|\bfailure\b' \
        "FAILED"
      ;;

    3)
      run_grep \
        'process has died|process.*died|has died' \
        "PROCESS DIED"
      ;;

    4)
      run_grep \
        'process.*exited|process has finished|exited with|exit code' \
        "PROCESS EXITED"
      ;;

    5)
      run_grep \
        '\bwarn(ing)?\b|\[WARN\]' \
        "WARN"
      ;;

    6)
      run_grep \
        '\berror\b|\[ERROR\]|\bfailed\b|\bfailure\b' \
        "ERROR + FAILED"
      ;;

    7)
      run_grep \
        'process has died|process.*died|process.*exited|exited with|exit code|process has finished' \
        "NODE / PROCESS FAILURES"
      ;;

    8)
      run_grep \
        '\berror\b|\[ERROR\]|\bfailed\b|\bfailure\b|process has died|process.*died|process.*exited|exited with|exit code|\bwarn(ing)?\b|\[WARN\]' \
        "ALL PROBLEMS"
      ;;

    9)
      echo
      read -rp "Keyword / regex: " keyword

      if [[ -z "$keyword" ]]; then
        echo "Keyword is empty."
      else
        run_grep "$keyword" "CUSTOM: $keyword"
      fi
      ;;

    0)
      exit 0
      ;;

    *)
      echo
      echo "Invalid selection: $selection"
      ;;
  esac

  echo
  read -rp "Press Enter to return to menu..."
done
