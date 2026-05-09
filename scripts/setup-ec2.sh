#!/bin/bash
# ============================================================
# setup-ec2.sh — One-time provisioning script for the EC2 host.
#
# Run this ONCE after first launching the EC2 instance.
# After this, GitHub Actions can SSH in and do `docker compose pull`
# without hitting GHCR authentication errors.
#
# Usage:
#   ssh -i ec2-key.pem ubuntu@<EC2_IP> "bash -s" < scripts/setup-ec2.sh
#
# Prerequisites:
#   - EC2 instance running Ubuntu 22.04+
#   - Your GHCR_PAT (GitHub Personal Access Token with read:packages scope)
#   - Set GHCR_PAT and GITHUB_USERNAME before running this script
# ============================================================
set -euo pipefail

GITHUB_USERNAME="${GITHUB_USERNAME:-satyam-prakash}"
GHCR_PAT="${GHCR_PAT:?ERROR: Set GHCR_PAT env var to your GitHub PAT with read:packages scope}"
APP_DIR="/opt/pr-tracker"

echo "=== [1/6] Installing Docker & Docker Compose ==="
apt-get update -q
apt-get install -y -q ca-certificates curl gnupg lsb-release

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -q
apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-compose-plugin

echo "=== [2/6] Adding ubuntu to docker group ==="
usermod -aG docker ubuntu

echo "=== [3/6] Authenticating Docker to GHCR ==="
echo "${GHCR_PAT}" | docker login ghcr.io \
  --username "${GITHUB_USERNAME}" \
  --password-stdin

echo "=== [4/6] Creating app directory ==="
mkdir -p "${APP_DIR}"
chown ubuntu:ubuntu "${APP_DIR}"

echo "=== [5/6] Cloning repo (if not already present) ==="
if [ ! -d "${APP_DIR}/.git" ]; then
  git clone https://github.com/${GITHUB_USERNAME}/pr-tracker.git "${APP_DIR}"
fi

echo "=== [6/6] Copying .env to app directory ==="
# You must manually scp your .env to the EC2 instance BEFORE running this script:
#   scp -i ec2-key.pem .env ubuntu@<EC2_IP>:/opt/pr-tracker/.env
if [ -f "${APP_DIR}/.env" ]; then
  echo ".env found — OK"
else
  echo "WARNING: .env not found at ${APP_DIR}/.env"
  echo "  Run: scp -i ec2-key.pem .env ubuntu@<EC2_IP>:${APP_DIR}/.env"
fi

echo ""
echo "==================================================================="
echo " EC2 setup complete!"
echo " Next steps:"
echo "   1. scp -i ec2-key.pem .env ubuntu@<EC2_IP>:${APP_DIR}/.env"
echo "   2. cd ${APP_DIR} && docker compose up -d"
echo "   3. Add these GitHub Secrets in your repo settings:"
echo "      VPS_HOST    = <EC2 public IP>"
echo "      VPS_USER    = ubuntu"
echo "      VPS_SSH_KEY = <contents of ec2-key.pem>"
echo "      CLIENT_URL  = http://<EC2 public IP>"
echo "==================================================================="
