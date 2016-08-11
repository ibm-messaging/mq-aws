#!/bin/bash
# -*- mode: sh -*-
# (C) Copyright IBM Corporation 2016
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

if [ "$#" -lt 3 ]; then
  echo "Usage: configure-mq-aws qmgr-name efs-id aws-region"
  exit 1
fi

set -x

MQ_QMGR_NAME=$1
MQ_FILE_SYSTEM=$2
AWS_REGION=$3
AWS_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)

# Configure fstab to mount the EFS file system as boot time
echo "${AWS_ZONE}.${MQ_FILE_SYSTEM}.efs.${AWS_REGION}.amazonaws.com:/ /var/mqm nfs4 defaults 0 2" >> /etc/fstab

# Mount the file system
mount /var/mqm

# Create/update the MQ directory structure under the mounted directory
/opt/mqm/bin/amqicdir -i -f

# Create the queue manager if it doesn't already exist
if [ ! -d "/var/mqm/qmgrs/${MQ_QMGR_NAME}" ]; then
  su mqm -c "crtmqm -q ${MQ_QMGR_NAME}" || exit 2
fi

# Add a systemd drop-in to create a dependency on the mount point
mkdir -p /etc/systemd/system/mq@${MQ_QMGR_NAME}.service.d
cat << EOF > /etc/systemd/system/mq@${MQ_QMGR_NAME}.service.d/mount-var-mqm.conf
[Unit]
RequiresMountsFor=/var/mqm
EOF

systemctl daemon-reload

# Enable the systemd services to run at boot time
systemctl enable mq@${MQ_QMGR_NAME}
systemctl enable mq-health-aws@${MQ_QMGR_NAME}

# Start the systemd services
systemctl start mq@${MQ_QMGR_NAME}
systemctl start mq-health-aws@${MQ_QMGR_NAME}

useradd johndoe -G mqm
echo johndoe:passw0rd | chpasswd
runmqsc ${MQ_QMGR_NAME} < /tmp/config.mqsc
