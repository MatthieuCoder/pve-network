FROM debian


# Install the makefile dependencies
RUN apt update && \
    apt install -y wget curl software-properties-common apt-transport-https ca-certificates gnupg2 && \
    echo "deb [arch=amd64] http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-install-repo.list && \
    wget https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg  && \
    apt update && apt full-upgrade -y && \
    apt install -y git locales debhelper-compat lintian libfile-slurp-perl libnet-subnet-perl libtest-mockmodule-perl perl pve-cluster pve-doc-generator libpve-access-control pve-firewall

ARG user=vscode
ARG group=vscode
ARG uid=1000
ARG gid=1000
RUN groupadd -g ${gid} ${group}
RUN useradd -u ${uid} -g ${group} -s /bin/sh -m ${user}
RUN chsh -s /bin/bash ${user}
RUN mkdir /env && chown ${user}:${group} -R /env
RUN chsh -s /bin/bash

ENV LANG=C

WORKDIR /env
