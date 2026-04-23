#!/bin/bash
# Fires just before Unraid unmounts array disks (unmounting_disks event).
# Removes the /mnt/cache persistent log config so rsyslogd releases its
# file handle on /mnt/cache before the unmount attempt.
rm -f /etc/rsyslog.d/99-persistent.conf
/etc/rc.d/rc.rsyslogd restart &>/dev/null
