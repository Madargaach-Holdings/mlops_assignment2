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


