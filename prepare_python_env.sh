#!/bin/bash
#
# Prepare Python environment for vsperf execution on RHEL 7.3 systems.
#
# Copyright 2016-2017 OPNFV, Intel Corporation, Red Hat Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# enable virtual environment in a subshell, so QEMU build can use python 2.7
# Also make sure we know which virtualenv was installed. I've seen the file
# name change pending on what type of installation was done.
virtualenv_file=$(ls /usr/local/bin | awk '/virtualenv/')

($virtualenv_file "$VSPERFENV_DIR"
pip3.4 install -r ../requirements.txt
pip3.4 install pylint
)