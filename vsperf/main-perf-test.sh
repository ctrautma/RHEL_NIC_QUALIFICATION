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
/bin/bash $CASE_PATH/repo.sh || exit 1

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

work_pipe=/tmp/sriov-github-work
notify_pipe=/tmp/sriov-notfiy-work
test -p $work_pipe && unlink $work_pipe
test -p $notify_pipe && unlink $notify_pipe
mkfifo $work_pipe
mkfifo $notify_pipe
python_file="start.py"
bash_exit_str="sriov-github-vsperf"
source $CASE_PATH/Perf-Verify.conf
set +a

trap ctrl_c INT
function ctrl_c() 
{
    local my_pid=`ps -ef | grep python | grep ${python_file} | awk '{print $2}'`
    kill -n 9 $my_pid
	kill -n 9 $process_PID
    exit
}

install_beakerlib()
{
    pushd $CASE_PATH
    rpm -q git  || yum -y install git
    rpm -q gcc  || yum -y install gcc
    rpm -q make || yum -y install make
    test -f /usr/share/beakerlib/beakerlib.sh && return 0
    test -d beakerlib && return 0
    git clone https://github.com/beakerlib/beakerlib.git
    pushd beakerlib
    git checkout beakerlib-1.18
    make 
    make install
    popd
    popd
    return 0
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
    rpm -q telnet || yum -y install telnet
    rpm -q vim || yum -y install vim
    
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
    pip install remote-pdb
    pip install tee
	#https://pypi.org/project/ripdb/
	pip install ripdb
	pip install scapy
}

check_python_process()
{
    local ppid=$1
	while true
	do
		sleep 10
		my_pid=`ps -ef | grep python | grep ${python_file} | awk '{print $2}'`
		#this time read line timeout
		if (( ${#my_pid} == 0 ))
		then
			echo "python process not exists , exit check process now !!!"
			break
		else
			if kill -0 $$
			then
				continue
			else
				echo "can not find the ppid process ,exit python process now"
                kill -9 $my_pid
				exit 0
			fi
		fi
	done
	exit 0
}


install_beakerlib
exec {fd}<>$work_pipe
install_python_and_init_env
sleep 3
source lib/lib_nc_sync.sh || exit 1
source lib/lib_utils.sh || exit 1
source /usr/share/beakerlib/beakerlib.sh || exit 1 
python start.py &
check_python_process $$ &
while true
do
    echo -n "OK" > $notify_pipe
    #Here read ctrl + D as the end of one each command
    if read -r line  <& $fd; then
        if [[ "$line" == "${bash_exit_str}" ]]; then
            my_pid=`ps -ef | grep python | grep ${python_file} | awk '{print $2}'`
            kill -n 9 $my_pid
            break
        fi
        eval $line
    fi
done
