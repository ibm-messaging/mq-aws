#!/bin/bash
# -*- mode: sh -*-
# (C) Copyright IBM Corporation 2016,2017
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

if [ `id -un` != "root" ]; then
  exec su - root -- $0 "$@"
fi

timedatectl set-timezone UTC

# Recommended: Update all packages to the latest level
yum -y update

# These packages should already be present, but let's make sure
yum -y install \
  bash \
  curl \
  rpm \
  tar \
  bc

# Download and extract the MQ installation files
mkdir -p /tmp/mq
cd /tmp/mq
curl -LO ${MQ_URL}
tar -zxvf ./*.tar.gz

# Recommended: Create the mqm user ID with a fixed UID and group, so that the
# file permissions work between different images
groupadd --gid 1234 mqm
useradd --uid 1234 --gid mqm --home-dir /var/mqm mqm
usermod -G mqm root

# Configure file limits for the mqm user
echo "mqm       hard  nofile     10240" >> /etc/security/limits.conf
echo "mqm       soft  nofile     10240" >> /etc/security/limits.conf

# Configure kernel parameters to values suitable for running MQ
CONFIG=/etc/sysctl.conf
cp ${CONFIG} /etc/sysctl.conf.bak
sed -i '/^fs.file-max\s*=/{h;s/=.*/=524288/};${x;/^$/{s//fs.file-max=524288/;H};x}' ${CONFIG}
sed -i '/^kernel.shmmni\s*=/{h;s/=.*/=4096/};${x;/^$/{s//kernel.shmmni=4096/;H};x}' ${CONFIG}
sed -i '/^kernel.shmmax\s*=/{h;s/=.*/=268435456/};${x;/^$/{s//kernel.shmmax=268435456/;H};x}' ${CONFIG}
sed -i '/^kernel.shmall\s*=/{h;s/=.*/=2097152/};${x;/^$/{s//kernel.shmall=2097152/;H};x}' ${CONFIG}
sed -i '/^kernel.sem\s*=/{h;s/=.*/=32 4096 32 128/};${x;/^$/{s//kernel.sem=32 4096 32 128/;H};x}' ${CONFIG}

cd /tmp/mq/MQServer

# Accept the MQ license
./mqlicense.sh -text_only -accept

# Install MQ using the RPM packages
rpm -ivh ${MQ_PACKAGES}

# Recommended: Set the default MQ installation (makes the MQ commands available on the PATH)
/opt/mqm/bin/setmqinst -p /opt/mqm -i

# Clean up all the downloaded files
rm -rf /tmp/mq

# Create a templated systemd service for running MQ
cp /tmp/mq@.service /etc/systemd/system/
