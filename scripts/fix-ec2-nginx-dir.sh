#!/bin/bash
# ============================================================
# fix-ec2-nginx-dir.sh — Run this ONE TIME on EC2 to fix the
# "mounting file onto directory" Docker error.
#
# Usage:
#   ssh -i ec2-key.pem ubuntu@13.200.251.30 "bash -s" < scripts/fix-ec2-nginx-dir.sh
# ============================================================
set -e

APP_DIR="/opt/pr-tracker"
cd "$APP_DIR"

echo "=== [1] Stopping all containers ==="
docker compose down

echo "=== [2] Pulling latest code from git ==="
git fetch origin main
git reset --hard origin/main

echo "=== [3] Checking for Docker-created directories at file-mount paths ==="
for path in nginx/nginx.conf; do
  if [ -d "$path" ]; then
    echo "  FIXING: $path is a directory — removing..."
    rm -rf "$path"
    echo "  DONE: $path removed, git will restore the file"
  else
    echo "  OK: $path is a file (or doesn't exist yet)"
  fi
done

echo "=== [4] Verifying nginx/nginx.conf is now a file ==="
ls -la nginx/nginx.conf

echo "=== [5] Restarting all containers ==="
docker compose up -d

echo "=== [6] Container status ==="
docker compose ps

echo ""
echo "=== Fix complete! ==="
