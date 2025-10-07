## DS/CS553 – MLOps Case Study 2 Deliverables

**Team:** 10 (Solo)

**Student:** Ujjwal Pandit

**Date:** $(date)
### Operate and Recover

- Status:
```bash
ssh -i ~/.ssh/my_key -p 22010 student-admin@paffenroth-23.dyn.wpi.edu \
  'systemctl --user status --no-pager hugging_face_mood_app.service'
```

- Logs (live):
```bash
ssh -i ~/.ssh/my_key -p 22010 student-admin@paffenroth-23.dyn.wpi.edu \
  'journalctl --user -u hugging_face_mood_app.service -f'
```

- Restart:
```bash
ssh -i ~/.ssh/my_key -p 22010 student-admin@paffenroth-23.dyn.wpi.edu \
  'systemctl --user restart hugging_face_mood_app.service'
```

- Smoke test (local):
```bash
bash scripts/smoke_test.sh http://paffenroth-23.dyn.wpi.edu:8010/
```

- Guarded recovery (local):
```bash
HUGGING_FACE_TOKEN=<token> bash scripts/recover.sh
```

### Optional Cron Watchdog (conservative)

Add with `crontab -e` on your laptop. Runs every 10 minutes, with lock and cooldown to avoid loops:
```cron
*/10 * * * * HUGGING_FACE_TOKEN=<token> /bin/bash -lc '/home/ujjwal/mlops_assignment2/scripts/recover.sh'
```

Live app URL: `http://paffenroth-23.dyn.wpi.edu:8010/`


### 1. Virtual Machine Setup

- **SSH Access Setup (10 pts)**
  - Generated a personal ED25519 keypair on the local machine:
    - `ssh-keygen -f my_key -t ed25519`
  - Verified initial access using the provided shared key:
    - `ssh -i student-admin_key -p 22010 student-admin@paffenroth-23.dyn.wpi.edu`
  - Secured the VM: added `my_key.pub` to `~/.ssh/authorized_keys` and removed the shared key entry.
  - Verified exclusive access using the new key:
    - `ssh -i my_key -p 22010 student-admin@paffenroth-23.dyn.wpi.edu`

- **Environment Configuration (10 pts)**
  - Installed Git and Python venv on the VM.
  - Cloned the repo containing both products (API-based and local):
    - `git clone https://github.com/Madargaach-Holdings/hugging_face_mood_app.git`
  - Created and activated a virtual environment, installed dependencies:
    - `python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt`

These steps are automated by `deploy.sh` (see Section 3).

### 2. Deployment of Products on VMs

- **API-based Product (15 pts)**
  - Uses Hugging Face Inference API with token provided via environment variable `HUGGING_FACE_TOKEN`.
  - Runs as a Gradio app; accessible on the VM’s public interface.

- **Locally Executed Product (15 pts)**
  - Uses local model loading and caching on first run; subsequent runs use cached artifacts for speed.
  - Same entrypoint (`app.py`) supports both modes based on configuration.

### 3. Automated Deployment and Auto-Recovery

This repository includes `deploy.sh`, which:
1) Ensures SSH access is secured with your personal key.
2) Installs system dependencies, clones the app, and installs Python requirements.
3) Configures a user-level systemd service to run the app with auto-restart.

#### Prerequisites (local machine)
- Ensure your personal keys exist in this folder:
  - Private: `my_key`
  - Public: `my_key.pub`
- The original bootstrap key: `student-admin_key` (used only if the VM isn’t secured yet).
- Export your Hugging Face token locally (do not hardcode secrets):
  - `export HUGGING_FACE_TOKEN="hf_..."`

#### Run the deployment
```
bash /home/ujjwal/mlops_assignment2/deploy.sh
```

What the script does:
- Detects whether the VM already trusts your personal key; if not, it uses the student key once to add your public key and removes shared access.
- Installs `git` and `python3-venv`, clones the app, builds a virtual environment, and installs requirements.
- Writes an environment file on the VM at `~/.config/hugging_face_mood_app.env` with `HUGGING_FACE_TOKEN`.
- Creates a systemd user service at `~/.config/systemd/user/hugging_face_mood_app.service` and enables lingering for persistence.
- Starts the service and prints its short status.

#### Verify the deployment
- Service status on the VM:
  - `systemctl --user status hugging_face_mood_app.service`
- Follow logs:
  - `tail -f ~/hugging_face_mood_app/app.log`
- If using Gradio public URL, check the log for the external URL; otherwise, reach the VM’s IP/port if configured in the app.

#### Manage the service
- Restart:
  - `systemctl --user restart hugging_face_mood_app.service`
- Stop:
  - `systemctl --user stop hugging_face_mood_app.service`
- Enable on boot (already done by script):
  - `systemctl --user enable hugging_face_mood_app.service`

#### Auto-recovery behavior
- The service is configured with `Restart=always` and will start automatically after failures or reboots.
- The environment file is kept at `~/.config/hugging_face_mood_app.env` with mode `600`.

### 4. Notes and Security
- No tokens are committed or hardcoded. All secrets are passed via environment variables and stored on the VM in a user-only environment file.
- The shared class key is removed from `authorized_keys` to enforce exclusive access by the group.

### 5. Troubleshooting
- If the script reports missing `HUGGING_FACE_TOKEN`, export it locally and re-run.
- If `systemctl --user` fails due to no lingering, ensure lingering is enabled:
  - `sudo loginctl enable-linger student-admin`
- If the service crashes, check `app.log` for stack traces and verify the token is valid.
- If port exposure is required, confirm Gradio share configuration or VM firewall settings.


### Evidence

- Live URL: `http://paffenroth-23.dyn.wpi.edu:8010/`
- Service status excerpt:
```text
● hugging_face_mood_app.service - Hugging Face Mood App (Gradio)
     Loaded: loaded (/home/student-admin/.config/systemd/user/hugging_face_mood_app.service; enabled)
     Active: active (running)
   Main PID: <pid> (python3)
     CGroup: /user.slice/user-1002.slice/user@1002.service/app.slice/hugging_face_mood_app.service
             └─... /home/student-admin/hugging_face_mood_app/venv/bin/python3 app.py
```
- Smoke test (local):
```bash
$ bash scripts/smoke_test.sh http://paffenroth-23.dyn.wpi.edu:8010/
OK: http://paffenroth-23.dyn.wpi.edu:8010/ responded with HTTP 200
```
- Watchdog log sample:
```text
2025-10-07T16:03:36-0400 | Healthy: http://paffenroth-23.dyn.wpi.edu:8010/
```

### Rubric Map (Where to Find Evidence)

- SSH Access Setup (10 pts):
  - Steps: Section "1. Virtual Machine Setup"
  - Script: `deploy.sh` Part 1
  - Evidence: SSH commands and status in README; screenshots recommended
- Environment Configuration (10 pts):
  - Steps: Section "1. Virtual Machine Setup" → Environment Configuration
  - Script: `deploy.sh` Part 2
  - Evidence: system packages installed, venv + requirements
- Deployment of Products (2×15 pts):
  - Repo: `Madargaach-Holdings/hugging_face_mood_app` (both local and API modes)
  - Service: systemd unit in README; Evidence section and live URL
- Automated Deployment and Auto-Recovery (20+ pts):
  - Scripts: `deploy.sh`, `scripts/recover.sh`, `scripts/smoke_test.sh`
  - Service config: systemd user service, lingering enabled
  - Evidence: watchdog log sample, smoke test OK
- Operations Runbook / Monitoring:
  - Section "Operate and Recover" with status, logs, restart, cron

### Limitations and Future Work

- Parameterize VM host/port/user via env to support multiple teams with one script.
- Add Slack/Telegram alerts in `recover.sh` on failure or redeploy.
- Add GitHub Actions to lint shell scripts and verify smoke test on push.





