#!/bin/bash

set -ex

export DISPLAY=:99

export PATH=$PATH:${NPM_CONFIG_PREFIX}/bin

VENV="${WORKSPACE}_VENV"
[ "${VENV_CLEANUP}" == "true" ] && rm -rf "${VENV}"
virtualenv -p python2.7 "${VENV}"
source "${VENV}/bin/activate"

NODE_MODULES="${VENV}/node_modules"

cd "${WORKSPACE}/nailgun"
mkdir -p "${NODE_MODULES}"
ln -s "${NODE_MODULES}" node_modules
npm install

export TEST_NAILGUN_DB=nailgun

# Run UI tests
npm run lint
npm test

deactivate
