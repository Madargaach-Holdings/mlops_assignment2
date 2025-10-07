## Case Study 2: End-to-End Deployment and Auto-Recovery Guide (Step-by-Step)

This tutorial walks you through everything required to complete CS2 on the provided VM, from SSH setup to deployment with auto-recovery via systemd. Follow the steps in order. All commands are provided explicitly.

Assumptions:
- Local machine: Linux/macOS terminal with `ssh`, `ssh-keygen`, and `bash`.
- VM login: `student-admin@paffenroth-23.dyn.wpi.edu` with port `22010` (replace if your assignment differs).
- Your repository folder on local machine is at `/home/ujjwal/mlops_assignment2` (adjust paths if different).

Important files (on your local machine):
- `/home/ujjwal/mlops_assignment2/student-admin_key` (provided bootstrap key to access the VM initially)
- `/home/ujjwal/mlops_assignment2/my_key` and `my_key.pub` (your personal keypair)
- `/home/ujjwal/mlops_assignment2/deploy.sh` (automated deployment script)

---

### 0) Prepare your local environment

1. Open a terminal and change to your repo folder:
```
cd /home/ujjwal/mlops_assignment2
```

2. Ensure keys have safe permissions (private keys should be owner-read only):
```
chmod 400 /home/ujjwal/mlops_assignment2/student-admin_key || true
chmod 400 /home/ujjwal/mlops_assignment2/my_key || true
```

3. If you do NOT already have a personal keypair, create one now (skip if already created):
```
ssh-keygen -f /home/ujjwal/mlops_assignment2/my_key -t ed25519
```

---

### 1) First login using the shared (bootstrap) key

1. Attempt to connect using the shared key:
```
ssh -i /home/ujjwal/mlops_assignment2/student-admin_key -p 22010 student-admin@paffenroth-23.dyn.wpi.edu
```

2. If you are prompted to trust the host, type `yes`.
3. If you see a shell prompt like `student-admin@groupXX:~$`, you are in. If the connection is refused, wait a minute and retry.

---

### 2) Secure the VM with your own key

You have two options. Option A is automatic via the deploy script. Option B is manual (good to understand what happens).

#### Option A (automatic via script) – recommended
The script will use the shared key once (if needed) to add your public key and remove the shared key.

1. On your local machine, export your Hugging Face token (needed later to run the app):
```
export HUGGING_FACE_TOKEN="hf_..."
```

2. Run the deploy script (it will handle key transfer if required):
```
bash /home/ujjwal/mlops_assignment2/deploy.sh
```

3. If the VM was already secured with your personal key, the script will skip the transfer. Otherwise it will add your public key and remove the shared one, then proceed.

#### Option B (manual steps)

1. On your local machine, show your public key:
```
cat /home/ujjwal/mlops_assignment2/my_key.pub
```

2. Copy the full line. On the VM (logged in using the shared key):
```
mkdir -p ~/.ssh
chmod 700 ~/.ssh
nano ~/.ssh/authorized_keys
```
Paste your public key on a new line, save, and exit.

3. Remove the shared (class) key line(s) from the same `authorized_keys` file to ensure only your group has access.

4. Reconnect using your personal key (from local machine):
```
ssh -i /home/ujjwal/mlops_assignment2/my_key -p 22010 student-admin@paffenroth-23.dyn.wpi.edu
```

---

### 3) Environment setup (automated by the script)

The script performs the following on the VM:
- `sudo apt update`
- `sudo apt install git python3-venv -y`
- `git clone https://github.com/Madargaach-Holdings/hugging_face_mood_app.git`
- `python3 -m venv venv && source venv/bin/activate`
- `pip install -r requirements.txt`

If you prefer manual steps on the VM:
```
sudo apt update
sudo apt install git python3-venv -y
rm -rf ~/hugging_face_mood_app
git clone https://github.com/Madargaach-Holdings/hugging_face_mood_app.git
cd ~/hugging_face_mood_app
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

---

### 4) Configure and start the app as a systemd user service (auto-recovery)

This is automatic if you used `deploy.sh`. For manual setup on the VM:

1. Create an environment file with the token (on the VM):
```
mkdir -p ~/.config
umask 177
printf 'HUGGING_FACE_TOKEN=%s\n' "${HUGGING_FACE_TOKEN}" > ~/.config/hugging_face_mood_app.env
chmod 600 ~/.config/hugging_face_mood_app.env
```

2. Create the systemd user unit file (on the VM):
```
mkdir -p ~/.config/systemd/user
nano ~/.config/systemd/user/hugging_face_mood_app.service
```
Paste the following, then save:
```
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
```

3. Enable lingering so user services persist after logout (on the VM):
```
sudo loginctl enable-linger student-admin
```

4. Start and enable the service (on the VM):
```
systemctl --user daemon-reload
systemctl --user enable --now hugging_face_mood_app.service
systemctl --user status --no-pager --full hugging_face_mood_app.service
```

5. Watch logs:
```
tail -f ~/hugging_face_mood_app/app.log
```

Notes:
- The service will automatically restart on crashes or reboots.
- Logs are written to `~/hugging_face_mood_app/app.log`.

---

### 5) Running locally vs. API mode

- The same `app.py` supports both modes. Ensure `HUGGING_FACE_TOKEN` is set for API-based usage.
- For local model execution, `app.py` will download and cache the model on first run.

Manual run example (on the VM):
```
cd ~/hugging_face_mood_app
source venv/bin/activate
export HUGGING_FACE_TOKEN="hf_..."   # required for API-based mode
python3 app.py
```

---

### 6) Verification checklist

After running `deploy.sh` or completing manual steps:
1. Confirm service is active:
```
systemctl --user status hugging_face_mood_app.service
```
2. Check logs for errors and for the Gradio URL (if it generates a public share URL):
```
tail -n 200 ~/hugging_face_mood_app/app.log
```
3. If the app serves on a local port, confirm firewall rules or reverse proxy as required by your environment.

---

### 7) Daily operations

- Restart the service after code/config changes:
```
systemctl --user restart hugging_face_mood_app.service
```

- Stop the service:
```
systemctl --user stop hugging_face_mood_app.service
```

- View logs live:
```
tail -f ~/hugging_face_mood_app/app.log
```

- Update the application to the latest commit (on the VM):
```
cd ~/hugging_face_mood_app
git pull --rebase
source venv/bin/activate
pip install -r requirements.txt
systemctl --user restart hugging_face_mood_app.service
```

---

### 8) Rotating or fixing your token

If your Hugging Face token changes, update the VM’s env file and restart:
```
printf 'HUGGING_FACE_TOKEN=%s\n' "hf_new_token" > ~/.config/hugging_face_mood_app.env
chmod 600 ~/.config/hugging_face_mood_app.env
systemctl --user restart hugging_face_mood_app.service
```

If using `deploy.sh` again from local, set the new token first:
```
export HUGGING_FACE_TOKEN="hf_new_token"
bash /home/ujjwal/mlops_assignment2/deploy.sh
```

---

### 9) Troubleshooting

- Missing token when running the script from local:
```
export HUGGING_FACE_TOKEN="hf_..."
bash /home/ujjwal/mlops_assignment2/deploy.sh
```

- Service fails to start (on VM):
```
systemctl --user status hugging_face_mood_app.service
tail -n 200 ~/hugging_face_mood_app/app.log
```

- Lingering not enabled error:
```
sudo loginctl enable-linger student-admin
systemctl --user daemon-reload
systemctl --user restart hugging_face_mood_app.service
```

- Port/Network access issues:
  - Check whether Gradio is generating a public share URL in logs.
  - If serving a local port, ensure firewall allows access or use SSH tunneling.

---

### 10) Deliverables mapping (what to include in your write-up)

- 1a. SSH Access Setup
  - Commands used to connect with shared key, generate personal key, and update `authorized_keys`.
  - Confirmation of login using your personal key.

- 1b. Environment Configuration
  - `git clone`, `python3 -m venv`, `pip install -r requirements.txt` (or `deploy.sh` output).

- 2a. API-based Product Deployment
  - `HUGGING_FACE_TOKEN` usage; Gradio accessibility; logs/screenshots.

- 2b. Locally Executed Product Deployment
  - First-run local model download; subsequent cached runs; accessibility confirmation.

Include screenshots of successful connection, service status, and the running UI/logs as evidence.

---

### 11) One-command deployment summary

On your local machine (recommended path):
```
export HUGGING_FACE_TOKEN="hf_..."
bash /home/ujjwal/mlops_assignment2/deploy.sh
```

Then verify on the VM:
```
systemctl --user status hugging_face_mood_app.service
tail -f ~/hugging_face_mood_app/app.log
```




