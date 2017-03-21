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

# Fail on error
set -e

# Install NFS client, and other utils for this script
yum -y install \
  curl \
  nfs-utils \
  nfs-utils-lib \
  unzip

# Install the AWS command line
cd /tmp
curl "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" -o "awscli-bundle.zip"
unzip /tmp/awscli-bundle.zip
/tmp/awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws
rm -rf /tmp/awscli*

# Install the AWS-specific MQ health checking script
cp /tmp/check-mq-health-aws /usr/local/bin/
chmod +x /usr/local/bin/check-mq-health-aws

# Create a templated systemd service for checking the health of MQ
cp /tmp/mq-health-aws@.service /etc/systemd/system/
