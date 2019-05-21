#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   runtest.sh of /kernel/networking/fd_nic_partition/bond
#   Author: Hekai Wang <hewang@redhat.com>
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2013 Red Hat, Inc.
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

# variables
source /etc/os-release
PACKAGE="kernel"
export CASE_PATH=${CASE_PATH:-"/mnt/tests/kernel/networking/fd_nic_partition/bond"}
SYSTEM_VERSION_ID=`echo $VERSION_ID | tr -d '.'`
export SYSTEM_VERSION_ID=${SYSTEM_VERSION_ID}

source /mnt/tests/kernel/networking/common/include.sh || exit 1
source /mnt/tests/kernel/networking/common/lib/lib_nc_sync.sh || exit 1
source /mnt/tests/kernel/networking/common/lib/lib_netperf_all.sh || exit 1
source ${CASE_PATH}/env.sh || exit 1

fd_nic_pipe=/tmp/fd-nic-partition-for-bond-pipe
notify_pipe=/tmp/fd-notify-pipe
export fd_nic_pipe=$fd_nic_pipe
export notify_pipe=$notify_pipe
rm -f $fd_nic_pipe
rm -f $notify_pipe
trap ctrl_c INT

function ctrl_c() {
    local my_pid=`ps -ef | grep python | grep start.py | awk '{print $2}'`
    kill -n 9 $my_pid
    exit
}

if [[ ! -p $fd_nic_pipe ]]; then
    mkfifo $fd_nic_pipe
fi

if [[ ! -p $notify_pipe ]]; then
    mkfifo $notify_pipe
fi



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

install_python_and_init_env
python start.py &
exec {fd}<>$fd_nic_pipe

check_python_process()
{
	while true
	do
		my_pid=`ps -ef | grep python | grep start.py | awk '{print $2}'`
		#this time read line timeout
		if (( ${#my_pid} == 0 ))
		then
			#because python exit for no normal reason
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

check_python_process & 

while true
do	
	echo -n "OK" > $notify_pipe
    if read -r line  <& $fd; then
        if [[ "$line" == 'fd-nic-partition-quit' ]]; then
            my_pid=`ps -ef | grep python | grep start.py | awk '{print $2}'`
            kill -n 9 $my_pid
            break
        fi
        #echo "$line"
        eval $line
    fi
done
