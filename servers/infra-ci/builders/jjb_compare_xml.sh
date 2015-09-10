#!/bin/bash

set -ex

GITHEAD=$(git rev-parse HEAD)
OUT_DIR=${WORKSPACE}/output
LOGFILE=${OUT_DIR}/jobs-diff.log
BLOCKED="[blocked]<br>"
CHANGED="[changed]<br>"
ADDED="[added]<br>"
REMOVED="[removed]<br>"
RESULT=''
BLOCKLIST=blocklist
BLOCK=0

# First generate output from BASE_COMMIT vars value
git checkout "${BASE_COMMIT}"

for ENV in ${WORKSPACE}/servers/*; do
  tox -e compare-xml-old -- "${ENV##*/}"
done

# Then use that as a reference to compare against HEAD
git checkout "${GITHEAD}"

for ENV in ${WORKSPACE}/servers/*; do
  tox -e compare-xml-new -- "${ENV##*/}"
done

DIFF=$(diff -q -r -u "${OUT_DIR}/old" "${OUT_DIR}/new" &>"${LOGFILE}"; echo "${?}")
# Any changed job discovered? If exit code was 1, then there is a difference
if [[ ${DIFF} -eq 1 ]]; then
  # Loop through all changed jobs and compare them with a blocklist
  for JOB in $(awk '/Files/ {print $2}' "${LOGFILE}"); do
    # Extract job's name
    JOB_NAME=$(basename "${JOB}")
    # Extract job's ENV name (server/${ENV} to make sure, that we are comparing ENV/JOB_NAME with right ENV/BLOCKLIST.
    JOB_ENV=$(echo "${JOB}" | awk -F "/" '{print $(NF?NF-1:0)}')
    # Make diff
    mkdir -p "${OUT_DIR}/diff/${JOB_ENV}"
    diff -U 50 "${OUT_DIR}/old/${JOB_ENV}/${JOB_NAME}" "${OUT_DIR}/new/${JOB_ENV}/${JOB_NAME}" >> "${OUT_DIR}/diff/${JOB_ENV}/${JOB_NAME}" || true
    for BL in ${WORKSPACE}/servers/${JOB_ENV}/${BLOCKLIST}; do
      # Do exact job name match when checking with blocklist.
      GREP=$(grep -Fxq "${JOB_NAME}" "${BL}"; echo "${?}")
      if [[ ${GREP} -eq 0 ]]; then
        BLOCK=1
        BLOCKED+=${JOB_ENV}/${JOB_NAME}\<br\>
      # If grep returned 2 then there was no such blockfile.
      elif [[ ${GREP} -eq 2 ]]; then
          echo Error. There is no such blockfile.
          exit 2
      else
        CHANGE=1
        CHANGED+=\<a\ href\=${BUILD_URL}artifact/output/diff/${JOB_ENV}/${JOB_NAME}/*view*/\>${JOB_ENV}/${JOB_NAME}\</a\>\<br\>
      fi
    done
  done
  # Print Blocked or Changed jobs.
  if [[ ${BLOCK} -eq 1 ]]; then
    RESULT+=${BLOCKED}
  elif [[ ${CHANGE} -eq 1 ]]; then
    RESULT+=${CHANGED}
  fi
  # Now find added/removed Jobs...
  for JOB in $(awk '/Only in/ {print $3$4}' "${LOGFILE}"); do
    ON=$(echo  "${JOB}"|awk -F/ '{print $7}')
    JOB_NAME=$(echo  "${JOB}"| awk -F: '{print $2}')
    JOB_ENV=$(echo "${JOB}" | awk -F "/" '{print $(NF?NF-0:0)}' | cut -f1 -d ':')
    if [[ ${ON} = 'old' ]]; then
      REMOVE=1
      REMOVED+=\<a\ href\=${BUILD_URL}artifact/output/old/${JOB_ENV}/${JOB_NAME}/*view*/\>${JOB_ENV}/${JOB_NAME}\</a\>\<br\>
    elif [[ ${ON} = 'new' ]]; then
      ADD=1
      ADDED+=\<a\ href\=${BUILD_URL}artifact/output/new/${JOB_ENV}/${JOB_NAME}/*view*/\>${JOB_ENV}/${JOB_NAME}\</a\>\<br\>
    fi
  done
  # And print added/removed if any.
  if [[ ${REMOVE} -eq 1 ]]; then
    RESULT+=${REMOVED}
  fi
  if [[ ${ADD} -eq 1 ]]; then
    RESULT+=${ADDED}
  fi
fi
echo "${RESULT}"
exit "${BLOCK}"
