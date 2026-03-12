#!/usr/bin/env bash

# Copyright 2025 Genesis Corporation
#
# All Rights Reserved.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

set -eu
set -x
set -o pipefail


CORE_BRANCH=${CORE_BRANCH:-master}

curl -fsSL https://repository.genesis-core.tech/install.sh | sudo sh

#Build core image
git clone -b "$CORE_BRANCH" https://github.com/infraguys/genesis_core.git
cd ./genesis_core
export ALLOW_USER_PASSWD=true
export FREQUENT_LOG_VACUUM=true
export GEN_IMG_FORMAT_CORE=raw
genesis build -f . --inventory --manifest-var repository=https://repository.genesis-core.tech "$@"
jq '.[0].images[0] = "/opt/stand/genesis_core/output/images/genesis-core.raw"' output/inventory.json > temp.json
mv temp.json output/inventory.json
jq '.[0].manifests[0] = "/opt/stand/genesis_core/output/manifests/core.yaml"' output/inventory.json > temp.json
mv temp.json output/inventory.json
cd -

# Build stand image
genesis build -s element -f . "$@"
