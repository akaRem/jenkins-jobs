#!/bin/bash

set -ex

DEBMIRROR=/usr/bin/debmirror
DEBMIRROR_OPTS=(-a amd64,i386 --di-arch=amd64 -method=rsync --no-check-gpg --progress --nosource --rsync-extra=indices,trace --exclude=i386.deb --exclude-deb-section=games --checksums)

RSYNC_PATH=/usr/bin/rsync
RSYNC_OPTS=(-av --delete)
RSYNC_REMOTE_OPTS=(-aH)

OUTPUT="[mirror]"

if [ -z "${DST_DIR}" ] || [ -z "${SRC_URL}" ] || [ -z "${DST_PREFIX}" ] || [ -z "${TMP_PREFIX}" ] || [ -z "${DEFAULT_URL}" ] || [ -z "${MIRRORS}" ]
then
  echo 'ERROR: Environment settings are not set!'
  exit 1
fi

# check if just one parameter, add | if required
if [[ ! ${MIRRORS} == *"|"* ]]
then
  MIRRORS="${MIRRORS}|"
fi

# get date for current sync naming
DATE=$(date +%F-%H%M%S)

# make temporary directory for sync
TMP_DIR=$(mktemp -d -p "${TMP_PREFIX}")

# get prefix for DST_DIR
PREFIX_DIR=$(echo "${DST_DIR}" | cut -f 1 -d %)

# get rsync destination and link-dest parameters
RSYNC_DEST="${DST_PREFIX}/${DST_DIR//%version%/-${DATE}}"
LAST_DEST="${DST_PREFIX}/${DST_DIR//%version%/-latest}"

# if older version exists, use hardlink switch
if [ -d "${LAST_DEST}" ]
then
  # copy everything except project dir using hardlinks
  find -H "${LAST_DEST}" -mindepth 1 -maxdepth 1 -not -name project | while read -r line
  do
    cp -al "${line}" "${TMP_DIR}"
  done
fi

STATUS=-1
if [[ "${SRC_URL}" =~ mirror:// ]]
then
  if [ -z "${DISTRIBUTIONS}" ] || [ -z "${INST_DISTRIBUTIONS}" ] || [ -z "${SECTIONS}" ]
  then
    echo 'ERROR: Missing debmirror settings!'
    exit 1
  fi
  # run debmirror
  HOST=$(echo "${SRC_URL}" | cut -f 3 -d '/')
  URL=$(echo "${SRC_URL}" | cut -f 4- -d '/')
  ${DEBMIRROR} "${DEBMIRROR_OPTS[@]}" -s "${SECTIONS}" -h "${HOST}" -r /"${URL}" -d "${DISTRIBUTIONS}" --di-dist="${INST_DISTRIBUTIONS}" "${TMP_DIR}" || STATUS=${?}
  # remove .temp directory
  rm -rf "${TMP_DIR}"/.temp
else
  # run rsync
  ${RSYNC_PATH} "${RSYNC_OPTS[@]}" "${SRC_URL}" "${TMP_DIR}" || STATUS=${?}
fi

# if sync is completed, move to destination directory and create latest link
if [ ${STATUS} -eq -1 ]
then
  # make directory and move temporary repo
  mkdir -p "${RSYNC_DEST}"
  mv -T "${TMP_DIR}" "${RSYNC_DEST}"
  # enforce creation date if mirror was not changed
  touch "${RSYNC_DEST}"
  OUTPUT+="<a href=${DEFAULT_URL}/${PREFIX_DIR}-${DATE}>${DST_DIR//%version%/-latest}</a><br>"
else
  echo "ERROR: Mirroring of ${RSYNC_DEST} failed!"
  rm -rf "${TMP_DIR}"
  exit 1
fi

echo "${OUTPUT}"

# prepare post-synchronization script
TMP_SYNC=$(mktemp -p "${TMP_PREFIX}")

# latest name
LATEST_NAME="${PREFIX_DIR}-latest"

# synchronize all mirrors
i=1
while [ ! -z "$(echo "${MIRRORS}" | cut -f ${i} -d '|')" ]
do
  # get mirror url
  MIRROR=$(echo "${MIRRORS}" | cut -f ${i} -d '|')
  i=$((i+1))
  TMPSYNC_DIR=$(mktemp -d -p "${TMP_PREFIX}")
  HOST=$(echo "${MIRROR}" | cut -f 3 -d '/')
  URL=$(echo "${MIRROR}" | cut -f 5- -d '/')
  ln -s "${PREFIX_DIR}-${DATE}" "${TMPSYNC_DIR}"/"${LATEST_NAME}"
  echo "http://${HOST}/${URL}/${PREFIX_DIR}-${DATE}" > \
    "${TMPSYNC_DIR}"/"${PREFIX_DIR}"-latest.htm
  ${RSYNC_PATH} -v "${RSYNC_REMOTE_OPTS[@]}" \
    --include "${PREFIX_DIR}-*/***" \
    --exclude "*" "${DST_PREFIX}"/ "${MIRROR}" && \
    echo "${RSYNC_PATH}" -av "${TMPSYNC_DIR}"/ "${MIRROR}" >> "${TMP_SYNC}" || STATUS=${?}
  echo rm -rf "${TMPSYNC_DIR}" >> "${TMP_SYNC}"
done

# update links on main node and all satellite mirrors
if [ ${STATUS} -eq -1 ]
then
  # update link on main mirror
  rm -f "${DST_PREFIX}"/"${LATEST_NAME}"
  ln -s "${PREFIX_DIR}-${DATE}" "${DST_PREFIX}"/"${LATEST_NAME}"
  # update index on main mirror
  echo "${DEFAULT_URL}/${PREFIX_DIR}-${DATE}" > "${DST_PREFIX}"/"${LATEST_NAME}".htm
  # update indexes and symlinks on satallite mirrors
  source "${TMP_SYNC}"
fi

# delete post-synchronization script
rm "${TMP_SYNC}"

if [ ${STATUS} -ne -1 ]
then
  exit 1
fi
