#!/bin/bash
set -e

if [ -f /etc/redhat-release ]; then
    centos_maj_version=$(grep -oE '[0-9]+' /etc/redhat-release | head -n1)
    if [ "${centos_maj_version}" == 8 ]; then
       logfile='/var/log/dnf.rpm.log'
    else
       logfile='/var/log/yum.log'
    fi
else
  logfile='/var/log/apt/term.log'
fi

#echo ${logfile}

if [ "$(egrep -ic "error|warn" ${logfile})" != 0 ];then
        echo "ERROR: Warnings or Errors found in the installation logs"
        exit 1
else
        echo "Installation log is clean"
fi
