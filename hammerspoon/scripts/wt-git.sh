#!/bin/zsh --no-rcs
set -e

WORKSPACE_DIR="${HOME}/Workspace"
WORKTREES_BASE="${HOME}/Workspace/worktrees"

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

cmd_list_repos() {
  local first=true
  echo '['

  for dir in "${WORKSPACE_DIR}"/*/; do
    [ -d "$dir/.git" ] || continue
    local name=$(basename "$dir")

    cd "$dir"
    local last_commit=$(git log -1 --format='%aI' 2>/dev/null || echo "")
    local last_msg=$(git log -1 --format='%s' 2>/dev/null || echo "")
    local wt_count=$(git worktree list --porcelain 2>/dev/null | grep -c '^worktree ' || echo "0")
    wt_count=$((wt_count - 1))
    [ $wt_count -lt 0 ] && wt_count=0

    [ "$first" = true ] || echo ','
    first=false
    cat <<EOF
  {
    "name": "$(json_escape "$name")",
    "lastCommit": "$(json_escape "$last_commit")",
    "lastCommitMessage": "$(json_escape "$last_msg")",
    "worktreeCount": $wt_count
  }
EOF
  done

  echo ']'
}

cmd_list_worktrees() {
  local repo="$1"
  local repo_dir="${WORKSPACE_DIR}/${repo}"

  [ -d "$repo_dir/.git" ] || { echo '{"error":"Repository not found"}'; exit 1; }

  cd "$repo_dir"
  local main_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")
  local first=true
  echo '['

  # Use process substitution to avoid subshell variable scoping issues
  local wt_path="" branch=""
  while IFS= read -r line; do
    case "$line" in
      worktree\ *)
        wt_path="${line#worktree }"
        ;;
      branch\ *)
        branch="${line#branch refs/heads/}"
        ;;
      "")
        [ "$wt_path" = "$repo_dir" ] && { wt_path=""; branch=""; continue; }
        [ -z "$wt_path" ] && continue

        local wt_name=$(basename "$wt_path")
        local last_commit=""
        local last_msg=""
        local merged="false"

        if [ -d "$wt_path" ]; then
          last_commit=$(git -C "$wt_path" log -1 --format='%aI' 2>/dev/null || echo "")
          last_msg=$(git -C "$wt_path" log -1 --format='%s' 2>/dev/null || echo "")
        fi

        if [ -n "$branch" ]; then
          if git branch --merged "$main_branch" 2>/dev/null | grep -qw "$branch"; then
            merged="true"
          fi
        fi

        [ "$first" = true ] || echo ','
        first=false
        cat <<EOF
  {
    "name": "$(json_escape "$wt_name")",
    "path": "$(json_escape "$wt_path")",
    "branch": "$(json_escape "$branch")",
    "lastCommit": "$(json_escape "$last_commit")",
    "lastCommitMessage": "$(json_escape "$last_msg")",
    "merged": $merged
  }
EOF
        wt_path=""
        branch=""
        ;;
    esac
  done < <(git worktree list --porcelain)

  echo ']'
}

cmd_create() {
  local repo="$1"
  local name="$2"
  local repo_dir="${WORKSPACE_DIR}/${repo}"
  local wt_dir="${WORKTREES_BASE}/${repo}/${name}"

  [ -d "$repo_dir/.git" ] || { echo '{"error":"Repository not found"}'; exit 1; }
  [ -d "$wt_dir" ] && { echo "{\"path\": \"$(json_escape "$wt_dir")\", \"existed\": true}"; exit 0; }

  cd "$repo_dir"
  mkdir -p "${WORKTREES_BASE}/${repo}"

  if ! git worktree add -b "claude/${name}" "$wt_dir" 2>/tmp/wt-git-error.log; then
    local err=$(cat /tmp/wt-git-error.log)
    echo "{\"error\": \"$(json_escape "$err")\"}"
    exit 1
  fi

  if [ ! -f "${wt_dir}/.git" ]; then
    echo '{"error":"Worktree created but .git file missing"}'
    rm -rf "$wt_dir"
    exit 1
  fi

  find . -name ".worktreeinclude" -type f 2>/dev/null | while read -r f; do
    local rel_dir="$(dirname "$f")"
    mkdir -p "${wt_dir}/${rel_dir}"
    cp "$f" "${wt_dir}/${rel_dir}/"
  done

  if [ -f "${repo_dir}/bin/setup-worktree.sh" ]; then
    cd "$wt_dir"
    "${repo_dir}/bin/setup-worktree.sh" "$name" 2>/tmp/wt-git-error.log || true
  fi

  echo "{\"path\": \"$(json_escape "$wt_dir")\", \"existed\": false}"
}

cmd_info() {
  local repo="$1"
  local name="$2"
  local repo_dir="${WORKSPACE_DIR}/${repo}"

  [ -d "$repo_dir/.git" ] || { echo '{"error":"Repository not found"}'; exit 1; }

  cd "$repo_dir"
  local main_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")
  local branch="claude/${name}"

  # Find worktree path
  local wt_path=""
  local current_wt="" current_branch=""
  while IFS= read -r line; do
    case "$line" in
      worktree\ *) current_wt="${line#worktree }" ;;
      branch\ *)   current_branch="${line#branch refs/heads/}" ;;
      "")
        if [ "$(basename "$current_wt")" = "$name" ] && [ "$current_wt" != "$repo_dir" ]; then
          wt_path="$current_wt"
          branch="$current_branch"
        fi
        current_wt=""
        current_branch=""
        ;;
    esac
  done < <(git worktree list --porcelain)

  [ -z "$wt_path" ] && { echo '{"error":"Worktree not found"}'; exit 1; }

  # Merged check (traditional)
  local merged="false"
  if [ -n "$branch" ]; then
    if git branch --merged "$main_branch" 2>/dev/null | grep -qw "$branch"; then
      merged="true"
    fi
  fi

  # Last commit info
  local last_commit=$(git -C "$wt_path" log -1 --format='%aI' 2>/dev/null || echo "")
  local last_msg=$(git -C "$wt_path" log -1 --format='%s' 2>/dev/null || echo "")
  local last_author=$(git -C "$wt_path" log -1 --format='%an' 2>/dev/null || echo "")

  # Commits ahead/behind main
  local ahead=0 behind=0
  if [ -n "$branch" ]; then
    local counts=$(git rev-list --left-right --count "${main_branch}...${branch}" 2>/dev/null || echo "0 0")
    behind=$(echo "$counts" | awk '{print $1}')
    ahead=$(echo "$counts" | awk '{print $2}')
  fi

  # Uncommitted changes
  local dirty="false"
  if [ -d "$wt_path" ]; then
    local wt_status=$(git -C "$wt_path" status --porcelain 2>/dev/null)
    [ -n "$wt_status" ] && dirty="true"
  fi

  # Diff stat against main (shows if work is already in main via squash)
  local diff_files=0
  if [ -n "$branch" ]; then
    diff_files=$(git diff --stat "${main_branch}...${branch}" 2>/dev/null | tail -1 | grep -oE '^[[:space:]]*[0-9]+' | tr -d ' ' || echo "0")
    [ -z "$diff_files" ] && diff_files=0
  fi

  cat <<EOF
{
  "name": "$(json_escape "$name")",
  "branch": "$(json_escape "$branch")",
  "path": "$(json_escape "$wt_path")",
  "merged": $merged,
  "lastCommit": "$(json_escape "$last_commit")",
  "lastCommitMessage": "$(json_escape "$last_msg")",
  "lastAuthor": "$(json_escape "$last_author")",
  "ahead": $ahead,
  "behind": $behind,
  "dirty": $dirty,
  "diffFiles": $diff_files
}
EOF
}

cmd_remove() {
  local repo="$1"
  local name="$2"
  local repo_dir="${WORKSPACE_DIR}/${repo}"

  [ -d "$repo_dir/.git" ] || { echo '{"error":"Repository not found"}'; exit 1; }
  [ "$name" = "main" ] && { echo '{"error":"Cannot remove main"}'; exit 1; }

  cd "$repo_dir"

  # Find worktree by directory name (basename), not branch name
  local wt_path="" wt_branch=""
  local current_wt="" current_branch=""
  while IFS= read -r line; do
    case "$line" in
      worktree\ *) current_wt="${line#worktree }" ;;
      branch\ *)   current_branch="${line#branch refs/heads/}" ;;
      "")
        if [ "$(basename "$current_wt")" = "$name" ] && [ "$current_wt" != "$repo_dir" ]; then
          wt_path="$current_wt"
          wt_branch="$current_branch"
        fi
        current_wt="" current_branch=""
        ;;
    esac
  done < <(git worktree list --porcelain; echo "")

  if [ -z "$wt_path" ]; then
    echo '{"error":"Worktree not found"}'
    exit 1
  fi

  git worktree remove "$wt_path" --force 2>/tmp/wt-git-error.log || true
  [ -n "$wt_branch" ] && git branch -D "$wt_branch" 2>/dev/null || true

  echo '{"success": true}'
}

case "${1:-}" in
  list-repos)     cmd_list_repos ;;
  list-worktrees) cmd_list_worktrees "$2" ;;
  info)           cmd_info "$2" "$3" ;;
  create)         cmd_create "$2" "$3" ;;
  remove)         cmd_remove "$2" "$3" ;;
  *)
    echo '{"error":"Unknown command. Usage: wt-git.sh {list-repos|list-worktrees|create|remove} [args]"}'
    exit 1
    ;;
esac
