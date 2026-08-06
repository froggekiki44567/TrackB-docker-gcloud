#!/bin/bash
set -e

apt-get update
apt-get install -y ca-certificates curl gnupg git

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update

# Pin to a specific, known-good Docker version so behavior is reproducible
DOCKER_VERSION="5:27.3.1-1~debian.12~bookworm"

if apt-cache madison docker-ce | grep -q "$DOCKER_VERSION"; then
  echo "Installing pinned Docker version: $DOCKER_VERSION"
  apt-get install -y \
    docker-ce=$DOCKER_VERSION \
    docker-ce-cli=$DOCKER_VERSION \
    containerd.io \
    docker-compose-plugin
else
  echo "WARNING: pinned Docker version $DOCKER_VERSION not found in repo, falling back to latest stable"
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi

systemctl enable docker
systemctl start docker

if [ ! -d /opt/app ]; then
  git clone https://github.com/froggekiki44567/TrackB-docker-gcloud /opt/app
else
  cd /opt/app && git pull
fi
cd /opt/app/app

export ENVIRONMENT=$(curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/attributes/environment")

docker compose up -d --build