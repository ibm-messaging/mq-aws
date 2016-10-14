# Replicating IBM(R) MQ data using DRBD, part 2

This sample is the second relating to DRBD(R) and adds support for automatically failing over a queue manager using [Pacemaker](http://clusterlabs.org/wiki/Pacemaker), which is commonly used with DRBD.

This sample builds on top of [part 1](../part_1). If you have an environment from part 1 then you can extend that. If you do not have an environment from part 1 then you can create a new one using the template supplied in this sample.

## Extending an environment from part 1

If you have an environment from part 1 then you should stop the queue manager QM1 if it is running and unmount /mnt/QM1 on the same system. From now on, Pacemaker will decide where the queue manager should run.

You need to copy some additional scripts to each node:

1. configureFilesystem
2. configureHA_QM
3. configurePacemaker
4. installMQ_HA_QM
5. installPacemaker
6. MQ_HA_QM
7. MQ_HA_QM_monitor
8. MQ_HA_QM_start
9. MQ_HA_QM_stop

You will also need to allow udp traffic between the nodes on ports 5404 and 5405 for Pacemaker communication.

## Creating a new environment

You can create a new environment for part 2 using the createStack command in the part_2 directory, which uses a slightly different template which adds another Security Group to allow the Pacemaker UDP traffic.

You will need to copy the following scripts to each node:

1. configureFilesystem
2. configureForMQ
3. configureHA_QM
4. configurePacemaker
5. installDRBD
6. installMQ
7. installMQ_HA_QM
8. installPacemaker
9. MQ_HA_QM
10. MQ_HA_QM_monitor
11. MQ_HA_QM_start
12. MQ_HA_QM_stop

Follow the instructions from part 1 to get MQ and DRBD working.

## Installing Pacemaker

On each instance, run `sudo ./installPacemaker`

You will see the following messages which can be ignored:

```
The home directory `/var/lib/heartbeat' already exists.  Not copying from `/etc/skel'.
adduser: Warning: The home directory `/var/lib/heartbeat' does not belong to the user you are currently creating.
```

## Configuring Pacemaker Cluster

Copy the script configurePacemaker to each instance and run:

```
sudo ./configurePacemaker <IP1> <IP2> <IP3>
```

IP1 is the Private IP address of the first node in the cluster, IP2 is the Private IP address of the second node in the cluster and IP3 is the Private IP address of the third node in the cluster. The IP addresses should be supplied in the same order when the command is run on each instance.

To check that the cluster is configured and running, on one of the nodes run:

```
sudo crm_mon -1
```

You should see something like:

```
Last updated: Thu Oct  6 13:57:43 2016
Last change: Thu Oct  6 13:57:09 2016 via cibadmin on ip-10-0-3-232
Stack: corosync
Current DC: ip-10-0-2-56 (2) - partition with quorum
Version: 1.1.10-42f2063
3 Nodes configured
0 Resources configured


Online: [ ip-10-0-1-95 ip-10-0-2-56 ip-10-0-3-232 ]
```

## Creating Filesystem Resources

To manage the mounting and unmounting of the filesystem containing the data for the queue manager QM1 we are going to use a resource type that is shipped with Pacemaker: the Filesystem resource type. To create an instance of this resource type for QM1, run:

```
sudo ./configureFilesystem QM1
```

To check that this has worked, run:

```
sudo crm_mon -1
```

again and this time you should see something like:

```
Last updated: Thu Oct  6 14:01:34 2016
Last change: Thu Oct  6 14:01:21 2016 via cibadmin on ip-10-0-1-95
Stack: corosync
Current DC: ip-10-0-2-56 (2) - partition with quorum
Version: 1.1.10-42f2063
3 Nodes configured
1 Resources configured


Online: [ ip-10-0-1-95 ip-10-0-2-56 ip-10-0-3-232 ]

 p_fs_QM1	(ocf::heartbeat:Filesystem):	Started ip-10-0-3-232
 ```

 This shows that the resource is running (Started) on the node with a uname value of ip-10-0-3-232 and if you go to the node where your resource is running you should be able to do:

 ```
 ls /mnt/QM`
 ```

 and see the contents of the filesystem.

## Install MQ_HA_QM Resource Agent

To allow Pacemaker to manage queue managers I have written an Open Cluster Framework (OCF) Resource Agent script which invokes other scripts to monitor, start and stop queue managers. These other scripts are based on the samples given in the IBM MQ Knowledge Center.

To install the MQ_HA_QM Resource Agent, run:

```
sudo ./installMQ_HA_QM
```

## Configure Instance of MQ_HA_QM Resource Agent

To create an instance of the MQ_HA_QM resource agent for QM1, run:

```
sudo ./configureHA_QM QM1
```

In addition to creating a resource for the queue manager QM1, the script adds two constraints to the Pacemaker configuration:

1. a colocation constraint which says that the queue manager must run on the same node as the Filesystem
2. an ordering constraint which says that the Filesystem must be started before the queue manager is Started

To check that it worked, run:

```
sudo crm_mon -1
```

You should see something like:

```
Last updated: Mon Oct 10 12:58:40 2016
Last change: Mon Oct 10 12:58:36 2016 via crm_shadow on ip-10-0-1-118
Stack: corosync
Current DC: ip-10-0-1-118 (1) - partition with quorum
Version: 1.1.10-42f2063
3 Nodes configured
2 Resources configured


Online: [ ip-10-0-1-118 ip-10-0-2-141 ip-10-0-3-78 ]

 p_fs_QM1	(ocf::heartbeat:Filesystem):	Started ip-10-0-1-118
 QM1	(ocf::IBM:MQ_HA_QM):	Started ip-10-0-1-118
```

## Test Automatic Failover

To test that the queue manager automatically moves to another node if there is a problem with the first one, put the first node into standby node by running:

```
crm node standby <node name>
```

specifying the name of the node where the queue manager is normally running, in my case this was ip-10-0-1-118

To check that the queue manager has moved, run:

```
crm_mon -1
```

You should see that the filesystem and the queue manager are now both running on another node. In my case I saw:

```
Last updated: Mon Oct 10 13:02:19 2016
Last change: Mon Oct 10 13:02:12 2016 via crm_attribute on ip-10-0-1-118
Stack: corosync
Current DC: ip-10-0-1-118 (1) - partition with quorum
Version: 1.1.10-42f2063
3 Nodes configured
2 Resources configured


Node ip-10-0-1-118 (1): standby
Online: [ ip-10-0-2-141 ip-10-0-3-78 ]

 p_fs_QM1	(ocf::heartbeat:Filesystem):	Started ip-10-0-2-141
 QM1	(ocf::IBM:MQ_HA_QM):	Started ip-10-0-2-141
```

In my case the queue manager is now running on the node ip-10-0-2-141.

To restore the first node, run:

```
crm node online <node name>
```

## Summary

This sample has added a symmetric three-node Pacemaker cluster to the DRBD cluster and has shown how this can be used to manage where a queue manager runs automatically.
