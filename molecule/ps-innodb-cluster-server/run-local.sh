#!/usr/bin/env bash
export TEST_DIST="bento/centos-7"
export INSTALL_REPO="testing"
export PS_NODE1_IP="192.168.33.50"
export PS_NODE2_IP="192.168.33.51"
export PS_NODE3_IP="192.168.33.52"
export MYSQL_ROUTER_IP="192.168.33.53"
export UPSTREAM_VERSION="8.0.22"
export PS_VERSION="13"
export PS_REVISION="e3e71c5"

if [ "$1" == "setup" ]; then
  molecule create -s vagrant
  cd ../ps-innodb-cluster-router
  molecule create -s vagrant
  cd -
  molecule converge -s vagrant
  cd ../ps-innodb-cluster-router
  molecule converge -s vagrant
  cd -
elif [ "$1" == "verify" ]; then
  molecule verify -s vagrant
  cd ../ps-innodb-cluster-router
  molecule verify -s vagrant
  cd -
elif [ "$1" == "destroy" ]; then
  molecule destroy -s vagrant
  cd ../ps-innodb-cluster-router
  molecule destroy -s vagrant
  cd -
fi
