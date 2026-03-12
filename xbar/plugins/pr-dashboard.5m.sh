#!/usr/bin/env bash

# <xbar.title>PR Dashboard</xbar.title>
# <xbar.version>v1.0</xbar.version>
# <xbar.author>Eddy Pechuzal</xbar.author>
# <xbar.desc>Reviews waiting on me and my open PRs/MRs across GitHub and GitLab</xbar.desc>
# <xbar.dependencies>gh,glab,jq</xbar.dependencies>

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
[ -f "$HOME/.localrc" ] && source "$HOME/.localrc"

CONFIG_FILE="$HOME/.xbar-pr.conf"
LOCAL_CONFIG="$HOME/.xbar-pr.local.conf"
[ -f "$LOCAL_CONFIG" ] && CONFIG_FILE="$LOCAL_CONFIG"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "👀 ⚙️"
  echo "---"
  echo "No config found | color=orange"
  echo "Create ~/.xbar-pr.conf or ~/.xbar-pr.local.conf | color=gray"
  echo "---"
  echo "See xbar/pr-dashboard.conf.example in dotfiles | color=gray"
  exit 0
fi

GITHUB_USER=""
GITLAB_USER=""

while IFS= read -r line; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// /}" ]] && continue
  case "$line" in
    github_user=*) GITHUB_USER="${line#github_user=}" ;;
    gitlab_user=*) GITLAB_USER="${line#gitlab_user=}" ;;
  esac
done < "$CONFIG_FILE"

review_entries=""
review_count=0
my_entries=""
my_ci_failing=false

# --- Reviews waiting on me ---

# GitHub reviews
if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
  gh_reviews=$(gh search prs --review-requested=@me --state=open --json repository,title,author,url 2>/dev/null)
  if [ $? -eq 0 ] && [ -n "$gh_reviews" ] && [ "$gh_reviews" != "[]" ]; then
    count=$(echo "$gh_reviews" | jq -r 'length')
    review_count=$((review_count + count))
    for i in $(seq 0 $((count - 1))); do
      repo=$(echo "$gh_reviews" | jq -r ".[$i].repository.nameWithOwner // .[$i].repository.name" 2>/dev/null)
      title=$(echo "$gh_reviews" | jq -r ".[$i].title")
      author=$(echo "$gh_reviews" | jq -r ".[$i].author.login")
      url=$(echo "$gh_reviews" | jq -r ".[$i].url")
      short_repo=$(echo "$repo" | sed 's|.*/||')
      review_entries+="$short_repo: $title ($author) | color=#4078c0\n"
      review_entries+="--Open in browser | href=$url\n"
    done
  fi
else
  review_entries+="⚠️ gh CLI unavailable or not authenticated | color=orange\n"
fi

# GitLab reviews
if [ -n "$GITLAB_USER" ] && command -v glab &>/dev/null; then
  gl_reviews=$(glab mr list --reviewer="$GITLAB_USER" --all --output json 2>/dev/null)
  if [ $? -eq 0 ] && [ -n "$gl_reviews" ] && [ "$gl_reviews" != "[]" ] && [ "$gl_reviews" != "null" ]; then
    count=$(echo "$gl_reviews" | jq -r 'length' 2>/dev/null)
    if [ -n "$count" ] && [ "$count" != "null" ] && [ "$count" -gt 0 ] 2>/dev/null; then
      review_count=$((review_count + count))
      for i in $(seq 0 $((count - 1))); do
        title=$(echo "$gl_reviews" | jq -r ".[$i].title")
        author=$(echo "$gl_reviews" | jq -r ".[$i].author.username")
        url=$(echo "$gl_reviews" | jq -r ".[$i].web_url")
        project=$(echo "$gl_reviews" | jq -r ".[$i].references.full // .[$i].reference" 2>/dev/null | sed 's|!.*||')
        [ -z "$project" ] || [ "$project" = "null" ] && project=$(echo "$url" | sed 's|/-/merge_requests/.*||;s|.*/||')
        review_entries+="$project: $title ($author) | color=#fc6d26\n"
        review_entries+="--Open in browser | href=$url\n"
      done
    fi
  fi
else
  review_entries+="⚠️ glab CLI not found | color=orange\n"
fi

# --- My open PRs/MRs ---

# GitHub — author + assignee, deduplicated by URL
declare -A gh_seen
gh_my_prs=""

fetch_gh_prs() {
  local json
  json=$(gh search prs "$@" --state=open --json repository,title,url,statusCheckRollup 2>/dev/null)
  [ $? -ne 0 ] || [ -z "$json" ] || [ "$json" = "[]" ] && return
  echo "$json"
}

if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
  for query in "--author=@me" "--assignee=@me"; do
    result=$(fetch_gh_prs "$query")
    [ -z "$result" ] && continue
    count=$(echo "$result" | jq -r 'length')
    for i in $(seq 0 $((count - 1))); do
      url=$(echo "$result" | jq -r ".[$i].url")
      [ -n "${gh_seen[$url]}" ] && continue
      gh_seen[$url]=1

      repo=$(echo "$result" | jq -r ".[$i].repository.nameWithOwner // .[$i].repository.name")
      title=$(echo "$result" | jq -r ".[$i].title")
      short_repo=$(echo "$repo" | sed 's|.*/||')

      # CI status from statusCheckRollup
      checks=$(echo "$result" | jq -r ".[$i].statusCheckRollup // []")
      if [ -z "$checks" ] || [ "$checks" = "[]" ] || [ "$checks" = "null" ]; then
        ci_icon="⚪"
        ci_color="gray"
      else
        has_fail=$(echo "$checks" | jq '[.[] | select(.conclusion == "FAILURE" or .conclusion == "ERROR" or .state == "FAILURE" or .state == "ERROR")] | length')
        has_pending=$(echo "$checks" | jq '[.[] | select(.status == "IN_PROGRESS" or .status == "QUEUED" or .status == "PENDING" or .state == "PENDING")] | length')
        has_success=$(echo "$checks" | jq '[.[] | select(.conclusion == "SUCCESS" or .state == "SUCCESS")] | length')

        if [ "$has_fail" -gt 0 ] 2>/dev/null; then
          ci_icon="❌"
          ci_color="red"
          my_ci_failing=true
        elif [ "$has_pending" -gt 0 ] 2>/dev/null; then
          ci_icon="🔄"
          ci_color="yellow"
        elif [ "$has_success" -gt 0 ] 2>/dev/null; then
          ci_icon="✅"
          ci_color="green"
        else
          ci_icon="⚪"
          ci_color="gray"
        fi
      fi

      my_entries+="$ci_icon $short_repo: $title | color=$ci_color\n"
      my_entries+="--Open in browser | href=$url\n"
    done
  done
fi

# GitLab — author + assignee, deduplicated by URL
declare -A gl_seen

fetch_gl_mrs() {
  local json
  json=$(glab mr list "$@" --all --output json 2>/dev/null)
  [ $? -ne 0 ] || [ -z "$json" ] || [ "$json" = "[]" ] || [ "$json" = "null" ] && return
  echo "$json"
}

if [ -n "$GITLAB_USER" ] && command -v glab &>/dev/null; then
  for query in "--author=$GITLAB_USER" "--assignee=$GITLAB_USER"; do
    result=$(fetch_gl_mrs "$query")
    [ -z "$result" ] && continue
    count=$(echo "$result" | jq -r 'length' 2>/dev/null)
    [ -z "$count" ] || [ "$count" = "null" ] && continue
    for i in $(seq 0 $((count - 1))); do
      url=$(echo "$result" | jq -r ".[$i].web_url")
      [ -n "${gl_seen[$url]}" ] && continue
      gl_seen[$url]=1

      title=$(echo "$result" | jq -r ".[$i].title")
      project=$(echo "$url" | sed 's|/-/merge_requests/.*||;s|.*/||')

      # CI status from pipeline
      pipeline_status=$(echo "$result" | jq -r ".[$i].pipeline.status // \"unknown\"" 2>/dev/null)
      case "$pipeline_status" in
        success)  ci_icon="✅"; ci_color="green" ;;
        failed)   ci_icon="❌"; ci_color="red"; my_ci_failing=true ;;
        running|pending|created|waiting_for_resource|preparing|scheduled)
                  ci_icon="🔄"; ci_color="yellow" ;;
        canceled) ci_icon="⏹"; ci_color="orange" ;;
        *)        ci_icon="⚪"; ci_color="gray" ;;
      esac

      my_entries+="$ci_icon $project: $title | color=$ci_color\n"
      my_entries+="--Open in browser | href=$url\n"
    done
  done
fi

# --- Menu bar icon ---
if [ "$review_count" -gt 0 ]; then
  bar_text="👀 $review_count"
else
  bar_text="👀"
fi

if $my_ci_failing; then
  echo "$bar_text 🔴"
else
  echo "$bar_text"
fi

echo "---"

# --- Render sections ---
echo "Reviews waiting on me ($review_count) | disabled=true"
if [ -n "$review_entries" ]; then
  echo -en "$review_entries"
else
  echo "No reviews pending | color=gray"
fi

echo "---"

echo "My open PRs/MRs | disabled=true"
if [ -n "$my_entries" ]; then
  echo -en "$my_entries"
else
  echo "No open PRs/MRs | color=gray"
fi

echo "---"
echo "Refresh | refresh=true"
