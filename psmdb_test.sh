#!/bin/bash

log="/tmp/psmdb_run.log"
echo -n > /tmp/psmdb_run.log

source /package-testing/VERSIONS

SLES=0
if [ -f /etc/os-release ]; then
  SLES=$(cat /etc/os-release | grep -c '^NAME=\"SLES' || true)
fi

set -e

# Enable auditLog and profiling/rate limit to see if services start with those
if [ "$1" == "3.0" ]; then
  echo "Skipping usage of profiling rate limit functionality because not available in 3.0"
  sed -i 's/#operationProfiling:/operationProfiling:\n  mode: all\n  slowOpThresholdMs: 200/' /etc/mongod.conf
else
  sed -i 's/#operationProfiling:/operationProfiling:\n  mode: all\n  slowOpThresholdMs: 200\n  rateLimit: 100/' /etc/mongod.conf
fi
sed -i 's/#auditLog:/audit:\n  destination: file\n  path: \/tmp\/audit.json/' /etc/mongod.conf

function start_service {
  local redhatrelease=""
  if [ -f /etc/redhat-release ]; then
    redhatrelease=$(cat /etc/redhat-release | grep -o '[0-9]' | head -n 1)
  fi
  local lsbrelease=$(lsb_release -sc 2>/dev/null || echo "")
  if [ "${lsbrelease}" != "" -a "${lsbrelease}" = "trusty" ]; then
    echo "starting mongod service directly with init script..."
    /etc/init.d/mongod start
  elif [ "${redhatrelease}" = "5"  ]; then
    echo "starting mongod service directly with init script..."
    /etc/init.d/mongod start
  elif [ "${lsbrelease}" != "" -a ${SLES} -eq 1 ]; then
    echo "starting mongod with /sbin/service on SLES..."
    /sbin/service mongod start
  else
    echo "starting mongod service... "
    service mongod start
  fi
  echo "waiting 10s for service to boot up"
  sleep 10
}

function stop_service {
  local redhatrelease=""
  if [ -f /etc/redhat-release ]; then
    redhatrelease=$(cat /etc/redhat-release | grep -o '[0-9]' | head -n 1)
  fi
  local lsbrelease=$(lsb_release -sc 2>/dev/null || echo "")
  if [ "${lsbrelease}" != "" -a "${lsbrelease}" = "trusty" ]; then
    echo "stopping mongod service directly with init script..."
    /etc/init.d/mongod stop
  elif [ "${redhatrelease}" = "5"  ]; then
    echo "stopping mongod service directly with init script..."
    /etc/init.d/mongod stop
  elif [ "${lsbrelease}" != "" -a ${SLES} -eq 1 ]; then
    echo "stopping mongod with /sbin/service on SLES..."
    /sbin/service mongod stop
  else
    echo "stopping mongod service... "
    service mongod stop
  fi
  echo "waiting 10s for service to stop"
  sleep 10
}

function list_data {
  if [ -f /etc/redhat-release -o ${SLES} -eq 1 ]; then
    echo "$(date +%Y%m%d%H%M%S): contents of the mongo data dir: " >> $log
    ls /var/lib/mongo/ >> $log
  else
    echo "$(date +%Y%m%d%H%M%S): contents of the mongodb data dir: " >> $log
    ls /var/lib/mongodb/ >> $log
  fi
}

function clean_datadir {
  if [ -f /etc/redhat-release -o ${SLES} -eq 1 ]; then
    echo -e "removing the data files (on rhel distros)...\n"
    rm -rf /var/lib/mongo/*
  else
    echo -e "removing the data files (on debian distros)...\n"
    rm -rf /var/lib/mongodb/*
  fi
}

function test_hotbackup {
  rm -rf /tmp/backup
  mkdir -p /tmp/backup
  chown mongod:mongod -R /tmp/backup
  BACKUP_RET=$(mongo admin --eval 'db.runCommand({createBackup: 1, backupDir: "/tmp/backup"})'|grep -c '"ok" : 1')
  rm -rf /tmp/backup
  if [ ${BACKUP_RET} = 0 ]; then
    echo "Backup failed for storage engine: ${engine}"
    exit 1
  fi
}

function check_rocksdb_ver {
  if [ -f /etc/redhat-release -o ${SLES} -eq 1 ]; then
    ROCKSDB_VERSION=$(grep "RocksDB version" /var/lib/mongo/db/LOG|tail -n1|grep -Eo "[0-9]+\.[0-9]+(\.[0-9]+)*$")
  else
    ROCKSDB_VERSION=$(grep "RocksDB version" /var/lib/mongodb/db/LOG|tail -n1|grep -Eo "[0-9]+\.[0-9]+(\.[0-9]+)*$")
  fi
  if [ "$1" == "3.0" ]; then
    ROCKSDB_VERSION_NEEDED=${PSMDB30_ROCKSDB_VER}
  elif [ "$1" == "3.2" ]; then
    ROCKSDB_VERSION_NEEDED=${PSMDB32_ROCKSDB_VER}
  elif [ "$1" == "3.4" ]; then
    ROCKSDB_VERSION_NEEDED=${PSMDB34_ROCKSDB_VER}
  else
    echo "Wrong parameter to script: $1"
    exit 1
  fi
  if [ "${ROCKSDB_VERSION}" != "${ROCKSDB_VERSION_NEEDED}" ]; then
    echo "Wrong version of RocksDB library! Needed: ${ROCKSDB_VERSION_NEEDED} got: ${ROCKSDB_VERSION}"
    exit 1
  fi
}

for engine in mmapv1 PerconaFT rocksdb wiredTiger inMemory; do
  if [ "$1" == "3.4" -a ${engine} == "PerconaFT" ]; then
    echo "Skipping PerconaFT because version is 3.4"
  else
    stop_service
    clean_datadir
    sed -i "/engine: *${engine}/s/#//g" /etc/mongod.conf
    echo "testing ${engine}" | tee -a $log
    start_service
    if [ ${engine} == "rocksdb" ]; then
      check_rocksdb_ver
    fi
    echo "importing the sample data"
    mongo < /package-testing/mongo_insert.js >> $log
    list_data >> $log
    if [[ ${engine} = "wiredTiger" || ${engine} = "rocksdb" ]] && [[ "$1" != "3.0" ]]; then
      echo "testing the hotbackup functionality"
      test_hotbackup
    fi
    stop_service
    echo "disable ${engine}"
    sed -i "/engine: *${engine}/s//#engine: ${engine}/g" /etc/mongod.conf
    clean_datadir
  fi
done
