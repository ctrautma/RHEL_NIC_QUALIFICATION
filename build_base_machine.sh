#!/bin/bash
#
# Build a base machine for RHEL 7.3
#
# Copyright 2016 OPNFV, Intel Corporation & Red Hat Inc.
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
#
# Contributors:
#   Aihua Li, Huawei Technologies.
#   Martin Klozik, Intel Corporation.
#   Abdul Halim, Intel Corporation.
#   Christian Trautman, Red Hat Inc.

# Make and Compilers
pkglist=(\
 automake\
 fuse-devel\
 gcc\
 gcc-c++\
 glib2-devel\
 glibc\
 kernel-devel\
 openssl-devel\
 pixman-devel\
 sysstat\
)

# Tools
pkglist=(
 "${pkglist[@]}"\
 git\
 libtool\
 libpcap-devel\
 libnet\
 net-tools\
 openssl\
 openssl-devel\
 pciutils\
 socat\
 tk-devel\
 wget\
 numactl\
 numactl-devel\
 libpng-devel\
 sshpass\
)

# python tools for proper QEMU, DPDK, and OVS make
pkglist=(
 "${pkglist[@]}"\
 python-six\
)

# install RHEL compatible epel for sshpass
yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm

# Iterate installing each package. If packages fail to install, record those
# packages and exit with an error message on completion. Customer may need to
# add repo locations and subscription levels.
failedinstall=()
for pkg in ${pkglist[*]}; do
    echo "Installing ${pkg}"
    yum -y install ${pkg} || failedinstall=("${failedinstall[*]}" "$pkg")
done

if [ "${#failedinstall[*]}" -gt 0 ]; then
    echo "The following packages failed to install. Please add appropriate repo\
 locations and/or subscription levels. Then run the build script again."
    for fail in ${failedinstall[*]}; do
        echo $fail
    done
    exit 1
fi

# python34 is not yet available to Red Hat customers so we will just build
# it as an alternate install in usr/local for use with VSPerf. This prevents
# any functionality issues with pre-installed packages using python.
wget https://www.python.org/ftp/python/3.4.2/Python-3.4.2.tar.xz
tar -xf Python-3.4.2.tar.xz
cd Python-3.4.2
./configure
make
make altinstall
cd ..

# cleanup
rm -Rf Python-3.4.2
rm -f Python-3.4.2.tar.xz

# need virtualenv
pip3.4 install virtualenv

# Create hugepage dirs
mkdir -p /dev/hugepages
