#!/usr/bin/env bash

# <xbar.title>GitHub Actions Monitor</xbar.title>
# <xbar.version>v1.0</xbar.version>
# <xbar.author>Eddy Pechuzal</xbar.author>
# <xbar.desc>Monitor GitHub Actions workflow status across repos</xbar.desc>
# <xbar.dependencies>gh</xbar.dependencies>

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# xbar runs in a minimal environment — source localrc for GH_TOKEN etc.
[ -f "$HOME/.localrc" ] && source "$HOME/.localrc"

CONFIG_FILE="$HOME/.xbar-github-actions.conf"
LOCAL_CONFIG="$HOME/.xbar-github-actions.local.conf"

# Local config overrides default entirely
if [ -f "$LOCAL_CONFIG" ]; then
  CONFIG_FILE="$LOCAL_CONFIG"
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "⚙️ GH Actions"
  echo "---"
  echo "No config found | color=orange"
  echo "Create ~/.xbar-github-actions.conf | color=gray"
  echo "or ~/.xbar-github-actions.local.conf | color=gray"
  echo "---"
  echo "Format: owner/repo workflow_name | color=gray"
  echo "Example: epechuzal/scinfax Deploy to Production | color=gray"
  exit 0
fi

if ! command -v gh &>/dev/null; then
  echo "❌ GH Actions"
  echo "---"
  echo "gh CLI not found | color=red"
  exit 0
fi

if ! gh auth status &>/dev/null 2>&1; then
  echo "🔑 GH Actions"
  echo "---"
  echo "gh not authenticated | color=red"
  echo "Run: gh auth login | bash='echo gh auth login'"
  exit 0
fi

has_failure=false
has_running=false
entries=""

while IFS= read -r line; do
  # Skip comments and blank lines
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// /}" ]] && continue

  # Parse: owner/repo<whitespace>workflow name
  repo=$(echo "$line" | awk '{print $1}')
  workflow=$(echo "$line" | sed 's/^[^ ]* //')

  if [ -z "$repo" ] || [ -z "$workflow" ]; then
    continue
  fi

  # Get the most recent run for this workflow
  run_json=$(gh run list \
    --repo "$repo" \
    --workflow "$workflow" \
    --limit 1 \
    --json databaseId,status,conclusion,headBranch,event,createdAt,updatedAt,url,displayTitle \
    2>/dev/null)

  if [ $? -ne 0 ] || [ -z "$run_json" ] || [ "$run_json" = "[]" ]; then
    entries+="⚪ $repo — $workflow | color=gray\n"
    entries+="--No runs found\n"
    continue
  fi

  status=$(echo "$run_json" | /opt/homebrew/bin/jq -r '.[0].status')
  conclusion=$(echo "$run_json" | /opt/homebrew/bin/jq -r '.[0].conclusion')
  branch=$(echo "$run_json" | /opt/homebrew/bin/jq -r '.[0].headBranch')
  title=$(echo "$run_json" | /opt/homebrew/bin/jq -r '.[0].displayTitle')
  created=$(echo "$run_json" | /opt/homebrew/bin/jq -r '.[0].createdAt')
  updated=$(echo "$run_json" | /opt/homebrew/bin/jq -r '.[0].updatedAt')
  url=$(echo "$run_json" | /opt/homebrew/bin/jq -r '.[0].url')
  run_id=$(echo "$run_json" | /opt/homebrew/bin/jq -r '.[0].databaseId')

  # Determine icon and color
  if [ "$status" = "completed" ]; then
    case "$conclusion" in
      success)   icon="✅"; color="green" ;;
      failure)   icon="❌"; color="red"; has_failure=true ;;
      cancelled) icon="⏹"; color="orange" ;;
      *)         icon="❓"; color="gray" ;;
    esac
  elif [ "$status" = "in_progress" ] || [ "$status" = "queued" ] || [ "$status" = "waiting" ]; then
    icon="🔄"; color="yellow"; has_running=true
  else
    icon="❓"; color="gray"
  fi

  # Compute timing
  created_epoch=$(TZ=UTC date -jf "%Y-%m-%dT%H:%M:%SZ" "$created" "+%s" 2>/dev/null)
  updated_epoch=$(TZ=UTC date -jf "%Y-%m-%dT%H:%M:%SZ" "$updated" "+%s" 2>/dev/null)

  fmt_duration() {
    local secs=$1
    if [ "$secs" -ge 3600 ]; then
      echo "$((secs / 3600))h $((secs % 3600 / 60))m"
    elif [ "$secs" -ge 60 ]; then
      echo "$((secs / 60))m $((secs % 60))s"
    else
      echo "${secs}s"
    fi
  }

  if [ "$status" != "completed" ]; then
    # In-progress: show elapsed since start
    now_epoch=$(date "+%s")
    if [ -n "$created_epoch" ]; then
      time_line="Running for $(fmt_duration $((now_epoch - created_epoch)))"
    else
      time_line="Running"
    fi
  else
    # Completed: show outcome + duration + end time
    case "$conclusion" in
      success)   status_label="Passed" ;;
      failure)   status_label="Failed" ;;
      cancelled) status_label="Cancelled" ;;
      *)         status_label="Ran" ;;
    esac
    end_time=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$updated" "+%b %d %H:%M" 2>/dev/null || echo "$updated")
    if [ -n "$created_epoch" ] && [ -n "$updated_epoch" ] && [ "$updated_epoch" -gt "$created_epoch" ]; then
      time_line="$status_label after $(fmt_duration $((updated_epoch - created_epoch))) · $end_time"
    else
      time_line="$status_label · $end_time"
    fi
  fi

  short_repo=$(echo "$repo" | cut -d'/' -f2)

  entries+="$icon $short_repo — $workflow | color=$color\n"
  entries+="--$title | color=$color\n"
  entries+="--Branch: $branch | color=gray\n"
  entries+="--$time_line | color=gray\n"
  entries+="-----\n"
  entries+="--Open in GitHub | href=$url\n"
  if [ "$conclusion" = "failure" ]; then
    entries+="--🔁 Rerun failed jobs | bash=/opt/homebrew/bin/gh param1=run param2=rerun param3=$run_id param4=--repo param5=$repo param6=--failed terminal=false refresh=true\n"
  fi

done < "$CONFIG_FILE"

# Menu bar icon
if $has_failure; then
  echo "❌"
elif $has_running; then
  echo "🔄"
else
  echo "✅"
fi

echo "---"
echo -en "$entries"
echo "---"
echo "Refresh | refresh=true"
