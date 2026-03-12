#!/usr/bin/env bash

# <xbar.title>Infra Dashboard</xbar.title>
# <xbar.version>v2.0</xbar.version>
# <xbar.author>Eddy Pechuzal</xbar.author>
# <xbar.desc>Unified infrastructure monitor — GitHub Actions, servers, Docker, custom scripts</xbar.desc>
# <xbar.dependencies>gh,jq</xbar.dependencies>

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
[ -f "$HOME/.localrc" ] && source "$HOME/.localrc"

CONFIG_FILE="$HOME/.xbar-infra.conf"
LOCAL_CONFIG="$HOME/.xbar-infra.local.conf"
[ -f "$LOCAL_CONFIG" ] && CONFIG_FILE="$LOCAL_CONFIG"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "⚙️"
  echo "---"
  echo "No config found | color=orange"
  echo "Create ~/.xbar-infra.conf | color=gray"
  echo "or ~/.xbar-infra.local.conf | color=gray"
  echo "---"
  echo "See xbar/infra-dashboard.conf.example in dotfiles | color=gray"
  exit 0
fi

has_failure=false
has_warning=false
has_running=false

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

# --- Parse config into sections ---
current_section=""
github_actions_lines=()
server_lines=()
script_lines=()

while IFS= read -r line; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// /}" ]] && continue
  if [[ "$line" =~ ^\[(.+)\]$ ]]; then
    current_section="${BASH_REMATCH[1]}"
    continue
  fi
  case "$current_section" in
    github-actions) github_actions_lines+=("$line") ;;
    servers)        server_lines+=("$line") ;;
    scripts)        script_lines+=("$line") ;;
  esac
done < "$CONFIG_FILE"

# --- Collect output per section ---
ga_entries=""
server_entries=""
script_entries=""

# --- GitHub Actions ---
if [ ${#github_actions_lines[@]} -gt 0 ]; then
  gh_available=true
  if ! command -v gh &>/dev/null; then
    ga_entries+="gh CLI not found | color=red\n"
    gh_available=false
    has_failure=true
  elif ! gh auth status &>/dev/null 2>&1; then
    ga_entries+="gh not authenticated | color=red\n"
    gh_available=false
    has_failure=true
  fi

  if $gh_available; then
    for ga_line in "${github_actions_lines[@]}"; do
      repo=$(echo "$ga_line" | awk '{print $1}')
      workflow=$(echo "$ga_line" | sed 's/^[^ ]* //')
      [ -z "$repo" ] || [ -z "$workflow" ] && continue

      run_json=$(gh run list \
        --repo "$repo" \
        --workflow "$workflow" \
        --limit 1 \
        --json databaseId,status,conclusion,headBranch,event,createdAt,updatedAt,url,displayTitle \
        2>/dev/null)

      if [ $? -ne 0 ] || [ -z "$run_json" ] || [ "$run_json" = "[]" ]; then
        ga_entries+="⚪ $(echo "$repo" | cut -d'/' -f2) — $workflow | color=gray\n"
        ga_entries+="--No runs found\n"
        continue
      fi

      status=$(echo "$run_json" | jq -r '.[0].status')
      conclusion=$(echo "$run_json" | jq -r '.[0].conclusion')
      branch=$(echo "$run_json" | jq -r '.[0].headBranch')
      title=$(echo "$run_json" | jq -r '.[0].displayTitle')
      created=$(echo "$run_json" | jq -r '.[0].createdAt')
      updated=$(echo "$run_json" | jq -r '.[0].updatedAt')
      url=$(echo "$run_json" | jq -r '.[0].url')
      run_id=$(echo "$run_json" | jq -r '.[0].databaseId')

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

      created_epoch=$(TZ=UTC date -jf "%Y-%m-%dT%H:%M:%SZ" "$created" "+%s" 2>/dev/null)
      updated_epoch=$(TZ=UTC date -jf "%Y-%m-%dT%H:%M:%SZ" "$updated" "+%s" 2>/dev/null)

      if [ "$status" != "completed" ]; then
        now_epoch=$(date "+%s")
        if [ -n "$created_epoch" ]; then
          time_line="Running for $(fmt_duration $((now_epoch - created_epoch)))"
        else
          time_line="Running"
        fi
      else
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
      ga_entries+="$icon $short_repo — $workflow | color=$color\n"
      ga_entries+="--$title | color=$color\n"
      ga_entries+="--Branch: $branch | color=gray\n"
      ga_entries+="--$time_line | color=gray\n"
      ga_entries+="-----\n"
      ga_entries+="--Open in GitHub | href=$url\n"
      if [ "$conclusion" = "failure" ]; then
        ga_entries+="--🔁 Rerun failed jobs | bash=/opt/homebrew/bin/gh param1=run param2=rerun param3=$run_id param4=--repo param5=$repo param6=--failed terminal=false refresh=true\n"
      fi
    done
  fi
fi

# --- Servers (reachability + Docker) ---
if [ ${#server_lines[@]} -gt 0 ]; then
  for srv_line in "${server_lines[@]}"; do
    host=$(echo "$srv_line" | awk '{print $1}')
    [ -z "$host" ] && continue

    # Check reachability via SSH with short timeout
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" "echo ok" &>/dev/null; then
      # Host is up — get Docker containers
      docker_output=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" \
        "docker ps -a --format '{{.Names}}\t{{.State}}\t{{.Status}}'" 2>/dev/null)

      if [ $? -ne 0 ] || [ -z "$docker_output" ]; then
        server_entries+="✅ $host — up (no Docker info) | color=green\n"
      else
        # Count problems: not running, or running but unhealthy
        problems=0
        total=0
        while IFS=$'\t' read -r _name _state _human_status; do
          total=$((total + 1))
          if [ "$_state" != "running" ]; then
            problems=$((problems + 1))
          elif echo "$_human_status" | grep -q "(unhealthy)"; then
            problems=$((problems + 1))
          fi
        done <<< "$docker_output"

        if [ "$problems" -gt 0 ]; then
          server_entries+="⚠️ $host — $problems of $total container(s) need attention | color=orange\n"
          has_warning=true
        else
          server_entries+="✅ $host — $total container(s) healthy | color=green\n"
        fi

        while IFS=$'\t' read -r name state human_status; do
          if [ "$state" = "running" ] && ! echo "$human_status" | grep -q "(unhealthy)"; then
            server_entries+="--📦 $name — $human_status | color=green\n"
          elif [ "$state" = "running" ]; then
            server_entries+="--⚠️ $name — $human_status | color=orange\n"
          else
            server_entries+="--💀 $name — $human_status | color=red\n"
          fi
        done <<< "$docker_output"
      fi

      server_entries+="-----\n"
      server_entries+="--SSH to $host | bash=/usr/bin/ssh param1=$host terminal=true\n"
    else
      server_entries+="❌ $host — unreachable | color=red\n"
      has_failure=true
    fi
  done
fi

# --- Custom scripts ---
# Each line: /path/to/script  Label
# Script exit 0 = ok, non-zero = failure
# Script stdout = submenu items (prefixed with --)
if [ ${#script_lines[@]} -gt 0 ]; then
  for scr_line in "${script_lines[@]}"; do
    scr_path=$(echo "$scr_line" | awk '{print $1}')
    scr_label=$(echo "$scr_line" | sed 's/^[^ ]* //')
    [ -z "$scr_path" ] && continue
    [ -z "$scr_label" ] && scr_label=$(basename "$scr_path")

    # Expand ~ in path
    scr_path="${scr_path/#\~/$HOME}"

    if [ ! -x "$scr_path" ]; then
      script_entries+="⚪ $scr_label — script not found | color=gray\n"
      continue
    fi

    scr_output=$("$scr_path" 2>/dev/null)
    scr_exit=$?

    if [ $scr_exit -eq 0 ]; then
      script_entries+="✅ $scr_label | color=green\n"
    else
      script_entries+="❌ $scr_label | color=red\n"
      has_failure=true
    fi

    if [ -n "$scr_output" ]; then
      while IFS= read -r scr_out_line; do
        script_entries+="--$scr_out_line\n"
      done <<< "$scr_output"
    fi
  done
fi

# --- Render ---
if $has_failure; then
  echo "❌"
elif $has_warning; then
  echo "⚠️"
elif $has_running; then
  echo "🔄"
else
  echo "✅"
fi

echo "---"

if [ -n "$ga_entries" ]; then
  echo "⚡ GitHub Actions | disabled=true"
  echo -en "$ga_entries"
fi

if [ -n "$server_entries" ]; then
  [ -n "$ga_entries" ] && echo "---"
  echo "🖥 Servers | disabled=true"
  echo -en "$server_entries"
fi

if [ -n "$script_entries" ]; then
  ([ -n "$ga_entries" ] || [ -n "$server_entries" ]) && echo "---"
  echo "🔌 Custom | disabled=true"
  echo -en "$script_entries"
fi

echo "---"
echo "Refresh | refresh=true"
