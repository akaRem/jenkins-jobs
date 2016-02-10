#!/bin/bash

set -ex

echo "puppet=$(puppet --version)"
echo "puppet-lint=$(puppet-lint --version | awk '{print $NF}')"

find . -name '*.pp' -print0 | xargs -0 -P1 -L1 file --mime-encoding | awk '
BEGIN {
  cnt = 0
}
{
  if($NF != "us-ascii") {
    print $0
    cnt += 1
  }
} END {
  if(cnt > 0) {
    exit(1)
  }
}'

find . -name '*.pp' -print0 | xargs -0 -P1 -L1 puppet parser validate --verbose

find . -name '*.pp' -print0 | xargs -0 -P1 -L1 puppet-lint \
          --fail-on-warnings \
          --with-context \
          --with-filename \
          --no-80chars-check \
          --no-variable_scope-check \
          --no-nested_classes_or_defines-check \
          --no-autoloader_layout-check \
          --no-class_inherits_from_params_class-check

find . -name '*.erb' -print0 | xargs -0 -P1 -L1 -I '%' erb \
          -P -x -T '-' % | ruby -c
