#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: Run throughput tests
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
init_main_perf_env()
{
    set -a
    CASE_PATH="$(dirname $(readlink -f $0))"
    source /etc/os-release
    SYSTEM_VERSION_ID=`echo $VERSION_ID | tr -d '.'`
    source $CASE_PATH/Perf-Verify.conf
    source $CASE_PATH/env.sh
    set +a

    set -a
    ALL_CMD_FILE="/tmp/all_commands"
    CMD_FILE="/tmp/shell_commands"
    LOCK_FILE='/tmp/throughput-lock-file'
    MAIN_FILE="main.py"
    set +a
}

trap ctrl_c INT
ctrl_c()
{
    local my_pid=$(ps -ef | grep python | grep ${MAIN_FILE} | awk '{print $2}')
    kill -n 9 $my_pid
    exit
}

install_python()
{
    if (( $SYSTEM_VERSION_ID < 80 ))
    then
        yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    else
        yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
    fi

    # yum clean all
    yum makecache

    if (( $SYSTEM_VERSION_ID < 80 ))
    then
        yum -y install python-netifaces
        yum -y install python2-devel
    else
        yum -y install python3-netifaces
        yum -y install platform-python-devel
    fi
    yum -y install python2
    yum -y install python3
    yum -y install python3-devel
    yum -y install python3-pyelftools

    yum -y install python-pip
    yum -y install python3-pip

    python2 -m pip install --upgrade pip
    python2 -m pip install wheel
    python2 -m pip install netifaces
    python2 -m pip install six

}

install_python_and_init_env()
{
    install_python

    pushd $CASE_PATH
    if (($SYSTEM_VERSION_ID > 76)); then
        python3 -m venv ${CASE_PATH}/venv
    else
        python36 -m venv ${CASE_PATH}/venv
    fi
    yum -y install vim

    source venv/bin/activate
    pip install --upgrade pip
    pip install wheel
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
    pip install napalm
    pip install remote-pdb
    pip install ripdb
    pip install scapy
    pip install openpyxl
    pip install Pillow
    pip install tee
	#https://pypi.org/project/ripdb/
	pip install ripdb
	pip install scapy
    pip install lxml
    deactivate
    popd
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

install_rpms()
{
    rpm -q libnl3-devel || yum -y install libnl3-devel
    rpm -q libvirt-devel || yum -y install libvirt-devel
    rpm -q telnet || yum -y install telnet
    rpm -q procmail || yum -y install procmail

	rpm -qa | grep yum-utils || yum -y install yum-utils
	rpm -qa | grep scl-utils || yum -y install scl-utils
	rpm -qa | grep tuned-profiles-cpu-partitioning || yum -y install tuned-profiles-cpu-partitioning
    yum install -y wget nano ftp git tuna openssl sysstat
	#install libvirt
	yum install -y libvirt virt-install virt-manager virt-viewer
    #for qemu bug that can not start qemu
    echo -e "group = 'hugetlbfs'" >> /etc/libvirt/qemu.conf

	systemctl restart libvirtd
	yum install -y czmq-devel
	yum install -y libguestfs-tools
    yum -y install ethtool
}

create_log_folder()
{
    echo "Create Log Folder Begin Now"
    log_folder="/root/RHEL_NIC_QUAL_LOGS"
    if ! test -d $log_folder
    then
        echo "Create new log folder"
        mkdir -p $log_folder
    fi

    time_stamp=`date +%Y-%m-%d-%H-%M-%S`
    nic_log_folder=${log_folder}"/"${time_stamp}
    if test -d $nic_log_folder
    then
        rm -rf $nic_log_folder
        mkdir -p $nic_log_folder
    else
        mkdir -p $nic_log_folder
    fi

    touch ${nic_log_folder}"/throughput_log_folder.txt"
    export NIC_LOG_FOLDER=$nic_log_folder
    return 0
}

clean_previous_main_perf_test()
{
    local my_pid=$$
    echo "my pid is "$my_pid
    local my_child_pid=$(pgrep -P $my_pid)
    echo "child pid "$my_child_pid
    local N=0
    local run_pid=$(pgrep main-perf-test)
    echo "main-perf-test.sh pid list "$run_pid
    while true
    do
        for i in $run_pid
        do
            if grep -q $i <<< ${my_child_pid[@]};then
                continue
            elif [[ $i == $my_pid ]];then
                continue
            else
                echo "kill main-perf-test.sh pid "$i
                kill -9 $i
                kill -9 $i
                kill -9 $i
            fi
        done
        sleep 1
        N=$((N + 1))
        if [[ $N -ge 3 ]];then
            break
        fi
    done
}

clean_previous_py_process()
{
    local N=0
    while true
    do
        local run_pid=$(pgrep python)
        for i in $run_pid
        do
            echo "kill python pid "$i
            kill -9 $i
            kill -9 $i
            kill -9 $i
        done
        sleep 1
        N=$((N + 1))
        if [[ $N -ge 3 ]];then
            break
        fi
    done
}

start_main_process()
{
    pushd $CASE_PATH
    echo "Begin Start python process"
    source venv/bin/activate
    python -u main.py
    deactivate
    sleep 3
    popd
}

all_env_init()
{
    init_main_perf_env
    echo "==============================================="
    env
    echo "==============================================="
    install_rpms
    install_beakerlib
    install_python_and_init_env
    sleep 3
    source lib/lib_nc_sync.sh || exit 1
    source lib/lib_utils.sh || exit 1
    source /usr/share/beakerlib/beakerlib.sh || exit 1
}


start_run_test() 
{
    all_env_init

    clean_previous_py_process
    clean_previous_main_perf_test

    rm -f ${LOCK_FILE}
    rm -f ${ALL_CMD_FILE}
    rm -f ${CMD_FILE}

    touch ${ALL_CMD_FILE}
    touch ${CMD_FILE}

    start_main_process &
    sleep 5

    #read command from cmd file
    local N=0
    while true; do
        if test ! -s ${CMD_FILE}; then
            sleep 0.1
            N=$((N + 1))
            if [[ $N == 6000 ]]; then
                echo "${CMD_FILE} NOT UPDATE IN 600 SECONDS .NOW QUIT"
                break
            fi
        else
            N=0
            lockfile ${LOCK_FILE}
            if grep sriov-github-throughput-quit-string ${CMD_FILE};then
                killall python
                killall python
                killall main-perf-test.sh
                killall main-perf-test.sh
                killall main-perf-test.sh
                break
            fi
            source ${CMD_FILE}
            cat ${CMD_FILE} >>${ALL_CMD_FILE}
            true > ${CMD_FILE}
            rm -f ${LOCK_FILE}
        fi
    done
}

create_log_folder
touch ${NIC_LOG_FOLDER}/throughput_pvp_all_performance.txt
start_run_test |& tee -a ${NIC_LOG_FOLDER}/throughput_pvp_all_performance.txt
