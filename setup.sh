#!/bin/bash
# =============================================================================
# setup.sh — Run ONCE on the HOST (Fedora) before `vagrant up`
# Generates: configs/munge.key + configs/slurm.conf
# =============================================================================
set -euo pipefail

echo "=== Slurm Cluster — Host Setup ==="

# ── Install munge on host if not present ─────────────────────────────────────
if ! rpm -q munge &>/dev/null; then
  echo "[setup] Installing munge..."
  sudo dnf install -y munge
fi

# ── Generate munge key ────────────────────────────────────────────────────────
# Official method per dun/munge Installation Guide:
#   newer versions: mungekey -c -f -k <path>
#   older versions: create-munge-key (deprecated, removed in newer distros)
#   universal fallback: dd from /dev/urandom (works everywhere)
echo "[setup] Generating MUNGE key → configs/munge.key"
mkdir -p configs

sudo mkdir -p /etc/munge
sudo chmod 700 /etc/munge

if command -v mungekey &>/dev/null; then
  echo "  → using mungekey (modern MUNGE)"
  sudo mungekey -c -f -k /etc/munge/munge.key
elif command -v create-munge-key &>/dev/null; then
  echo "  → using create-munge-key (legacy)"
  sudo create-munge-key -f
else
  echo "  → using dd /dev/urandom fallback"
  sudo dd if=/dev/urandom bs=1 count=1024 > /tmp/munge.key.tmp
  sudo mv /tmp/munge.key.tmp /etc/munge/munge.key
fi

sudo chown munge:munge /etc/munge/munge.key
sudo chmod 400 /etc/munge/munge.key

# Copy to configs/ for Vagrant rsync
sudo cp /etc/munge/munge.key configs/munge.key
sudo chown "$USER:$USER" configs/munge.key
chmod 600 configs/munge.key
echo "  ✓ configs/munge.key created ($(wc -c < configs/munge.key) bytes)"

# ── Write slurm.conf ──────────────────────────────────────────────────────────
echo "[setup] Writing configs/slurm.conf..."
cat > configs/slurm.conf <<'CONF'
# =============================================================================
# slurm.conf — Shared across ALL nodes (manager + computes)
# =============================================================================

ClusterName=vagrant-cluster
SlurmctldHost=slurm-mgr

AuthType=auth/munge
SlurmUser=slurm

SlurmctldPort=6817
SlurmdPort=6818

SlurmctldPidFile=/var/run/slurm/slurmctld.pid
SlurmdPidFile=/var/run/slurm/slurmd.pid

StateSaveLocation=/var/lib/slurmctld
SlurmdSpoolDir=/var/spool/slurmd

SlurmctldLogFile=/var/log/slurm/slurmctld.log
SlurmdLogFile=/var/log/slurm/slurmd.log
SlurmctldDebug=info
SlurmdDebug=info

# linuxproc: no cgroup config needed — best for VM/lab environments
ProctrackType=proctrack/linuxproc
TaskPlugin=task/none

SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_Core

AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost=slurm-mgr
AccountingStoragePort=6819
JobAcctGatherType=jobacct_gather/linux
JobAcctGatherFrequency=30

SlurmctldTimeout=120
SlurmdTimeout=300
InactiveLimit=0
MinJobAge=300
KillWait=30
Waittime=0
ReturnToService=1

MpiDefault=none

# =============================================================================
# COMPUTE NODES — CPUs must match lv.cpus in Vagrantfile (2)
#                 RealMemory = lv.memory minus OS overhead (~100MB)
# =============================================================================
NodeName=compute-01 NodeAddr=192.168.50.11 CPUs=2 RealMemory=900  State=UNKNOWN
NodeName=compute-02 NodeAddr=192.168.50.12 CPUs=2 RealMemory=900  State=UNKNOWN

PartitionName=compute Nodes=compute-01,compute-02 Default=YES MaxTime=INFINITE State=UP
CONF

echo "  ✓ configs/slurm.conf created"

echo ""
echo "=== Setup complete! ==="
echo ""
echo "  configs/munge.key   ✓"
echo "  configs/slurm.conf  ✓"
echo ""
echo "Now run:"
echo "  vagrant up slurm-mgr"
echo "  vagrant up compute-01 compute-02"
echo ""