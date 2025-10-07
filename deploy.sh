#!/bin/bash

# Part 1: Secure VM SSH access with a personal key, falling back to shared key once

# --- CONFIG ---
REMOTE_USER="student-admin"
REMOTE_HOST="paffenroth-23.dyn.wpi.edu"
REMOTE_PORT="22010"

# Use keys from ~/.ssh
PRI_KEY_PATH="/home/ujjwal/.ssh/my_key"          # your personal private key
PUB_KEY_PATH="/home/ujjwal/.ssh/my_key.pub"      # your personal public key
STUDENT_KEY_PATH="/home/ujjwal/.ssh/student-admin_key"  # shared bootstrap key

echo "--- Part 1: SSH setup ---"

# Validate key files exist locally
for f in "${PRI_KEY_PATH}" "${PUB_KEY_PATH}" "${STUDENT_KEY_PATH}"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: Missing key file: $f"
        exit 1
    fi
done

# Ensure strict permissions on private keys
chmod 600 "${PRI_KEY_PATH}" 2>/dev/null || true
chmod 600 "${STUDENT_KEY_PATH}" 2>/dev/null || true

# 1) Check if VM already accepts our personal key
ssh -i "${PRI_KEY_PATH}" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -p "${REMOTE_PORT}" "${REMOTE_USER}@${REMOTE_HOST}" exit

if [ $? -eq 0 ]; then
    echo "✅ Personal key already works. No changes needed."
    KEY_TO_USE="${PRI_KEY_PATH}"
else
    echo "⚠️ Personal key not yet installed. Using shared key to install it..."
    KEY_TO_USE="${STUDENT_KEY_PATH}"

    # Append personal pub key and remove any student-admin entries idempotently
    ssh -i "${KEY_TO_USE}" -p "${REMOTE_PORT}" "${REMOTE_USER}@${REMOTE_HOST}" \
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && grep -qxF \"$(cat \"${PUB_KEY_PATH}\")\" ~/.ssh/authorized_keys || echo \"$(cat \"${PUB_KEY_PATH}\")\" >> ~/.ssh/authorized_keys && sed -i '/student-admin/d' ~/.ssh/authorized_keys"

    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to update authorized_keys on VM."
        exit 1
    fi

    echo "✅ Installed personal key and removed shared key from authorized_keys."

    # Re-check with personal key
    ssh -i "${PRI_KEY_PATH}" -o BatchMode=yes -o ConnectTimeout=5 -p "${REMOTE_PORT}" "${REMOTE_USER}@${REMOTE_HOST}" exit
    if [ $? -ne 0 ]; then
        echo "ERROR: Personal key still not accepted after install."
        exit 1
    fi
    KEY_TO_USE="${PRI_KEY_PATH}"
fi

echo "Verifying login and recording host key..."
ssh -i "${KEY_TO_USE}" -o StrictHostKeyChecking=accept-new -p "${REMOTE_PORT}" "${REMOTE_USER}@${REMOTE_HOST}" "echo 'Successfully logged in with personal key.'"

if [ $? -ne 0 ]; then
    echo "ERROR: Verification login failed."
    exit 1
fi

echo "--- Part 1 complete. You can proceed to the next step. ---"



echo "--- Part 2: Environment setup and deployment ---"

# Required: HF token must be exported locally before running
if [ -z "${HUGGING_FACE_TOKEN}" ]; then
    echo "ERROR: HUGGING_FACE_TOKEN is not set. Export it before running."
    echo "Example: export HUGGING_FACE_TOKEN=hf_xxx"
    exit 1
fi

REPO_URL="https://github.com/Madargaach-Holdings/hugging_face_mood_app.git"
PROJECT_DIR="hugging_face_mood_app"

# Stop any existing service (ignore errors)
ssh -i "${KEY_TO_USE}" -p "${REMOTE_PORT}" "${REMOTE_USER}@${REMOTE_HOST}" \
    "systemctl --user stop hugging_face_mood_app.service 2>/dev/null || true"

# Install base deps, clone fresh, create venv, install requirements
ssh -i "${KEY_TO_USE}" -p "${REMOTE_PORT}" "${REMOTE_USER}@${REMOTE_HOST}" \
    "sudo apt update && sudo apt install -y git python3-venv && \
     rm -rf ~/${PROJECT_DIR} && \
     git clone ${REPO_URL} && \
     cd ~/${PROJECT_DIR} && \
     python3 -m venv venv && \
     ./venv/bin/pip install --upgrade pip && \
     ./venv/bin/pip install -r requirements.txt"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to prepare Python environment on VM."
    exit 1
fi

# Create env file with token
ssh -i "${KEY_TO_USE}" -p "${REMOTE_PORT}" "${REMOTE_USER}@${REMOTE_HOST}" \
    "mkdir -p ~/.config && umask 177 && \
     echo 'HF_TOKEN=${HUGGING_FACE_TOKEN}' > ~/.config/hugging_face_mood_app.env && \
     chmod 600 ~/.config/hugging_face_mood_app.env"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create env file on VM."
    exit 1
fi

# Create/refresh systemd user service
ssh -i "${KEY_TO_USE}" -p "${REMOTE_PORT}" "${REMOTE_USER}@${REMOTE_HOST}" \
    "mkdir -p ~/.config/systemd/user && \
     cat > ~/.config/systemd/user/hugging_face_mood_app.service << 'UNIT'
[Unit]
Description=Hugging Face Mood App (Gradio)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=%h/hugging_face_mood_app
EnvironmentFile=%h/.config/hugging_face_mood_app.env
ExecStart=%h/hugging_face_mood_app/venv/bin/python3 app.py
Restart=always
RestartSec=5
StandardOutput=append:%h/hugging_face_mood_app/app.log
StandardError=append:%h/hugging_face_mood_app/app.log

[Install]
WantedBy=default.target
UNIT"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to install systemd service on VM."
    exit 1
fi

# Ensure lingering enabled, then reload and start service
ssh -i "${KEY_TO_USE}" -p "${REMOTE_PORT}" "${REMOTE_USER}@${REMOTE_HOST}" \
    "sudo loginctl enable-linger ${REMOTE_USER} || true && \
     systemctl --user daemon-reload && \
     systemctl --user enable --now hugging_face_mood_app.service && \
     systemctl --user status --no-pager --full hugging_face_mood_app.service | sed -n '1,50p'"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to start the service."
    exit 1
fi

echo "--- Part 2 complete. Service deployed and managed by systemd. ---"
