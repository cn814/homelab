#!/bin/bash
# Fires after Unraid mounts array disks (disks_mounted event).
# Reinstalls the /mnt/cache persistent log config so syslog resumes
# writing to the array now that /mnt/cache is available again.
cp /boot/config/rsyslog-persistent.conf /etc/rsyslog.d/99-persistent.conf
/etc/rc.d/rc.rsyslogd restart &>/dev/null
