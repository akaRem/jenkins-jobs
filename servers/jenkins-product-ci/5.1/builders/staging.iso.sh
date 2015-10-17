#!/bin/bash

set -ex

echo STARTED_TIME="`date -u +'%Y-%m-%dT%H:%M:%S'`" > ci_status_params.txt

# Checking gerrit commits for fuel-main
if [ "${FUELMAIN_COMMIT}" != "master" ] ; then
    git checkout "${FUELMAIN_COMMIT}"
fi

PROD_VER=$(grep 'PRODUCT_VERSION:=' config.mk | cut -d= -f2)

export LANG="C"
export PATH=/bin:/usr/bin:/sbin:/usr/sbin:${PATH}

export ISO_NAME=fuel-staging-${PROD_VER}-${BUILD_NUMBER}-${BUILD_ID}
export UPGRADE_TARBALL_NAME=fuel-staging-${PROD_VER}-upgrade-${BUILD_NUMBER}-${BUILD_ID}

export BUILD_DIR=${WORKSPACE}/../tmp/${JOB_NAME}/build
export LOCAL_MIRROR=${WORKSPACE}/../tmp/${JOB_NAME}/local_mirror

export ARTS_DIR=${WORKSPACE}/artifacts
rm -rf ${ARTS_DIR}

# Checking gerrit commits for fuel-main
if [ "${fuelmain_gerrit_commit}" != "none" ] ; then
  for commit in ${fuelmain_gerrit_commit} ; do
    git fetch https://review.openstack.org/openstack/fuel-main ${commit} && git cherry-pick FETCH_HEAD || false
  done
fi

export NAILGUN_GERRIT_COMMIT="${nailgun_gerrit_commit}"
export ASTUTE_GERRIT_COMMIT="${astute_gerrit_commit}"
export OSTF_GERRIT_COMMIT="${ostf_gerrit_commit}"
export FUELLIB_GERRIT_COMMIT="${fuellib_gerrit_commit}"
export PYTHON_FUELCLIENT_GERRIT_COMMIT="${python_fuelclient_gerrit_commit}"

#########################################

echo "STEP 0. Clean before start"
make deep_clean

#########################################

echo "STEP 1. Make everything"

make ${make_args} iso img version-yaml ${add_make_target}

#########################################

echo "STEP 2. Publish everything"

cd ${ARTS_DIR}

for artifact in $(ls fuel-*)
do
  ${WORKSPACE}/utils/jenkins/process_artifacts.sh ${artifact}
done

cd ${WORKSPACE}

echo FUELMAIN_GERRIT_COMMIT="${fuelmain_gerrit_commit}" > ${ARTS_DIR}/gerrit_commits.txt
echo NAILGUN_GERRIT_COMMIT="${nailgun_gerrit_commit}" >> ${ARTS_DIR}/gerrit_commits.txt
echo ASTUTE_GERRIT_COMMIT="${astute_gerrit_commit}" >> ${ARTS_DIR}/gerrit_commits.txt
echo OSTF_GERRIT_COMMIT="${ostf_gerrit_commit}" >> ${ARTS_DIR}/gerrit_commits.txt
echo FUELLIB_GERRIT_COMMIT="${fuellib_gerrit_commit}" >> ${ARTS_DIR}/gerrit_commits.txt
echo PYTHON_FUELCLIENT_GERRIT_COMMIT="${python_fuelclient_gerrit_commit}" >> ${ARTS_DIR}/gerrit_commits.txt

cp ${LOCAL_MIRROR}/*changelog ${ARTS_DIR}/ || true
cp ${BUILD_DIR}/iso/isoroot/version.yaml ${ARTS_DIR}/version.yaml.txt || true
(cd ${BUILD_DIR}/iso/isoroot && find . | sed -s 's/\.\///') > ${ARTS_DIR}/listing.txt || true

grep MAGNET_LINK ${ARTS_DIR}/*iso.data.txt > ${ARTS_DIR}/magnet_link.txt

# Generate build description
ISO_MAGNET_LINK=$(grep MAGNET_LINK ${ARTS_DIR}/*iso.data.txt | sed 's/MAGNET_LINK=//')
ISO_HTTP_LINK=$(grep HTTP_LINK ${ARTS_DIR}/*iso.data.txt | sed 's/HTTP_LINK=//')
ISO_HTTP_TORRENT=$(grep HTTP_TORRENT ${ARTS_DIR}/*iso.data.txt | sed 's/HTTP_TORRENT=//')
IMG_HTTP_TORRENT=$(grep HTTP_TORRENT ${ARTS_DIR}/*img.data.txt | sed 's/HTTP_TORRENT=//')

echo "DESCRIPTION=<a href=${ISO_HTTP_TORRENT}>ISO</a> <a href=${IMG_HTTP_TORRENT}>IMG</a>" > ${ARTS_DIR}/status_description.txt

echo "<a href="${ISO_HTTP_LINK}">ISO download link</a> <a href="${ISO_HTTP_TORRENT}">ISO torrent link</a><br>${ISO_MAGNET_LINK}<br>"

#########################################

echo "STEP 3. Clean after build"
make deep_clean

echo FINISHED_TIME="`date -u +'%Y-%m-%dT%H:%M:%S'`" >> ci_status_params.txt
