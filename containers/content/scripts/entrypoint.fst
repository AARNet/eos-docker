#!/bin/sh

export PATH=$PATH:/sbin:/usr/sbin

echo "Setting /tmp to mode 1777"
chmod 1777 /tmp
if [ $? -ne 0 ]; then
  echo "Cannot set permissions on /tmp, existing"
fi

echo "Creating log directory if it doesn't exist"
if ! [ -d "/var/log/eos/fst" ]; then
  mkdir -p /var/log/eos/fst
  chown daemon:daemon /var/log/eos/fst
fi

cd /disks
echo "Unmounting any existing mounts for file systems"
ls | sort | while read FS; do
  umount -f $FS
done

# create container /dev/mapper
rm -rf /dev/mapper && mkdir /dev/mapper

# make sure container has access to our logical volumes, if there are any
ls /hostdev/mapper/ | sort | while read DEVICE; do
  LABEL=`blkid -o value -s LABEL /hostdev/mapper/${DEVICE}`
  FSTYPE=`blkid -o value -s TYPE /hostdev/mapper/${DEVICE}`
  if [[ "${LABEL}" =~ ${FSLABEL}* ]] || [[ "${LABEL}" =~ ${FSLABEL_ENCRYPTED}* ]] || [ "${FSTYPE}" = "crypto_LUKS" ]; then
    ln -s /hostdev/mapper/${DEVICE} /dev/mapper/${DEVICE}
  fi
done

# next - check for encrypted volumes to close
ls /dev/mapper/luks* | sort | while read DEVICE; do
  FSTYPE=`blkid -o value -s TYPE ${DEVICE}`
  LABEL=`blkid -o value -s LABEL ${DEVICE}`

  if [ ! -z "${LABEL}" ] && [[ "${LABEL}" =~ ${FSLABEL_ENCRYPTED}* ]]; then
    TYPE=`lsblk -rno TYPE ${DEVICE}`
    if [ -z "${TYPE}" ]; then echo "lsblk failed, we have a mapper problem" && exit 1; fi
    if [ "${FSTYPE}" = "xfs" ] && [ "${TYPE}" = "crypt" ]; then
      cryptsetup luksClose ${DEVICE}
      echo "Disconnected ${DEVICE} from crypto loopback" 
    fi
  fi
done

# next - go over and re-open any encrypted volumes 
VOLUMES="`ls /dev/sd*` `ls /dev/mapper/*`"
for DEVICE in ${VOLUMES}; do
  FSTYPE=`blkid -o value -s TYPE ${DEVICE}`
  LABEL=`blkid -o value -s LABEL ${DEVICE}`

  if [ -z "${LABEL}" ] && [ "${FSTYPE}" = "crypto_LUKS" ]; then
    if [ -z "${LUKSPASSPHRASE}" ]; then echo "trying to unlock luks encrypted disk with no passphrase, what are you doing" && exit 1; fi
    TYPE=`lsblk -rno TYPE ${DEVICE} | head -n1`
    if [ "${TYPE}" = "disk" ]; then
      MAPPERNAME=luks`lsblk -rno HCTL ${DEVICE} | head -n1 | awk -F  ":" '{printf "c%02dt%02d",$1,$3;}'`
      echo "Unlocking ${DEVICE} as ${MAPPERNAME}" 
      echo ${LUKSPASSPHRASE} | cryptsetup luksOpen ${DEVICE} ${MAPPERNAME}
    elif [ "${TYPE}" = "lvm" ]; then
      MAPPERNAME=luks`basename ${DEVICE} | sed 's/-//' | cut -c 2-`
      echo "Unlocking ${DEVICE} as ${MAPPERNAME}" 
      echo ${LUKSPASSPHRASE} | cryptsetup luksOpen ${DEVICE} ${MAPPERNAME}
    fi
  fi
done

# lastly - mount all our volumes, encrypted and unencrypted
VOLUMES="`ls /dev/sd*` `ls /dev/mapper/*`"
for DEVICE in ${VOLUMES}; do
  FSTYPE=`blkid -o value -s TYPE ${DEVICE}`
  LABEL=`blkid -o value -s LABEL ${DEVICE}`

  if [ ! -z "${LABEL}" ] && ( [[ "${LABEL}" =~ ${FSLABEL}* ]] || [[ "${LABEL}" =~ ${FSLABEL_ENCRYPTED}* ]]); then
    if [ "${FSTYPE}" = "xfs" ]; then
      mkdir -p /disks/${LABEL}
      mount -o defaults,rw,noatime,nodiratime,swalloc,logbsize=256k,logbufs=8,inode64 -t xfs ${DEVICE} /disks/${LABEL} && \
      chown -f daemon:daemon /disks/${LABEL} && \
      echo "Successfully mounted ${DEVICE} as /disks/${LABEL} for FST usage"  || echo "Failed to mount ${DEVICE} for FST usage" 
    fi
  fi
done

sed -i "s/^xrd.port .*$/xrd.port ${EOS_FST_PORT-1095}/" /etc/xrd.cf.fst

# remove all ipv6
sed '/ip6/d' /etc/hosts > /etc/tmphosts && cat /etc/tmphosts > /etc/hosts && rm -f /etc/tmphosts && cat /etc/hosts
sed '/localhost6/d' /etc/hosts > /etc/tmphosts && cat /etc/tmphosts > /etc/hosts && rm -f /etc/tmphosts && cat /etc/hosts

echo "Mounted filesystems are:"
cd /disks && ls | sort | sed s/^/-\ /g | column
echo
echo "Starting EOS FST " $(rpm -q eos-server | sed s/eos-server-//g)

. /etc/sysconfig/eos

exec /usr/bin/xrootd -n fst -c /etc/xrd.cf.fst -l /var/log/eos/xrdlog.fst -Rdaemon 
