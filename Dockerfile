FROM debian


# Install the makefile dependencies
RUN apt update && \
    apt install -y wget curl software-properties-common apt-transport-https ca-certificates gnupg2 && \
    echo "deb [arch=amd64] http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-install-repo.list && \
    wget https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg  && \
    apt update && apt full-upgrade -y && \
    apt install -y debhelper-compat lintian libfile-slurp-perl libnet-subnet-perl libtest-mockmodule-perl perl pve-cluster pve-doc-generator libpve-access-control pve-firewall

WORKDIR /env
