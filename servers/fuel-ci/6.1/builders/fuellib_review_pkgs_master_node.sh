#!/bin/bash

set -ex

export MIRROR_UBUNTU="$(curl -sSf "${JENKINS_URL}job/devops.6.1.env/lastSuccessfulBuild/artifact/mirror_ubuntu_data.txt")"

BRANCH_ID="6_1"

export FUEL_MAIN_PATH="/home/jenkins/workspace/fuel-main/env_masternode-${BRANCH_ID}"
export SYSTEM_TESTS="${FUEL_MAIN_PATH}/utils/jenkins/system_tests.sh"
export ENV_NAME="env_masternode-${BRANCH_ID}"
export ISO_PATH="/home/jenkins/workspace/iso/fuel_${BRANCH_ID}.iso"
export LOGS_DIR=/home/jenkins/workspace/${JOB_NAME}/logs/${BUILD_NUMBER}
export VENV_PATH=/home/jenkins/venv-nailgun-tests-2.9

#test params
export UPDATE_FUEL=true
export UPDATE_FUEL_PATH="${WORKSPACE}/packages/"
export UBUNTU_RELEASE='auxiliary'
export LOCAL_MIRROR_UBUNTU='/var/www/nailgun/ubuntu/auxiliary/'
export LOCAL_MIRROR_CENTOS='/var/www/nailgun/centos/auxiliary/'
export EXTRA_RPM_REPOS_PRIORITY=15
export EXTRA_DEB_REPOS_PRIORITY=1100
export CUSTOM_ENV=true
export BUILD_IMAGES=true
export TEST_GROUP="smoke_neutron"

VERSION_STRING=$(readlink "${ISO_PATH}" | cut -d '-' -f 2-3)
echo "Description string: ${VERSION_STRING}"

sh -x "${SYSTEM_TESTS}" -w "${FUEL_MAIN_PATH}" -V "${VENV_PATH}" -i "${ISO_PATH}" -t test -e "${ENV_NAME}" -o --group=${TEST_GROUP}
