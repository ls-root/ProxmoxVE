#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: ls-root
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://linkding.link

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Instaling dependencies"
install_packages_with_retry build-essential \
  pkg-config \
  libpq-dev \
  libicu-dev \
  libsqlite3-dev \
  libffi-dev \
  wget \
  unzip \
  chromium \
  python3-dev 
msg_ok "Installed dependencies"

PYTHON_VERSION="3.13" setup_uv
NODE_VERSION="22" setup_nodejs

fetch_and_deploy_gh_release "linkding" "sissbruecker/linkding" "tarball" "latest" "/opt/linkding"

cd /opt/linkding || exit

msg_info "Building frontend"
if [[ -d bookmarks/frontend ]]; then
  $STD npm ci
  $STD npm run build
fi
msg_ok "Built frontend"

msg_info "Installing python dependencies"
$STD uv venv .venv
$STD uv sync --no-dev --group postgres --python .venv/bin/python
msg_info "Installed python dependencies"

msg_info "Compiling SQLite ICU extension"
# Versions are also hardcoded in the offical Dockerfile
# https://github.com/sissbruecker/linkding/blob/master/docker/default.Dockerfile#L29-L34
wget -q https://www.sqlite.org/2023/sqlite-amalgamation-3430000.zip
unzip -q sqlite-amalgamation-3430000.zip
cp sqlite-amalgamation-3430000/sqlite3.h .
cp sqlite-amalgamation-3430000/sqlite3ext.h .
wget -q https://www.sqlite.org/src/raw/ext/icu/icu.c?name=91c021c7e3e8bbba286960810fa303295c622e323567b2e6def4ce58e4466e60 -O icu.c
$STD gcc -fPIC -shared icu.c "$(pkg-config --libs --cflags icu-uc icu-io)" -o libicu.so
msg_ok "ICU extension compiled"

msg_info "Installing single-file-cli"
$STD npm install -g single-file-cli@2.0.75
msg_ok "single-file-cli installed"

msg_info "Downloading uBlock Origin Lite"
TAG=$(curl -sL https://api.github.com/repos/uBlockOrigin/uBOL-home/releases/latest | jq -r '.tag_name')
curl -L -o ubol.zip https://github.com/uBlockOrigin/uBOL-home/releases/download/$TAG/uBOLite_$TAG.chromium.zip
unzip -q ubol.zip -d /opt/linkding/uBOLite.chromium.mv3
rm ubol.zip
msg_ok "uBlock installed"

mkdir -p chromium-profile

msg_info "Creating service"
cat <<EOF >/etc/systemd/system/linkding.service
[Unit]
Description=Linkding Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/linkding
Environment=LD_ENABLE_SNAPSHOTS=True
ExecStart=/opt/linkding/bootstrap.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now linkding
msg_ok "Service created"

motd_ssh
customize
cleanup_lxc
