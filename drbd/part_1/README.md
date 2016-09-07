# Replicating IBM MQ data using DRBD

There are two aspects to any High Availability (HA) or Disaster Recovery (DR)
solution for IBM(R) MQ:

1. managing where an instance of a queue manager runs
2. making sure that the appropriate data is available to the queue manager

This sample assumes that a queue manager is stopped and started manually,
and uses [DRBD(R)](https://www.drbd.org/en/) to replicate data between Linux systems.

This version of the sample creates three Ubuntu Virtual Servers, one in each
Availability Zone of an AWS region. Using three instances ensures that if one
fails data will still be replicated between the remaining two.
IBM MQ and DRBD are installed in each and
configured appropriately.

The sample uses an Elastic Block Storage (EBS) volume for the queue manager data. EBS replicates data within an Availability Zone and this sample builds on that by replicating the data between Availability Zones so even if an entire Availability Zone fails you can still start another instance of the queue manager.

The data replication is tested by writing some persistent messages to a queue
when the queue manager is running on one virtual server, the queue manager is
then shut down and started on another virtual server and the messages retrieved.

## Creating Ubuntu Virtual Servers

The Virtual Servers are created using a CloudFormation template. The template defines a number of parameters:
1. AMI - the identifier of the AMI to use to create the instances
2. ClusterName - a string that is used to name the instances
3. InstanceTypeParameter - the type of instance to create; the default is m3.xlarge. As the instances are defined with the EbsOptimized attribute set to "true" only instance types which support EBS Optimization are allowed
4. KeyName - the name of the key pair to use to authenticate to the instances

The resources created by the template are:
1. a Virtual Private Cloud (VPC) to contain the other resources
2. an InternetGateway to allow access to the virtual servers over the Internet
3. a VPCGatewayAttachment to associate the InternetGateway with the VPC
4. a RouteTable for the VPC
5. three SubnetRouteTableAssociations, one for each of the SubnetRouteTableAssociations
6. a Route that allows access to any of the IP addresses
7. three Subnets, one for each Availability Zone
8. three Instances, one for each Availability Zone
9. a SecurityGroup that allows ssh access via port 22 to any IP address and allows MQ access to the ports 1414, 1515 and 1616
10. a SecurityGroup that allows tcp access to any port on any IP address, to allow the DRBD instances to communicate with each other

The outputs defined in the template are the public and private IP addresses of each instance.

To make it easier to create a stack using the template, a `createStack` script is included which takes the following arguments:
1. the AMI to use
2. the name of the cluster
3. the instance type
4. the region in which to create the stack
5. the name of the SSH key to use
6. a string to tag the resources with using the Owner tag

You can create a stack using a command like `./createStack ami-d732f0b7 drbd-cluster m4.large us-west-2 '<key name>' <userid>` where <key name> should be replaced with the name of your SSH key pair and <userid> should be replaced with your AWS userid.

The following steps, up to and including installing DRBD, could be done once and a custom AMI produced which you could then use to create the stack rather than the standard Ubuntu AMI.

You can monitor the progress of the creation of the stack using the `describeStack` script, for example `./describeStack drbd-cluster us-west-2`

When the `StackStatus` is CREATE_COMPLETE you should see an `Outputs` section containing the public and private IP addresses of the three instances.

The instances are configured with an additional EBS volume of type IO1. The size of the volume is 26 GiB and the IOPS are configured at the maximum for a volume of this size: 1300.

## Installing IBM MQ

As this is just a sample, we will use IBM MQ Advanced for Developers which can be downloaded [here](http://www14.software.ibm.com/cgi-bin/weblap/lap.pl?popup=Y&li_formnum=L-APIG-A4FHQ9&accepted_url=http://public.dhe.ibm.com/ibmdl/export/pub/software/websphere/messaging/mqadv/mqadv_dev90_linux_x86-64.tar.gz)

Once you have downloaded the file mqadv_dev90_linux_x86-64.tar.gz, scp it to each instance.

### Preparing each instance

There are some configuration changes that should be made before installing MQ.

The first is to edit `/etc/sysctl.conf` as root and add the following lines:
```
kernel.shmmax=268435456
vm.overcommit_memory=2
```

Save the file and run the command `sudo sysctl -p`

The second change is to edit `/etc/security/limits.conf` as root and add the following lines:
```
* hard nofile 10240
* soft nofile 10240
root hard nofile 10240
root soft nofile 10240
```

Finally, edit `/etc/pam.d/common-session` as root and add the line:
```
session required pam_limits.so
```

You should exit and connect to the instance again before installing MQ.

### Installing IBM MQ

To install IBM MQ, perform the following as root:
1. `tar -xzf mqadv_dev90_linux_x86-64.tar.gz`
2. `cd MQServer`
3. `./mqlicense.sh -accept`
4. `apt-get -y install rpm`
5. `rpm -ivh --force-debian *.rpm`

You should check that the uid and gid values for mqm are the same on all the instances.

### Final configuration

There are some steps that must performed once IBM MQ is installed:
1. run `sudo /opt/mqm/bin/setmqinst -i -p /opt/mqm`
2. edit the `.bashrc` file of the ubuntu user and add the line `. /opt/mqm/bin/setmqenv -s`
3. add the ubuntu user to the mqm group using the command `sudo usermod -G mqm ubuntu`

Log out and log in again.

### Testing MQ Installation

When you have logged back in again, run `dspmqver` which should show something like:
```
Name:        IBM MQ
Version:     9.0.0.0
Level:       p900-L160520.DE
BuildType:   IKAP - (Production)
Platform:    IBM MQ for Linux (x86-64 platform)
Mode:        64-bit
O/S:         Linux 3.13.0-92-generic
InstName:    Installation1
InstDesc:    
Primary:     Yes
InstPath:    /opt/mqm
DataPath:    /var/mqm
MaxCmdLevel: 900
LicenseType: Developer
```
To verify that IBM MQ has been installed successfully, perform the following:
```
crtmqm QMA
strmqm QMA
runmqsc QMA
DEFINE QLOCAL (QUEUE1) DEFPSIST(YES)
end
cd /opt/mqm/samp/bin
./amqsput QUEUE1 QMA
Message1
Message2
Message3

./amqsget QUEUE1 QMA
```

You should see the three messages you entered when you ran amqsput.

## Installing DRBD

You can copy the `installDRBD` script to each instance and use that to install DRBD and prepare the instance to use the `drbdmanage` tool to configure DRBD, or you can just issue the commmands directly on each instance.

DRBD will be installed from the PPA maintained by LINBIT, the company behind DRBD.

This will install the latest version of DRBD which has some new features that we will use:
1. a new approach to manage drbd: drbdmanage
2. support for replicating data to more than one other instance
3. making the replicated data available by simply mounting the DRBD device

To use the script, run `sudo ./installDRBD`

### Setting up the DRBD Cluster

On one instance, issue the command `sudo drbdmanage init -q`

On one of the other instances, run `uname -n` and then on the first instance run the command `sudo drbdmanage add-node <uname> <IP address>` where <uname> is the value returned by `uname -n` on the second instance and <IP address> is the private IP address of the second instance.

This will print out a command that has to be executed as root on the second instance so run that command as root on the second instance. You will have to enter 'yes' to confirm the operation.

Repeat for the third instance.

You should now have a three-node DRBD cluster defined.

On the first instance, run `sudo drbdmanage list-nodes` and you should see something like:

```
+------------------------------------------------------------------------------+
| Name          | Pool Size | Pool Free |                              | State |
|------------------------------------------------------------------------------|
| ip-10-0-1-161 |     26620 |     26612 |                              |    ok |
| ip-10-0-2-63  |     26620 |     26612 |                              |    ok |
| ip-10-0-3-4   |     26620 |     26612 |                              |    ok |
+------------------------------------------------------------------------------
```

If you do not want to copy and paste commands to set up the cluster, you can enable passwordless ssh for the root user on the three instances and then DRBD will run the necessary commands automatically on the other nodes.

## Creating a DRBD volume for a queue manager

It is necessary to have consistency between the queue manager recovery logs and the queue files. The easiest way to guarantee this is to put all of the data for the queue manager in a single DRBD volume.

The drbdmanage tool can create an LVM so we will create a volume for another queue manager, QM1, using the command `sudo drbdmanage add-volume QM1 3GB --deploy 3` which can be run on any node, but I tend to run such commands on the first node. This creates a 3GB volume named QM1 and deploys it to all three nodes so any change made to the primary instance will be replicated to two secondary instances.

To check that the volume was created and deployed correctly, run the command `sudo drbdmanage list-assignments` and you should see output similar to:

```
+------------------------------------------------------------------------------+
| Node          | Resource | Vol ID |                                  | State |
|------------------------------------------------------------------------------|
| ip-10-0-1-161 | QM1      |      * |                                  |    ok |
| ip-10-0-2-63  | QM1      |      * |                                  |    ok |
| ip-10-0-3-4   | QM1      |      * |                                  |    ok |
+------------------------------------------------------------------------------+
```

## Configuring the queue manager

As root, run the following on the first appliance:
```
mkdir /mnt/QM1
chown mqm:mqm /mnt/QM1
mkfs.ext4 /dev/drbd/by-res/QM1/0
mount -t ext4 /dev/drbd/by-res/QM1/0 /mnt/QM1
mkdir /mnt/QM1/data
mkdir /mnt/QM1/logs
chown -R mqm:mqm /mnt/QM1
```
As the ubuntu user, run:
```
crtmqm -ld /mnt/QM1/logs -md /mnt/QM1/data QM1
```

You can start the queue manager immediately but you would not be able to move it to another instance until the initial synchronization of the volume has completed. You can check this by running the command `sudo drbdsetup status QM1` which will return something like the following when the initial synchronization is complete:
```
QM1 role:Primary
  disk:UpToDate
  ip-10-0-2-63 role:Secondary
    peer-disk:UpToDate
  ip-10-0-3-4 role:Secondary
    peer-disk:UpToDate
```

Once both peer-disk lines say `UpToDate` it is safe to start the queue manager with `strmqm QM1`

### Configuring the queue manager on the other instances

On the first instance run the command `dspmqinf -o command QM1` which will print an addmqinf command that you have to run on each of the other instances, but before doing that you should prepare the mount point for the data volume by running as root:
```
mkdir /mnt/QM1
chown mqm:mqm /mnt/QM1
```

You can then run, as the ubuntu user, the generated addmqinf command. This will give a message about /mnt/QM1/data/QM1/qm.ini missing but that can be ignored.

## Testing moving the queue manager

To test moving the queue manager from one instance to another, we will do the same test as before but divided into two parts, and move the queue manager from one instance to another between the two parts.

The first part consists of writing some persitent messages to a queue on the QM1 queue manager, so on the first instance run, as the ubuntu user:
```
runmqsc QM1
DEFINE QLOCAL (QUEUE1) DEFPSIST(YES)
end
cd /opt/mqm/samp/bin
./amqsput QUEUE1 QM1
Message1
Message2
Message3

endmqm -w QM1
sudo umount /mnt/QM1
```

Now, on one of the other instances run as the ubuntu user:
```
sudo mount -t ext4 /dev/drbd/by-res/QM1/0 /mnt/QM1
strmqm QM1
cd /opt/mqm/samp/bin
./amqsget QUEUE1 QM1
```

You should see the three messages that you put to the queue on the first instance, which shows that the data was replicated to whichever instance you chose to start the queue manager on.
