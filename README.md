# MLOps Assignment 2 - Automated Deployment & Recovery

**Team 10 (Solo):** Ujjwal Pandit

## Overview

Automated deployment and recovery system for a dual-mode Gradio application (local model + Hugging Face API) with health monitoring and self-healing capabilities.

## Quick Start

```bash
# Deploy to VM
HUGGING_FACE_TOKEN=<token> make deploy

# Check application health
make smoke

# View service status
make status

# View logs
make logs

# Restart service
make restart

# Run recovery (if needed)
make recover
```

## Architecture

- **Deployment:** `deploy.sh` - Idempotent script that secures SSH access, installs dependencies, and configures systemd service
- **Health Monitoring:** `scripts/smoke_test.sh` - HTTP health check
- **Recovery:** `scripts/recover.sh` - Guarded recovery with lock/cooldown to prevent loops
- **Operations:** `Makefile` - Convenient targets for common tasks

## Live Application

- **URL:** http://paffenroth-23.dyn.wpi.edu:8010/
- **Service:** systemd user service with auto-restart
- **Monitoring:** Optional cron watchdog (every 10 minutes)

## Documentation

See `Case Study 2_Report.pdf` for complete documentation including:
- Setup process and SSH key management
- Deployment automation and resilience testing
- Monitoring and recovery mechanisms
- Lessons learned and future improvements

## Files

- `deploy.sh` - Main deployment script
- `scripts/smoke_test.sh` - Health check utility
- `scripts/recover.sh` - Recovery automation
- `Makefile` - Operations convenience targets
- `Case Study 2_Report.pdf` - Complete project documentation
