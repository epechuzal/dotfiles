#!/bin/bash
# Start EC2 dev box and wait for Tailscale connectivity
# Args: <instance-id> <region> <tailscale-ip>
# Exits 0 on success, 1 on failure. Prints status to stdout.

set -euo pipefail

# Load credentials (not available outside interactive shell)
# shellcheck disable=SC1090
[[ -f ~/.localrc ]] && source ~/.localrc

INSTANCE="$1"
REGION="$2"
TS_IP="$3"
AWS="/opt/homebrew/bin/aws"
TAILSCALE="/usr/local/bin/tailscale"
TIMEOUT=120
LOG="/tmp/start-dev.log"

log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG"; }

echo "--- $(date) ---" >> "$LOG"

log "STARTING instance=$INSTANCE region=$REGION"
if ! $AWS ec2 start-instances --instance-ids "$INSTANCE" --region "$REGION" >>"$LOG" 2>&1; then
  log "FAILED: aws ec2 start-instances"
  echo "FAILED_START"
  exit 1
fi

log "WAITING_EC2"
if ! $AWS ec2 wait instance-running --instance-ids "$INSTANCE" --region "$REGION" 2>>"$LOG"; then
  log "FAILED: aws ec2 wait instance-running"
  echo "FAILED_EC2_WAIT"
  exit 1
fi

log "WAITING_TAILSCALE"
deadline=$((SECONDS + TIMEOUT))
while (( SECONDS < deadline )); do
  if $TAILSCALE status 2>/dev/null | grep "$TS_IP" | grep -qv offline; then
    log "READY"
    echo "READY"
    exit 0
  fi
  sleep 2
done

log "TIMEOUT waiting for Tailscale ($TIMEOUT s)"
$TAILSCALE status 2>&1 | head -20 >> "$LOG"
echo "TIMEOUT"
exit 1
