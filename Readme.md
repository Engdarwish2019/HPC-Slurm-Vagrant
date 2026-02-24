# Slurm Cluster — Vagrant + KVM (Fedora Host)

A fully automated 3-node Slurm HPC cluster using Vagrant + KVM/libvirt on Fedora,
with slurmdbd accounting backed by MariaDB and MUNGE authentication.

## Official Documentation

| Component | Docs |
|---|---|
| Slurm Quick Start (Admin) | https://slurm.schedmd.com/quickstart_admin.html |
| Slurm Configuration Tool | https://slurm.schedmd.com/configurator.html |
| MUNGE Installation Guide | https://github.com/dun/munge/wiki/Installation-Guide |
| vagrant-libvirt Configuration | https://vagrant-libvirt.github.io/vagrant-libvirt/configuration.html |
| vagrant-libvirt Networking | https://vagrant-libvirt.github.io/vagrant-libvirt/configuration.html#networks |
| EPEL 9 Slurm Packages | https://packages.fedoraproject.org/pkgs/slurm/ |

---

## Cluster Layout

| Node       | IP            | Role                           | RAM  | vCPU |
|------------|---------------|--------------------------------|------|------|
| slurm-mgr  | 192.168.50.10 | slurmctld + slurmdbd + MariaDB | 2 GB | 2    |
| compute-01 | 192.168.50.11 | slurmd                         | 1 GB | 2    |
| compute-02 | 192.168.50.12 | slurmd                         | 1 GB | 2    |

**Network:** `slurm-net` (192.168.50.0/24) — created automatically by vagrant-libvirt, NAT-forwarded so VMs reach the internet for `dnf`.

**Slurm services:**
- `slurmctld` — central controller/scheduler (manager only)
- `slurmd` — job executor daemon (each compute node)
- `slurmdbd` — accounting database daemon (manager only)
- `munged` — authentication daemon (all nodes, same key)

---

## Prerequisites

```bash
sudo dnf install -y vagrant vagrant-libvirt libvirt-daemon-kvm munge
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt $USER
# Log out and back in after usermod
```

---

## Step 1 — Host Setup (run ONCE before first `vagrant up`)

```bash
chmod +x setup.sh scripts/*.sh
./setup.sh
```

This generates two files that Vagrant rsync delivers to every VM at boot:

- `configs/munge.key` — shared MUNGE cryptographic key (all nodes must have the same key per the MUNGE installation guide)
- `configs/slurm.conf` — Slurm configuration (must be identical on all nodes per the Slurm quick start guide)

> **Why on the host?** Vagrant rsync is host→VM only. Files cannot be shared
> between VMs via `/vagrant`. Generating them on the host and rsyncing to all
> VMs is the correct pattern.

---

## Step 2 — Start the Cluster

```bash
# Manager first — creates slurm-net libvirt network + all Slurm services
vagrant up slurm-mgr

# Then compute nodes — join slurm-net, start slurmd
vagrant up compute-01 compute-02

# Or all at once (safe because compute scripts wait for configs)
vagrant up
```

---

## Step 3 — Verify

```bash
vagrant ssh slurm-mgr

sinfo
# Expected output:
# PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
# compute*     up   infinite      2   idle compute-[01-02]

scontrol show nodes        # detailed node info
sacctmgr show cluster      # confirm cluster registered in slurmdbd
```

---

## Submit Test Jobs

```bash
vagrant ssh slurm-mgr

# Single node job
sbatch --wrap="hostname && echo done" --output=/tmp/job-%j.out
squeue
cat /tmp/job-*.out

# Span both compute nodes
sbatch -N2 --wrap="hostname" --output=/tmp/multi-%j.out
squeue
cat /tmp/multi-*.out
```

---

## Useful Commands

```bash
# Live queue monitoring
watch -n1 squeue

# Logs (on slurm-mgr)
tail -f /var/log/slurm/slurmctld.log
tail -f /var/log/slurm/slurmdbd.log

# Logs (on compute nodes)
tail -f /var/log/slurm/slurmd.log

# Accounting
sacct -a
sacctmgr show cluster
sacctmgr show user

# Resume nodes manually if stuck in down state
sudo scontrol update NodeName=compute-01 State=RESUME
sudo scontrol update NodeName=compute-02 State=RESUME
```

---

## Tear Down

```bash
vagrant destroy -f

# Optionally remove the libvirt network
sudo virsh net-destroy slurm-net
sudo virsh net-undefine slurm-net
```

---

## Troubleshooting

**Nodes show as `down` in `sinfo` after boot:**
```bash
sudo scontrol update NodeName=compute-01 State=RESUME
sudo scontrol update NodeName=compute-02 State=RESUME
```
Normal on first boot — `slurmctld` marks nodes `down` until their first heartbeat arrives.

**MUNGE authentication failures:**
```bash
# All three must print the same MD5
vagrant ssh slurm-mgr  -- md5sum /etc/munge/munge.key
vagrant ssh compute-01 -- md5sum /etc/munge/munge.key
vagrant ssh compute-02 -- md5sum /etc/munge/munge.key

# Test MUNGE encode/decode locally and remotely (from a compute node)
munge -n | unmunge
munge -n | ssh slurm-mgr unmunge
```

**`slurmd` can't connect to `slurmctld`:**
```bash
# Check slurmd log on the compute node
sudo journalctl -u slurmd -n 50

# Verify firewall ports are open on manager (6817/6818/6819)
sudo firewall-cmd --list-ports
```

**libvirt network stuck on re-up:**
```bash
sudo virsh net-list --all
sudo virsh net-start slurm-net   # if inactive
```

---

## Issues Encountered & Fixed

These are real problems hit during setup on Fedora 43 + vagrant-libvirt 0.11.2.

---

### 1. `Network not found: no network with matching name`

**Cause:** vagrant-libvirt requires explicit `libvirt__` prefixed options to know
how to create a private network. Without them it looks for an existing network
by IP and fails.

**Fix:** Specify network name, DHCP, and forward mode explicitly in the Vagrantfile:
```ruby
vm.network "private_network",
  ip:                    "192.168.50.10",
  libvirt__network_name: "slurm-net",
  libvirt__dhcp_enabled: false,
  libvirt__forward_mode: "nat"
```
Reference: https://vagrant-libvirt.github.io/vagrant-libvirt/configuration.html#private-network-options

---

### 2. `Network not found` on Fedora even with correct network options

**Cause:** On Fedora, vagrant-libvirt defaults to `qemu:///session` (unprivileged
user session). Session connections cannot access or create system-level libvirt
networks. The network appears to be created but the domain starts under
`qemu:///system` where it doesn't exist.

**Fix:** Force system-level QEMU connection in the global provider block:
```ruby
config.vm.provider :libvirt do |lv|
  lv.qemu_use_session = false
end
```
Reference: https://vagrant-libvirt.github.io/vagrant-libvirt/configuration.html#connection-options

---

### 3. `virtiofs` synced folder fails

**Cause:** `virtiofs` requires `virtiofsd` running on the host with specific
QEMU memory-backend configuration — not available out of the box with vagrant-libvirt on Fedora.

**Fix:** Use `rsync` which works universally:
```ruby
config.vm.synced_folder ".", "/vagrant", type: "rsync",
  rsync__exclude: [".git/", ".vagrant/"]
```

---

### 4. `sudo: /usr/sbin/create-munge-key: command not found` on Fedora 43

**Cause:** `create-munge-key` was a helper script in older MUNGE RPM packages.
Fedora 43 ships MUNGE 0.5.16+ which replaced it with `mungekey`.

**Fix:** Use `mungekey` with a `dd` fallback (setup.sh handles this automatically):
```bash
# Modern MUNGE (Fedora 43+)
mungekey -c -f -k /etc/munge/munge.key

# Universal fallback per official MUNGE Installation Guide
dd if=/dev/urandom bs=1 count=1024 > /etc/munge/munge.key
chown munge:munge /etc/munge/munge.key
chmod 400 /etc/munge/munge.key
```
Reference: https://github.com/dun/munge/wiki/Installation-Guide

---

### 5. `No match for argument: slurm-pmi` on CentOS Stream 9

**Cause:** `slurm-pmi` does not exist as a separate subpackage in EPEL 9.
PMI support is compiled into the base `slurm` package itself.

**Fix:** Install `slurm-libs` instead:
```bash
dnf install -y slurm slurm-libs
```
Reference: https://packages.fedoraproject.org/pkgs/slurm/

---

### 6. rsync is host→VM only — inter-VM file sharing doesn't work

**Cause:** The original design had `manager.sh` write `munge.key` and `slurm.conf`
into `/vagrant` for compute nodes to pick up during provisioning. With rsync,
VMs cannot write back to the host or share files with each other through `/vagrant`.

**Fix:** Pre-generate both files on the host via `setup.sh` before `vagrant up`.
Vagrant rsync then delivers `configs/munge.key` and `configs/slurm.conf` to all
VMs simultaneously at boot — no inter-VM dependency needed.