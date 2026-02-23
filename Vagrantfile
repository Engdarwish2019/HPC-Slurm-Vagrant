# =============================================================================
# Slurm Cluster — Vagrantfile
# Stack : CentOS Stream 9 · KVM/libvirt · 1 Manager + 2 Compute Nodes
# =============================================================================
# Nodes:
#   slurm-mgr   192.168.50.10  → slurmctld + slurmdbd + MariaDB + MUNGE
#   compute-01  192.168.50.11  → slurmd + MUNGE
#   compute-02  192.168.50.12  → slurmd + MUNGE
#
# Network: "slurm-net" (192.168.50.0/24) — isolated, no DHCP, NAT-forwarded
#   vagrant-libvirt will CREATE this network automatically on first `vagrant up`
# =============================================================================

Vagrant.configure("2") do |config|

  # ── Base box ────────────────────────────────────────────────────────────────
  config.vm.box = "centos/stream9"

  # ── Default libvirt provider settings ────────────────────────────────────────
  config.vm.provider :libvirt do |lv|
    lv.driver             = "kvm"
    lv.storage_pool_name  = "default"
    # CRITICAL for Fedora: default is qemu:///session which has no access to
    # system-level networks. Force qemu:///system so networks can be created.
    lv.qemu_use_session   = false
  end

  # ── Shared folder via rsync (most compatible with libvirt) ───────────────────
  # Scripts are synced on `vagrant up`; munge.key + slurm.conf written here
  # by manager.sh are picked up by compute nodes during their provisioning
  config.vm.synced_folder ".", "/vagrant", type: "rsync",
    rsync__exclude: [".git/", ".vagrant/"]

  # ============================================================================
  # MANAGEMENT NODE — slurm-mgr
  # Runs: slurmctld, slurmdbd, MariaDB, munged
  # Provisions first so munge.key + slurm.conf land in /vagrant before computes
  # ============================================================================
  config.vm.define "slurm-mgr", primary: true do |mgr|
    mgr.vm.hostname = "slurm-mgr"

    # ── Network: attach to "slurm-net" — libvirt creates it automatically ──────
    mgr.vm.network "private_network",
      ip:                       "192.168.50.10",
      libvirt__network_name:    "slurm-net",
      libvirt__netmask:         "255.255.255.0",
      libvirt__host_ip:         "192.168.50.1",
      libvirt__dhcp_enabled:    false,
      libvirt__forward_mode:    "nat"   # NAT so VMs can reach internet for dnf

    mgr.vm.provider :libvirt do |lv|
      lv.memory = 2048
      lv.cpus   = 2
    end

    # common setup first, then manager-specific
    mgr.vm.provision "shell", path: "scripts/common.sh"
    mgr.vm.provision "shell", path: "scripts/manager.sh"
  end

  # ============================================================================
  # COMPUTE NODE 01 — compute-01
  # Runs: slurmd, munged
  # ============================================================================
  config.vm.define "compute-01" do |c1|
    c1.vm.hostname = "compute-01"

    # ── Network: join same "slurm-net" (already created by slurm-mgr) ─────────
    c1.vm.network "private_network",
      ip:                       "192.168.50.11",
      libvirt__network_name:    "slurm-net",
      libvirt__netmask:         "255.255.255.0",
      libvirt__dhcp_enabled:    false,
      libvirt__forward_mode:    "nat"

    c1.vm.provider :libvirt do |lv|
      lv.memory = 1024
      lv.cpus   = 2
    end

    c1.vm.provision "shell", path: "scripts/common.sh"
    c1.vm.provision "shell", path: "scripts/compute.sh"
  end

  # ============================================================================
  # COMPUTE NODE 02 — compute-02
  # Runs: slurmd, munged
  # ============================================================================
  config.vm.define "compute-02" do |c2|
    c2.vm.hostname = "compute-02"

    # ── Network: join same "slurm-net" ─────────────────────────────────────────
    c2.vm.network "private_network",
      ip:                       "192.168.50.12",
      libvirt__network_name:    "slurm-net",
      libvirt__netmask:         "255.255.255.0",
      libvirt__dhcp_enabled:    false,
      libvirt__forward_mode:    "nat"

    c2.vm.provider :libvirt do |lv|
      lv.memory = 1024
      lv.cpus   = 2
    end

    c2.vm.provision "shell", path: "scripts/common.sh"
    c2.vm.provision "shell", path: "scripts/compute.sh"
  end

end