# EOS-DOCKER
This repository contains all containers required for setting up EOS.
Each component of EOS, as detailed below, is run in a separate container, although files and volumes may be mapped to the same locations on the host.

The `docker-compose.yml` file can be used as a reference for configuring the containers, but it is only used to run up very specifically configured instances of EOS to check that the containers work.

## SYSTEM REQUIREMENTS

### Docker
In the systemd docker.service file, add the line `MountFlags=shared`, then restart docker for the change to take effect - this may not work on older versions of Docker (we currently use 17.05.0-ce).
This line allows a volume mount to be accessible to other containers.

Depending on the version of Docker, the default storage driver may be set to devicemapper or overlay (or overlay2 if available).
Overlay2 is preferable - change the value in `/etc/docker/daemon.json`, then restart docker to allow the change to take effect.

### Docker-Compose
The setup script makes use of docker-compose, so this will need to be installed on the system - we currently use version 1.7.1.

## QUICKSTART
There is an `eos.keytab` file that is empty - this **must** be re-generated for your own environment.

```
./build 
```

## EOS-DOCKER CONTAINER REFERENCE

The information in this section describes how each of the containers is configured for use in production.

### EOS Base
Base image required for all the other EOS-DOCKER containers; the build process installs all necessary RPMs for running EOS. 
This container is not meant to be run itself, but the image must be created.
EOS Base is built on top of RHEL7/ Centos7.

-----

### EOS MQ
EOS Message Queue Service container. The MQ is typically run on the same server as the MGM, but it can exist on a separate server.
The MQ listens on port `1097`. If not using `--net=host`, this port has to be exposed.

#### Required Environment Variables
  - EOS\_INSTANCE\_NAME - Cluster name
  - EOS\_GEOTAG - Geotag to describe region cluster is in
  - EOS\_MGM\_MASTER1 - EOS MGM active master
  - EOS\_MGM\_MASTER2 - EOS MGM slave
  - EOS\_MGM\_ALIAS - CNAME for the current master
  - EOS\_MAIL\_CC - Notification address for issues

#### Optional/Conditional Environment Variables
  - EOS\_SET\_MASTER - Must be set to 1 or true on a master node

**Single Node Deployment**

The EOS\_SET\_MASTER environment variable should be set to value 'true'/1. This creates the `/var/eos/eos.mq.master` file, which is the actual indicator that this MQ node is the master node.
Additionally, the values of EOS\_MGM\_MASTER1 and EOS\_MGM\_MASTER2 must be the same.

**Multiple Node Deployment**

For multiple node deployment, the EOS\_SET\_MASTER environment variable should be set to value 'true'/1 on the master node, and either omitted or set to 'false'/0 on the slave node.
Additionally, the values of EOS\_MGM\_MASTER1 and EOS\_MGM\_MASTER2 must be different.

If multiple slave nodes are deployed, each slave should have EOS\_MGM\_MASTER2 set as its own hostname, and EOS\_MGM\_MASTER1 set as the master's hostname.
On the master, EOS\_MGM\_MASTER2 can be set to any slave's hostname.

#### Required Volume Mounts
  - `/etc/eos.keytab` (file)
  - `/var/eos`
  - `/var/eos/tx`
  - `/var/eos/md`
  - `/var/eos/config`
  - `/var/eos/report`
  - `/var/log/eos`
  - `/var/spool/eos`

-----

### EOS MGM
EOS Management and Metadata server container. The MGM should be started after the MQ.
The MGM listens on port `1094`, and uses `8000` as well for HTTP. If not using `--net=host`, these ports have to be exposed.

#### Required Environment Variables
  - EOS\_INSTANCE\_NAME - Cluster name
  - EOS\_GEOTAG - Geotag to describe region cluster is in
  - EOS\_MGM\_MASTER1 - EOS MGM active master
  - EOS\_MGM\_MASTER2 - EOS MGM slave
  - EOS\_MGM\_ALIAS - CNAME for the current master
  - EOS\_MAIL\_CC - Notification address for issues

#### Optional/Conditional Environment Variables
  - EOS\_SET\_MASTER - Must be set to 1 or true on a master node
  - EOS\_START\_SYNC\_SEPARATELY - Must be set to 1 or true if deploying multiple nodes

**Single Node Deployment**

The EOS\_SET\_MASTER environment variable should be set to value 'true'/1. This creates the `/var/eos/eos.mgm.rw` file, which is the actual indicator that this MGM node is the master node.
Additionally, the values of EOS\_MGM\_MASTER1 and EOS\_MGM\_MASTER2 must be the same.

**Multiple Node Deployment**

For multiple node deployment, the EOS\_SET\_MASTER environment variable should be set to value 'true'/1 on the master node, and either omitted or set to 'false'/0 on the slave node.
Additionally, the values of EOS\_MGM\_MASTER1 and EOS\_MGM\_MASTER2 must be different.

If the values of EOS\_MGM\_MASTER1 and EOS\_MGM\_MASTER2 are different, the MGM tries to start both sync and filesync/dirsync via init scripts or systemd.
However this doesn't quite work in docker world, especially in an EL/Centos7 container without functional systemd.
Instead, we start sync and filesync/dirsync in their own containers, as described below, using the EOS\_START\_SYNC\_SEPARATELY environment variable to let the MGM know not to start any sync processes on its own.

#### Required Volume Mounts
  - `/etc/eos.keytab` (file)
  - `/var/eos`
  - `/var/eos/tx`
  - `/var/eos/md`
  - `/var/eos/config`
  - `/var/eos/report`
  - `/var/log/eos`
  - `/var/spool/eos`

The `/var/log/eos/tx` folder is created when EOS is installed - if we are mounting a local/persistent volume over `/var/log/eos`, it must be manually created.
Without the `/var/log/eos/tx` folder the MGM will not boot successfully, as it looks for a file it assumes is in that directory.

-----

### EOS SYNC
EOS Sync container. This must be run on the slave node in a master/slave setup; can be disregarded otherwise.
The sync process listens on port `1096`. If not using `--net=host`, this port has to be exposed.

#### Required Environment Variables
  - EOS\_INSTANCE\_NAME - Cluster name
  - EOS\_GEOTAG - Geotag to describe region cluster is in
  - EOS\_MGM\_MASTER1 - EOS MGM active master
  - EOS\_MGM\_MASTER2 - EOS MGM slave
  - EOS\_MGM\_ALIAS - CNAME for the current master
  - EOS\_MAIL\_CC - Notification address for issues

#### Required Volume Mounts
  - `/etc/eos.keytab` (file)
  - `/var/eos/md`
  - `/var/eos/config`
  - `/var/log/eos`
  - `/var/spool/eos`

-----

### EOS ~~EOSSYNC (ha ha)~~ FILESYNC & DIRSYNC
EOS Filesync and EOS Dirsync containers. A total of four of these (3x filesync, 1x dirsync) must be run on the master node in a master/slave setup, for each slave in the cluster; it can be disregarded otherwise.

The necessary processes are:
```
/usr/sbin/eosfilesync /var/eos/md/files.MASTER_HOSTNAME.mdlog       root://SYNC_HOSTNAME:1096///var/eos/md/files.MASTER_HOSTNAME.mdlog
/usr/sbin/eosfilesync /var/eos/md/directories.MASTER_HOSTNAME.mdlog root://SYNC_HOSTNAME:1096///var/eos/md/directories.MASTER_HOSTNAME.mdlog
/usr/sbin/eosfilesync /var/eos/md/iostat.MASTER_HOSTNAME.dump       root://SYNC_HOSTNAME:1096///var/eos/md/iostat.MASTER_HOSTNAME.dump
/usr/sbin/eosdirsync  /var/eos/config/MASTER_HOSTNAME/              root://SYNC_HOSTNAME:1096///var/eos/config/MASTER_HOSTNAME/
```

#### Required Environment Variables
  - EOS\_MGM\_HOST - Host that eossync is running on - usually the same as EOS\_MGM\_MASTER1
  - EOS\_MGM\_HOST\_TARGET - Host to sync metadata/config to - usually the slave MGM
  - SYNC\_TYPE - [file|dir] determines if container runs filesync or dirsync
  - SYNCFILE\_NAME - [files|directories|iostat] - name of file to be synced
  - SYNCFILE\_TYPE - [mdlog|dump] - type of file to be synced

The eossync-related environment variables for each container should be set as follows:

| SYNC\_TYPE | SYNCFILE\_NAME | SYNCFILE\_TYPE |
| ---------- | -------------- | -------------- |
| file       | files          | mdlog          |
| file       | directories    | mdlog          |
| file       | iostat         | dump           |
| dir        |                |                |

#### Required Volume Mounts
  - `/etc/eos.keytab` (file)
  - `/var/eos/md`
  - `/var/eos/config`

-----

### EOS FST
EOS File Storage Server container. Manages local storage partitions.
The FST listens on port `1095` by default, and uses `8001` as well for HTTP. If not using `--net=host`, these ports have to be exposed.

#### Required Environment Variables
  - EOS\_INSTANCE\_NAME - Cluster name
  - EOS\_GEOTAG - Geotag to describe region cluster is in
  - EOS\_MGM\_MASTER1 - EOS MGM active master
  - EOS\_MGM\_MASTER2 - EOS MGM slave
  - EOS\_MGM\_ALIAS - CNAME for the current master
  - EOS\_MAIL\_CC - Notification address for issues

#### Optional/Conditional Environment Variables
  - LUKSPASSPHRASE - Phrase to unlock the encrypted-at-rest disk volumes, if LUKS encryption is being used
  - EOS\_FST\_PORT - Port FST should run on, if a non-standard one is required - allows running multiple FSTs on same host, mostly for testing purposes

#### Required Volume Mounts
  - `/etc/eos.keytab` (file)
  - `/var/eos`
  - `/var/eos/tx`
  - `/var/eos/md`
  - `/var/eos/config`
  - `/var/eos/report`
  - `/var/log/eos`
  - `/var/spool/eos`
  - `/dev/disk/by-physlocation:ro` (:ro attribute indicates read-only)
  - `/disks:shared` (:shared attribute allows other containers to view in if required)

The FST entrypoint script handles mounting disks within the container itself.
It looks for disks with labels matching the patterns `eos*s*c*t*` or `earfs*c*t*` (luks encrypted disks), and mounts them into `/disks/<label>`.

-----

### EOSD & EOSXD
There are containers for eosd and eosxd. The eosxd configuration file is in JSON, and currently needs to be manually edited (MGM URL, etc).

#### Required Environment Variables
  - EOS\_FUSE\_MGM\_ALIAS - CNAME for the current master

#### Optional/Conditional Environment Variables
  - A whole list of fuse configuration variables can be found [here](http://eos-docs.web.cern.ch/eos-docs/configuration/fuse.html).

#### Required Volume Mounts
  - `/var/log/eos`
  - `/var/eos`
  - `/eos:shared` 

The namespaces on the host and in the container must match up, as fuse requires consistent mapping; typically, we mount `/eos` on the host to `/eos` in the container.
A path like `/home/user/eos` on the host would work just as well.

#### Required Devices
  - `/dev/fuse:rwm` 

#### Required Docker Settings
  - set pid to "host"
  - add SYS\_ADMIN capability
