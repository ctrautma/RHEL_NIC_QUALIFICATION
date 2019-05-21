#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: Run VSPerf tests
#   Author: Hekai Wang <hewang@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2017 Red Hat, Inc. All rights reserved.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Detect OS name and version from systemd based os-release file
set -a
CASE_PATH="$(dirname $(readlink -f $0))"
source /etc/os-release
SYSTEM_VERSION_ID=`echo $VERSION_ID | tr -d '.'`

if [ $VERSION_ID == "7.5" ]
then
    dpdk_ver="1711-9"
    one_queue_image="RHEL7-5VNF-1Q.qcow2"
    two_queue_image="RHEL7-5VNF-2Q.qcow2"
    one_queue_zip="RHEL7-5VNF-1Q.qcow2.lrz"
    two_queue_zip="RHEL7-5VNF-2Q.qcow2.lrz"
elif [ $VERSION_ID == "7.6" ]
then
    dpdk_ver="1711-9"
    one_queue_image="RHEL76-1Q.qcow2"
    two_queue_image="RHEL76-2Q.qcow2"
    one_queue_zip="RHEL76-1Q.qcow2.lrz"
    two_queue_zip="RHEL76-2Q.qcow2.lrz"
fi

work_pipe="sriov-github-work"
notify_pipe="sriov-notfiy-work"
unlink $work_pipe
unlink $notify_pipe
mkfifo $work_pipe
mkfifo $notify_pipe
python_file="start.py"
bash_exit_str="sriov-github-vsperf"

set +a

trap ctrl_c INT
ctrl_c() 
{
    local my_pid=`ps -ef | grep python | grep ${python_file} | awk '{print $2}'`
    kill -n 9 $my_pid
    exit
}

install_beakerlib()
{
    pushd $CASE_PATH
    rpm -q git  || yum -y install git
    rpm -q gcc  || yum -y install gcc
    rpm -q make || yum -y install make
    git clone https://github.com/beakerlib/beakerlib.git
    git checkout beakerlib-1.18
    make 
    make install
    popd
    return 0
}

check_python_process()
{
	while true
	do
        sleep 3
		my_pid=`ps -ef | grep python | grep ${python_file} | awk '{print $2}'`
		#this time read line timeout
		if (( ${#my_pid} == 0 ))
		then
			echo "Shell Check that python process exit "
			break
		else
			if kill -0 $$
			then
				continue
			else
				echo "parent process not exist"
				exit 1
			fi
		fi
	done
	kill -9 $$
	exit 1
}

install_python_and_init_env()
{
    pushd $CASE_PATH
    if (( $SYSTEM_VERSION_ID < 80 ))
	then
		rpm -q epel-release || yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
	else
		rpm -q epel-release || dnf -y install epel-release
        rpm -q platform-python-devel || yum -y install platform-python-devel
	fi
	rpm -q libnl3-devel || yum -y install libnl3-devel
    rpm -q python36 || yum -y install python36
    rpm -q python36-devel || yum -y install python36-devel
    rpm -q libvirt-devel || yum -y install libvirt-devel
    
    if (( $SYSTEM_VERSION_ID >= 80 ))
	then
		python3 -m venv ${CASE_PATH}/venv
	else
		python36 -m venv ${CASE_PATH}/venv
	fi

	source venv/bin/activate
	export PYTHONPATH=${CASE_PATH}/venv/lib64/python3.6/site-packages/
	pip install --upgrade pip

	pip install fire
	pip install psutil
	pip install paramiko
	pip install xmlrunner
	pip install netifaces
	pip install argparse
	pip install plumbum
	pip install ethtool
	pip install shell
    pip install libvirt-python
    pip install envbash
	pip install bash
	pip install pexpect
	pip install serial
	pip install pyserial
}

install_beakerlib
install_python_and_init_env
python start.py &
sleep 3
check_python_process & 

while true
do	
	echo -n "OK" > $notify_pipe
    if read -r line  <& $work_pipe; then
        if [[ "$line" == "${bash_exit_str}" ]]; then
            my_pid=`ps -ef | grep python | grep ${python_file} | awk '{print $2}'`
            kill -n 9 $my_pid
            break
        fi
        eval $line
    fi
done
