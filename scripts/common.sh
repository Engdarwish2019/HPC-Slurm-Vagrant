#!/bin/bash
# =============================================================================
# common.sh — Runs on ALL nodes (manager + computes)
# Pre-requisite: setup.sh was run on the HOST first (generates configs/)
# Vagrant rsync delivers configs/munge.key + configs/slurm.conf to /vagrant/configs/
# =============================================================================
set -euo pipefail

echo "================================================================"
echo " [COMMON] Starting on $(hostname)"
echo "================================================================"

# ── /etc/hosts — cluster-wide name resolution ─────────────────────────────────
echo "[COMMON] Setting up /etc/hosts..."
cat >> /etc/hosts <<'EOF'

# Slurm Cluster
192.168.50.10  slurm-mgr
192.168.50.11  compute-01
192.168.50.12  compute-02
EOF

# ── SELinux → permissive ──────────────────────────────────────────────────────
echo "[COMMON] Setting SELinux to permissive..."
setenforce 0 || true
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

# ── Firewall — open Slurm ports ───────────────────────────────────────────────
echo "[COMMON] Configuring firewall..."
systemctl enable --now firewalld
firewall-cmd --permanent --add-port=6817/tcp   # slurmctld
firewall-cmd --permanent --add-port=6818/tcp   # slurmd
firewall-cmd --permanent --add-port=6819/tcp   # slurmdbd
firewall-cmd --reload

# ── EPEL + CRB ────────────────────────────────────────────────────────────────
echo "[COMMON] Installing EPEL..."
dnf install -y epel-release
dnf config-manager --set-enabled crb

# ── System update ─────────────────────────────────────────────────────────────
echo "[COMMON] Updating system..."
dnf update -y

# ── MUNGE ─────────────────────────────────────────────────────────────────────
echo "[COMMON] Installing MUNGE..."
dnf install -y munge munge-libs munge-devel

# ── Install MUNGE key from /vagrant/configs/ (rsynced from host) ─────────────
echo "[COMMON] Installing MUNGE key from /vagrant/configs/munge.key..."
if [ ! -f /vagrant/configs/munge.key ]; then
  echo "ERROR: /vagrant/configs/munge.key not found!"
  echo "       Did you run ./setup.sh on the host before vagrant up?"
  exit 1
fi

mkdir -p /etc/munge
chmod 700 /etc/munge
cp /vagrant/configs/munge.key /etc/munge/munge.key
chown munge:munge /etc/munge/munge.key
chmod 400 /etc/munge/munge.key
echo "  ✓ MUNGE key installed"

# ── Start MUNGE ───────────────────────────────────────────────────────────────
echo "[COMMON] Starting MUNGE..."
systemctl enable --now munge

# ── Slurm base package ────────────────────────────────────────────────────────
echo "[COMMON] Installing Slurm base..."
dnf install -y slurm slurm-libs

# ── Create slurm user/group — MUST be identical UID/GID on all nodes ─────────
echo "[COMMON] Creating slurm system user (UID 992, GID 992)..."
if ! getent group slurm &>/dev/null; then
  groupadd -g 992 slurm
fi
if ! getent passwd slurm &>/dev/null; then
  useradd -m -c "Slurm Workload Manager" -d /var/lib/slurm \
          -u 992 -g slurm -s /sbin/nologin slurm
fi

# ── Slurm directories ─────────────────────────────────────────────────────────
echo "[COMMON] Creating Slurm directories..."
mkdir -p /etc/slurm
mkdir -p /var/log/slurm
mkdir -p /var/spool/slurm
mkdir -p /var/run/slurm

chown slurm:slurm /var/log/slurm /var/spool/slurm /var/run/slurm
chmod 755         /var/log/slurm /var/spool/slurm /var/run/slurm

# ── Install slurm.conf from /vagrant/configs/ ────────────────────────────────
echo "[COMMON] Installing slurm.conf from /vagrant/configs/slurm.conf..."
if [ ! -f /vagrant/configs/slurm.conf ]; then
  echo "ERROR: /vagrant/configs/slurm.conf not found!"
  exit 1
fi
cp /vagrant/configs/slurm.conf /etc/slurm/slurm.conf
chown slurm:slurm /etc/slurm/slurm.conf
chmod 644 /etc/slurm/slurm.conf
echo "  ✓ slurm.conf installed"

echo "[COMMON] Done on $(hostname) ✓"