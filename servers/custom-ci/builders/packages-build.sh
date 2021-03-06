#!/bin/bash

set -ex

LOCATION_FACT=$(facter --external-dir /etc/facter/facts.d/ location)
LOCATION=${LOCATION_FACT:-bud}
UBUNTU_DIST=${UBUNTU_DIST:-trusty}

case "${LOCATION}" in
    srt)
        MIRROR_HOST="http://osci-mirror-srt.srt.mirantis.net/"
        ;;
    msk)
        MIRROR_HOST="http://osci-mirror-msk.msk.mirantis.net/"
        ;;
    kha)
        MIRROR_HOST="http://osci-mirror-kha.kha.mirantis.net/"
        ;;
    poz|bud|bud-ext|budext|undef)
        MIRROR_HOST="http://mirror.seed-cz1.fuel-infra.org/"
        ;;
    mnv|scc|sccext)
        MIRROR_HOST="http://mirror.seed-us1.fuel-infra.org/"
        ;;
    *)
        MIRROR_HOST="http://mirror.fuel-infra.org/"
esac

if [ ! -z "${CUSTOM_PROJECT_PACKAGE}" ]; then
  PROJECT_PACKAGE="${CUSTOM_PROJECT_PACKAGE}"
fi

# Checking gerrit commits for fuel-mirror
if [[ "${FUEL_MIRROR_GERRIT_COMMIT}" != "none" ]] ; then
  cd "${WORKSPACE}"/fuel-mirror
  for commit in ${FUEL_MIRROR_GERRIT_COMMIT} ; do
    git fetch origin "${commit}" && git cherry-pick FETCH_HEAD
  done
  cd "${WORKSPACE}"
fi


## we MUST use external DNS
echo "DNSPARAM=\"--dns 8.8.8.8\"" > "${WORKSPACE}"/fuel-mirror/perestroika/docker-builder/config

# where we store sources, this dir will be mounted to docker env
SOURCE_PATH="${WORKSPACE}/sources/"
# where we store packages, that should be uploaded by test
PACKAGES_DIR="${UPDATE_FUEL_PATH}"
# where we checkout fuel-library code
PROJECT_ROOT="${WORKSPACE}/${PROJECT}"

rm -rf "${SOURCE_PATH}" "${PACKAGES_DIR}"
mkdir -p "${SOURCE_PATH}" "${PACKAGES_DIR}"

# where docker will store results (builded packages)
RPM_RESULT_DIR="${WORKSPACE}/packages_rpm"
DEB_RESULT_DIR="${WORKSPACE}/packages_deb"
rm -rf "${RPM_RESULT_DIR}" "${DEB_RESULT_DIR}"
mkdir -p "${RPM_RESULT_DIR}" "${DEB_RESULT_DIR}"

# prepare fuel-library sources
pushd "${PROJECT_ROOT}" &>/dev/null

# taking version of package
RPM_PACKAGE_VERSION=$(rpm -q \
  --specfile "${PROJECT_ROOT}/specs/${PROJECT_PACKAGE}".spec \
  --queryformat "%{VERSION}\n" | head -1 )

NUMBER_OF_COMMITS=$(git -C "${PROJECT_ROOT}" rev-list --no-merges HEAD --count)
LAST_COMMIT_SHORT_HASH=$(git -C "${PROJECT_ROOT}" rev-parse --short HEAD)
IDENTIFIER="1.git"

RELEASE="${NUMBER_OF_COMMITS}.${IDENTIFIER}${LAST_COMMIT_SHORT_HASH}"

export DEBFULLNAME=$(git -C "${PROJECT_ROOT}" log -1 --pretty=format:%an)
export DEBEMAIL=$(git -C "${PROJECT_ROOT}" log -1 --pretty=format:%ae)
DEBMSG=$(git -C "${PROJECT_ROOT}" log -1 --pretty=%s)

# for rpm
git archive --format=tar.gz --worktree-attributes HEAD \
  --output="${SOURCE_PATH}/${PROJECT_PACKAGE}-${RPM_PACKAGE_VERSION}.tar.gz"

cp -v "${PROJECT_ROOT}/specs/${PROJECT_PACKAGE}.spec" "${SOURCE_PATH}"

# update spec with proper version
sed -i "s|Release:.*$|Release: ${RELEASE}|" "${SOURCE_PATH}/${PROJECT_PACKAGE}.spec"

## build rpm
"${WORKSPACE}"/fuel-mirror/perestroika/build-package.sh \
  --build-target centos7 \
  --ext-repos "mos,${MIRROR_HOST}mos-repos/centos/${RPM_MIRROR_BASE_NAME}/os/x86_64/" \
  --source "${SOURCE_PATH}" \
  --output-dir "${RPM_RESULT_DIR}"

# for deb
if [ -d "${PROJECT_ROOT}/debian" ]; then
  DEB_PACKAGE_VERSION=$(dpkg-parsechangelog --show-field Version | cut -d '-' -f1)
  cp -v "${SOURCE_PATH}/${PROJECT_PACKAGE}-${RPM_PACKAGE_VERSION}.tar.gz" "${SOURCE_PATH}/${PROJECT_PACKAGE}_${DEB_PACKAGE_VERSION}.orig.tar.gz"
  mkdir -p "${SOURCE_PATH}/${PROJECT_PACKAGE}"
  cp -rv "${PROJECT_ROOT}/debian" "${SOURCE_PATH}/${PROJECT_PACKAGE}"

  dch -c "${SOURCE_PATH}/${PROJECT_PACKAGE}/debian/changelog" \
    -D "${UBUNTU_DIST}" \
    -b --force-distribution \
    -v "${DEB_PACKAGE_VERSION}-${RELEASE}" "${DEBMSG}"
  ## build deb
  "${WORKSPACE}"/fuel-mirror/perestroika/build-package.sh \
    --upstream-repo "${MIRROR_HOST}pkgs/ubuntu/" \
    --build-target "${UBUNTU_DIST}" \
    --ext-repos "${MIRROR_HOST}mos-repos/ubuntu/${DEB_MIRROR_BASE_NAME} main restricted" \
    --source "${SOURCE_PATH}" \
    --output-dir "${DEB_RESULT_DIR}"
fi

popd &>/dev/null

# preparing artifacts
echo "Copy packages to artifacts dir"
find "${RPM_RESULT_DIR}" -type f -name '*.rpm' -exec cp -r {} "${PACKAGES_DIR}" \;
find "${DEB_RESULT_DIR}" -type f -name '*.deb' -exec cp -r {} "${PACKAGES_DIR}" \;
