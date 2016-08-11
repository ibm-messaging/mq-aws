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

MQ_QMGR_NAME=$1

state()
{
    dspmq -n -m ${MQ_QMGR_NAME} | awk -F '[()]' '{ print $4 }'
}

if [ "$#" -lt 1 ]; then
  echo "Usage: mq-health-check qmgr-name"
  exit 1
fi

# Figure out the AWS region from the instance metadata JSON
AWS_REGION=$(curl --silent http://169.254.169.254/latest/dynamic/instance-identity/document | python -c 'import json,sys;obj=json.load(sys.stdin);print obj["region"]')
AWS_INSTANCE_ID=$(curl --silent http://169.254.169.254/latest/meta-data/instance-id)

while true; do
  sleep 20
  if [ "$(state)" != "RUNNING" ]; then
      aws autoscaling set-instance-health --instance-id ${AWS_INSTANCE_ID}  --health-status Unhealthy --region ${AWS_REGION}
  fi
done
