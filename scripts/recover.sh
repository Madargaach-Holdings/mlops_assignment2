#!/bin/bash

# Guarded recovery script:
# 1) Health check URL
# 2) If unhealthy, try systemd restart via SSH
# 3) If still unhealthy or SSH fails, run deploy.sh (with lock + cooldown)

set -euo pipefail

# --- CONFIG ---
URL="${URL:-http://paffenroth-23.dyn.wpi.edu:8010/}"
REMOTE_USER="${REMOTE_USER:-student-admin}"
REMOTE_HOST="${REMOTE_HOST:-paffenroth-23.dyn.wpi.edu}"
REMOTE_PORT="${REMOTE_PORT:-22010}"
SSH_KEY="${SSH_KEY:-/home/ujjwal/.ssh/my_key}"
SERVICE_NAME="${SERVICE_NAME:-hugging_face_mood_app.service}"
DEPLOY_SCRIPT="${DEPLOY_SCRIPT:-/home/ujjwal/mlops_assignment2/deploy.sh}"
LOCK_FILE="${LOCK_FILE:-/home/ujjwal/mlops_assignment2/.recover.lock}"
COOLDOWN_FILE="${COOLDOWN_FILE:-/home/ujjwal/mlops_assignment2/.recover.last}"
COOLDOWN_SECS="${COOLDOWN_SECS:-1800}"  # 30 minutes
LOG_FILE="${LOG_FILE:-/home/ujjwal/mlops_assignment2/recover.log}"

timestamp() { date +"%Y-%m-%dT%H:%M:%S%z"; }
log() { echo "$(timestamp) | $*" | tee -a "${LOG_FILE}"; }

# Health check
if curl -fsS -m 10 -o /dev/null "${URL}"; then
  log "Healthy: ${URL}"
  exit 0
fi
log "Unhealthy: ${URL}"

# Try systemd restart first
if ssh -i "${SSH_KEY}" -o BatchMode=yes -p "${REMOTE_PORT}" "${REMOTE_USER}@${REMOTE_HOST}" \
  "systemctl --user restart ${SERVICE_NAME}"; then
  log "Issued systemd restart"
  sleep 10
  if curl -fsS -m 10 -o /dev/null "${URL}"; then
    log "Recovered: service restart succeeded"
    exit 0
  fi
  log "Still unhealthy after restart"
else
  log "SSH/systemd restart failed"
fi

# Escalate to redeploy with lock + cooldown
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
  log "Another recovery in progress; exiting"
  exit 0
fi

now=$(date +%s)
if [ -f "${COOLDOWN_FILE}" ]; then
  last=$(cat "${COOLDOWN_FILE}" || echo 0)
  if [ $(( now - last )) -lt "${COOLDOWN_SECS}" ]; then
    log "Cooldown active; skipping redeploy"
    exit 0
  fi
fi
echo "${now}" > "${COOLDOWN_FILE}"

# Ensure HF token available: prefer env; else optional config file
if [ -z "${HUGGING_FACE_TOKEN:-}" ] && [ -f "/home/ujjwal/.config/mlops_assignment2.env" ]; then
  # shellcheck disable=SC1091
  source "/home/ujjwal/.config/mlops_assignment2.env"
fi
if [ -z "${HUGGING_FACE_TOKEN:-}" ]; then
  log "ERROR: HUGGING_FACE_TOKEN not set; cannot redeploy"
  exit 1
fi

log "Starting redeploy via ${DEPLOY_SCRIPT}"
if HUGGING_FACE_TOKEN="${HUGGING_FACE_TOKEN}" "${DEPLOY_SCRIPT}" >> "${LOG_FILE}" 2>&1; then
  sleep 10
  if curl -fsS -m 10 -o /dev/null "${URL}"; then
    log "Recovered: redeploy succeeded"
    exit 0
  else
    log "ERROR: Redeploy completed but app still unhealthy"
    exit 1
  fi
else
  log "ERROR: Redeploy script failed"
  exit 1
fi


