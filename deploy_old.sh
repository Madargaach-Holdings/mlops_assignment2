#!/bin/bash

# --- VARIABLES ---
# The path to your personal public SSH key (used to secure the VM)
PUB_KEY_PATH="/home/ujjwal/GitHub_Edits/mlops_assignment2/my_key.pub"

# The path to your personal private SSH key (used for all future connections)
PRI_KEY_PATH="/home/ujjwal/GitHub_Edits/mlops_assignment2/my_key"

# >>> ADDED THIS LINE FOR THE STUDENT KEY'S PATH <<<
STUDENT_KEY_PATH="/home/ujjwal/GitHub_Edits/mlops_assignment2/student-admin_key"

# The path to your project's GitHub repository
REPO_URL="https://github.com/Madargaach-Holdings/hugging_face_mood_app.git"

# The remote user and VM host
REMOTE_USER="student-admin"
REMOTE_HOST="paffenroth-23.dyn.wpi.edu"
REMOTE_PORT="22010"

# --- DEPLOYMENT SCRIPT ---
echo "--- Starting Automated Deployment ---"

# Validate required local environment variables (do NOT hardcode secrets)
if [ -z "${HUGGING_FACE_TOKEN}" ]; then
    echo "ERROR: HUGGING_FACE_TOKEN is not set in your local environment."
    echo "Export it locally, e.g.: export HUGGING_FACE_TOKEN=\"hf_xxx\""
    exit 1
fi

# Check if the VM is already secured with our key.
# This checks if our private key works without any prompts.
ssh -i ${PRI_KEY_PATH} -o BatchMode=yes -o ConnectTimeout=5 -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} "exit"

# $? holds the exit code of the last command. 0 means success.
if [ $? -eq 0 ]; then
    # Scenario 1: VM is already secured.
    echo "✅ VM is already secured. Skipping key transfer."
    KEY_TO_USE=${PRI_KEY_PATH}
else
    # Scenario 2: VM is wiped or not yet secured.
    echo "⚠️ VM is not secured. Initiating key transfer..."
    KEY_TO_USE=${STUDENT_KEY_PATH}

    # Step 1: Secure the VM by adding your personal public key.
    # We use the student key to do the initial key transfer.
    cat ${PUB_KEY_PATH} | ssh -i ${KEY_TO_USE} -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} \
        "mkdir -p ~/.ssh && \
        chmod 700 ~/.ssh && \
        echo '`cat -`' >> ~/.ssh/authorized_keys && \
        sed -i '/student-admin/d' ~/.ssh/authorized_keys"

    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to update authorized_keys. Exiting."
        exit 1
    fi
    echo "✅ SSH key updated successfully."
    # After the key is transferred, we switch to our personal key for the rest of the script.
    KEY_TO_USE=${PRI_KEY_PATH}
fi

# Check if service is running and stop it first
echo "Checking if application is already running..."
ssh -i ${KEY_TO_USE} -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} \
    "systemctl --user stop hugging_face_mood_app.service 2>/dev/null || true && \
     sleep 2"

# Step 2: Connect via the correct key and install dependencies.
# This step is executed regardless of the initial security state.
echo "2. Installing required system dependencies and cloning repository..."
ssh -i ${KEY_TO_USE} -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} \
    "sudo apt update && \
    sudo apt install git python3-venv -y && \
    rm -rf ~/hugging_face_mood_app && \
    git clone ${REPO_URL} && \
    cd ~/hugging_face_mood_app && \
    python3 -m venv venv && \
    ./venv/bin/pip install -r requirements.txt"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to clone and install dependencies. Exiting."
    exit 1
fi
echo "✅ Environment configured and project cloned successfully."

# Step 3: Configure systemd user service for auto-recovery and start it.
echo "3. Configuring systemd user service for auto-recovery..."

# Create environment file on remote with the token (mode 600)
# FIXED: Using HF_TOKEN instead of HUGGING_FACE_TOKEN since that's what app.py expects
ssh -i ${KEY_TO_USE} -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} \
    "mkdir -p ~/.config && \
    umask 177 && \
    echo 'HF_TOKEN=${HUGGING_FACE_TOKEN}' > ~/.config/hugging_face_mood_app.env && \
    chmod 600 ~/.config/hugging_face_mood_app.env"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create environment file on the VM."
    exit 1
fi

# Create systemd user service unit
ssh -i ${KEY_TO_USE} -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} \
    "mkdir -p ~/.config/systemd/user && \
    cat > ~/.config/systemd/user/hugging_face_mood_app.service << 'UNIT' && \
    true
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
    echo "ERROR: Failed to create systemd service on the VM."
    exit 1
fi

# Enable lingering so user services keep running after logout
ssh -i ${KEY_TO_USE} -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} \
    "sudo loginctl enable-linger ${REMOTE_USER} || true"

# Reload systemd user units, enable, and start the service
ssh -i ${KEY_TO_USE} -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} \
    "systemctl --user daemon-reload && \
     systemctl --user enable --now hugging_face_mood_app.service && \
     systemctl --user status --no-pager --full hugging_face_mood_app.service | sed -n '1,50p'"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to start the systemd service."
    exit 1
fi
echo "✅ Systemd service installed and started. Auto-recovery is enabled."
echo "--- Deployment Complete ---"