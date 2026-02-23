#!/bin/bash
# =============================================================================
# manager.sh — Runs ONLY on slurm-mgr
# By this point common.sh has already:
#   - installed MUNGE + key + started munged
#   - installed slurm.conf
#   - created slurm user/dirs
# This script adds: slurmctld, slurmdbd, MariaDB
# =============================================================================
set -euo pipefail

echo "================================================================"
echo " [MANAGER] Starting Slurm Manager setup on $(hostname)"
echo "================================================================"

# ── Manager-specific Slurm packages ───────────────────────────────────────────
echo "[MANAGER] Installing slurmctld + slurmdbd packages..."
dnf install -y slurm-slurmctld slurm-slurmdbd

# ── MariaDB ───────────────────────────────────────────────────────────────────
echo "[MANAGER] Installing MariaDB..."
dnf install -y mariadb-server mariadb

systemctl enable --now mariadb
sleep 3   # let MariaDB fully start

echo "[MANAGER] Configuring MariaDB for slurmdbd..."
mysql -u root <<'SQL'
CREATE DATABASE IF NOT EXISTS slurm_acct_db;
CREATE USER IF NOT EXISTS 'slurm'@'localhost' IDENTIFIED BY 'SlurmDBpass123!';
GRANT ALL PRIVILEGES ON slurm_acct_db.* TO 'slurm'@'localhost';
FLUSH PRIVILEGES;
SQL
echo "  ✓ MariaDB configured"

# ── slurmctld state directory ────────────────────────────────────────────────
mkdir -p /var/lib/slurmctld
chown slurm:slurm /var/lib/slurmctld
chmod 755 /var/lib/slurmctld

# ── Write slurmdbd.conf ───────────────────────────────────────────────────────
echo "[MANAGER] Writing /etc/slurm/slurmdbd.conf..."
cat > /etc/slurm/slurmdbd.conf <<'CONF'
# =============================================================================
# slurmdbd.conf — Manager node only
# =============================================================================
AuthType=auth/munge
DbdHost=slurm-mgr
DbdPort=6819

DebugLevel=info
LogFile=/var/log/slurm/slurmdbd.log
PidFile=/var/run/slurm/slurmdbd.pid

StorageType=accounting_storage/mysql
StorageHost=localhost
StoragePort=3306
StorageLoc=slurm_acct_db
StorageUser=slurm
StoragePass=SlurmDBpass123!

PurgeEventAfter=12months
PurgeJobAfter=12months
PurgeResvAfter=2months
PurgeStepAfter=2months
PurgeSuspendAfter=1month
PurgeTXNAfter=12months
PurgeUsageAfter=24months
CONF

chown slurm:slurm /etc/slurm/slurmdbd.conf
chmod 600 /etc/slurm/slurmdbd.conf   # contains DB password
echo "  ✓ slurmdbd.conf written"

# ── Start slurmdbd first, then slurmctld ──────────────────────────────────────
echo "[MANAGER] Starting slurmdbd..."
systemctl enable --now slurmdbd

echo "[MANAGER] Waiting for slurmdbd to init (15s)..."
sleep 15

echo "[MANAGER] Registering cluster in slurmdbd..."
sacctmgr -i add cluster vagrant-cluster || true

echo "[MANAGER] Starting slurmctld..."
systemctl enable --now slurmctld
sleep 3

echo ""
echo "================================================================"
echo " [MANAGER] Setup complete! Service status:"
echo "================================================================"
systemctl is-active munge     && echo "  ✓ munge     → active" || echo "  ✗ munge     → FAILED"
systemctl is-active mariadb   && echo "  ✓ mariadb   → active" || echo "  ✗ mariadb   → FAILED"
systemctl is-active slurmdbd  && echo "  ✓ slurmdbd  → active" || echo "  ✗ slurmdbd  → FAILED"
systemctl is-active slurmctld && echo "  ✓ slurmctld → active" || echo "  ✗ slurmctld → FAILED"
echo "================================================================"