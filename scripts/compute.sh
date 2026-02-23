#!/bin/bash
# =============================================================================
# compute.sh — Runs on compute-01 and compute-02
# By this point common.sh has already:
#   - installed MUNGE + key + started munged
#   - installed slurm.conf
#   - created slurm user/dirs
# This script just adds slurmd and starts it
# =============================================================================
set -euo pipefail

echo "================================================================"
echo " [COMPUTE] Starting Slurm Compute setup on $(hostname)"
echo "================================================================"

# ── Install slurmd ────────────────────────────────────────────────────────────
echo "[COMPUTE] Installing slurmd..."
dnf install -y slurm-slurmd

# ── Spool dir for this node ───────────────────────────────────────────────────
mkdir -p /var/spool/slurmd
chown slurm:slurm /var/spool/slurmd
chmod 755 /var/spool/slurmd

# ── Start slurmd ──────────────────────────────────────────────────────────────
echo "[COMPUTE] Starting slurmd..."
systemctl enable --now slurmd
sleep 3

echo ""
echo "================================================================"
echo " [COMPUTE] Setup complete on $(hostname)! Service status:"
echo "================================================================"
systemctl is-active munge  && echo "  ✓ munge  → active" || echo "  ✗ munge  → FAILED"
systemctl is-active slurmd && echo "  ✓ slurmd → active" || echo "  ✗ slurmd → FAILED"
echo "================================================================"