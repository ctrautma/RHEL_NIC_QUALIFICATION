#!/bin/bash

unset NIC_DRIVER
NIC_DRIVER=$1
#NIC_DRIVER=${NIC_DRIVER:-"enic"}
NIC_DRIVER=${NIC_DRIVER:-"ixgbe"}
#NIC_DRIVER=${NIC_DRIVER:-"xl710"}
#NIC_DRIVER=${NIC_DRIVER:-"i40e"}
#NIC_DRIVER=${NIC_DRIVER:-"nfp"}
#NIC_DRIVER=${NIC_DRIVER:-"mlx5_core"}
#NIC_DRIVER=${NIC_DRIVER:-"broadcom"}
#NIC_DRIVER=${NIC_DRIVER:-"xxv"}
#NIC_DRIVER=${NIC_DRIVER:-"qede"}


SYSTEM_VERSION=${SYSTEM_VERSION:-"RHEL-7.6-20181010.0"}
version=$SYSTEM_VERSION

XENA_CONFIG_FILE='http://netqe-bj.usersys.redhat.com/share/wanghekai/config/bond_test/hewang_ovs_dpdk_bonding_new_topo-100G.x2544'
XENA_MODULE_INDEX=5
XENA_MODULE_PORT=0

TREX_URL=${TREX_URL:-'http://netqe-bj.usersys.redhat.com/share/wanghekai/v2.48.tar.gz'}

IMAGE_GUEST=${IMAGE_GUEST:-"http://netqe-bj.usersys.redhat.com/share/tli/vsperf_img/rhel${SYSTEM_VERSION:5:3}-vsperf-1Q-viommu.qcow2"}

echo "Test image URL "$IMAGE_GUEST
image_test_result=$(curl -s --head $IMAGE_GUEST | head -n 1 | awk '{print $NF}' | tr -d '\r')
if [[ $image_test_result == "OK" ]]
then
    echo "GUEST IMAGE EXIST , TEST IS PASS AND OK"
else
    echo "GUEST IMAGE NOT !!!!! EXIST , PLEASE CHECK "
    exit 1
fi

DRIVERCTL_URL=${DRIVERCTL_URL:-'http://download-node-02.eng.bos.redhat.com/brewroot/packages/driverctl/0.101/1.el7fdp/noarch/driverctl-0.101-1.el7fdp.noarch.rpm'}

CONTAINER_SELINUX_URL=${CONTAINER_SELINUX_URL:-"http://download-node-02.eng.bos.redhat.com/brewroot/packages/container-selinux/2.77/1.el7_6/noarch/container-selinux-2.77-1.el7_6.noarch.rpm"}

OVS_SELINUX_URL=${OVS_SELINUX_URL:-"http://download-node-02.eng.bos.redhat.com/brewroot/packages/openvswitch-selinux-extra-policy/1.0/10.el7fdp/noarch/openvswitch-selinux-extra-policy-1.0-10.el7fdp.noarch.rpm"}

OVS_URL=${OVS_URL:-"http://download-node-02.eng.bos.redhat.com/brewroot/packages/openvswitch/2.9.0/94.el7fdp/x86_64/openvswitch-2.9.0-94.el7fdp.x86_64.rpm"}

function get_python_ovs_url()
{
    local ovs_url=$1
    local system_version=$2
    local ovs_dir=`dirname $ovs_url`
    local ovs_name=`basename $ovs_url`
    local python_ovs_name
    if [[ $system_version == "7" ]]
    then
        python_ovs_name=`echo $ovs_name | sed -e s/openvswitch/python-openvswitch/g`
    else
        python_ovs_name=`echo $ovs_name | sed -e s/openvswitch/python3-openvswitch/g`
    fi
    eval "PYTHON_OVS_URL=$ovs_dir/$python_ovs_name"
    echo $PYTHON_OVS_URL
}
get_python_ovs_url $OVS_URL ${SYSTEM_VERSION:5:1}
wget -O/dev/null -q $PYTHON_OVS_URL && echo PYTHON OVS URL exists || echo PYTHON OVS URL not exist

function get_ovs_test_url()
{
    local OVS_URL=$1
    local ovs_test_base_url=`echo $OVS_URL | sed -e s/x86_64/noarch/g`
    local ovs_test_base_dir=`dirname $ovs_test_base_url`
    local ovs_test_base_name=`basename $ovs_test_base_url`
    local ovs_test_base_name_prefix=`echo $ovs_test_base_name | awk -F '-' '{print $1}'`
    local ovs_test_all_base_name=`echo $ovs_test_base_name | sed -e s/$ovs_test_base_name_prefix/$ovs_test_base_name_prefix-test/g`
    eval "OVS_TEST_URL=$ovs_test_base_dir/$ovs_test_all_base_name"
    echo $OVS_TEST_URL    
}
get_ovs_test_url $OVS_URL
wget -O /dev/null -q $OVS_TEST_URL && echo OVS TEST URL exists || echo OVS TEST URL not exist


DPDK_VERSION=${DPDK_VERSION:-18.11-2}
GUEST_DPDK_VERSION=${GUEST_DPDK_VERSION:-18.11-2}

function get_dpdk_and_tool_url()
{
    local rhel_ver=$1
    local dpdk_version=$2
    local base_url='http://download-node-02.eng.bos.redhat.com/brewroot/packages/dpdk/'
    local major_ver=`echo $dpdk_version | awk -F '-' '{print $1}'`
    local minor_ver=`echo $dpdk_version | awk -F '-' '{print $NF}'`
    local all_r_p=`curl -s ${base_url}/${major_ver}/ | grep -oP "(href)*(el.*)*[0-9]+\.el[0-9]+_?[0-9]?[a-zA-Z]*" | sort | uniq`
    local cur_ver_p=`echo  "$all_r_p" | grep ^${minor_ver}.el${rhel_ver}`
    local dpdk_suffix=$major_ver/${cur_ver_p}/x86_64/dpdk-${major_ver}-${cur_ver_p}.x86_64.rpm
    local dpdk_tools_suffix=$major_ver/${cur_ver_p}/x86_64/dpdk-tools-${major_ver}-${cur_ver_p}.x86_64.rpm
    temp_dpdk_url=${base_url}${dpdk_suffix}
    temp_dpdk_tool_url=${base_url}${dpdk_tools_suffix}
    eval "$3=$temp_dpdk_url"
    eval "$4=$temp_dpdk_tool_url"
}

DPDK_URL=""
DPDK_TOOL_URL=""
GUEST_DPDK_URL=""
GUEST_DPDK_TOOL_URL=""

get_dpdk_and_tool_url ${SYSTEM_VERSION:5:1} $DPDK_VERSION DPDK_URL DPDK_TOOL_URL
echo $DPDK_URL
wget -O /dev/null -q $DPDK_URL && echo DPDK URL exists || echo DPDK URL not exist
echo $DPDK_TOOL_URL
wget -O /dev/null -q $DPDK_TOOL_URL && echo DPDK TOOL URL exists || echo DPDK TOOL URL not exist

get_dpdk_and_tool_url ${SYSTEM_VERSION:5:1} $GUEST_DPDK_VERSION GUEST_DPDK_URL GUEST_DPDK_TOOL_URL

echo $GUEST_DPDK_URL
wget -O /dev/null -q $GUEST_DPDK_URL && echo GUEST DPDK URL exists || echo GUEST DPDK URL not exist
echo $GUEST_DPDK_TOOL_URL
wget -O /dev/null -q $GUEST_DPDK_TOOL_URL && echo GUEST DPDK TOOL URL exists || echo GUEST DPDK TOOL URL not exist


#here all , iperf, performance
OVS_DPDK_BOND_TEST_ITEM="all"

ixgbe_config()
{
    CONN_TYPE=netscout
    NETSCOUT_HOST=10.73.88.9
    TRAFFIC_TYPE=trex

    #TOPO PORT NAME
    SERVER_PORT_ONE=01.01.05
    SERVER_PORT_TWO=01.01.06
    CLIENT_PORT_ONE=01.01.47
    CLIENT_PORT_TWO=01.01.48
    
    SERVER_NIC1_MAC='b4:96:91:14:b0:14'
    SERVER_NIC2_MAC='b4:96:91:14:b0:16'
    CLIENT_NIC1_MAC='90:e2:ba:29:bf:14'
    CLIENT_NIC2_MAC='90:e2:ba:29:bf:15'

    if [[ $TRAFFIC_TYPE == "trex" ]]
    then
        TRAFFIC_PORT_ONE=$CLIENT_PORT_ONE
        TRAFFIC_PORT_TWO=$CLIENT_PORT_TWO
    else
        TRAFFIC_PORT_ONE=XENA_M7P0
        TRAFFIC_PORT_TWO=XENA_M7P1
    fi
    
    SWITCH_PORT_ONE=5010_Eth3
    SWITCH_PORT_TWO=5010_Eth4
    SWITCH_PORT_THREE=5010_Eth5
    SWITCH_PORT_FOUR=5010_Eth6
    SWITCH_NAME=5010
    SWITCH_PORT_NAME='Eth1/3 Eth1/4'
    SWITCH_PORT2_NAME='Eth1/5 Eth1/6'
    SW_PORT_ONE_NAME=`echo $SWITCH_PORT_NAME| awk '{print $1}'`
    SW_PORT_TWO_NAME=`echo $SWITCH_PORT_NAME| awk '{print $2}'`

    under_test_machine='dell-per730-54.rhts.eng.pek2.redhat.com,dell-per730-18.rhts.eng.pek2.redhat.com'
    local temp_machine=`echo ${under_test_machine} | tr -s ',' ' '`
    local temp_machine_list=($temp_machine)
    TREX_SERVER_IP=${temp_machine_list[1]}
    TREX_SERVER_PASSWORD=QwAo2U6GRxyNPKiZaOCx

    XENA_MODULE_INDEX=5
    XENA_MODULE_PORT=0 


}

i40e_config()
{
    CONN_TYPE=netscout
    NETSCOUT_HOST=10.73.88.9
    TRAFFIC_TYPE=trex
    #TOPO PORT NAME
    SERVER_PORT_ONE=01.01.43
    SERVER_PORT_TWO=01.01.44
    CLIENT_PORT_ONE=01.01.45
    CLIENT_PORT_TWO=01.01.46
    
    SERVER_NIC1_MAC='f8:f2:1e:02:cf:40'
    SERVER_NIC2_MAC='f8:f2:1e:02:cf:42'
    CLIENT_NIC1_MAC='68:05:ca:30:57:24'
    CLIENT_NIC2_MAC='68:05:ca:30:57:25'

    if [[ $TRAFFIC_TYPE == "trex" ]]
    then
        TRAFFIC_PORT_ONE=$CLIENT_PORT_ONE
        TRAFFIC_PORT_TWO=$CLIENT_PORT_TWO
    else
        TRAFFIC_PORT_ONE=XENA_M7P0
        TRAFFIC_PORT_TWO=XENA_M7P1
    fi
    
    SWITCH_PORT_ONE=5010_Eth3
    SWITCH_PORT_TWO=5010_Eth4
    SWITCH_PORT_THREE=5010_Eth5
    SWITCH_PORT_FOUR=5010_Eth6
    SWITCH_NAME=5010
    SWITCH_PORT_NAME='Eth1/3 Eth1/4'
    SWITCH_PORT2_NAME='Eth1/5 Eth1/6'
    SW_PORT_ONE_NAME=`echo $SWITCH_PORT_NAME| awk '{print $1}'`
    SW_PORT_TWO_NAME=`echo $SWITCH_PORT_NAME| awk '{print $2}'`


    under_test_machine='dell-per730-54.rhts.eng.pek2.redhat.com,dell-per730-55.rhts.eng.pek2.redhat.com'
    local temp_machine=`echo ${under_test_machine} | tr -s ',' ' '`
    local temp_machine_list=($temp_machine)
    TREX_SERVER_IP=${temp_machine_list[1]}
    TREX_SERVER_PASSWORD=QwAo2U6GRxyNPKiZaOCx

    XENA_MODULE_INDEX=7
    XENA_MODULE_PORT=0 
}

xl710_config()
{
    OVS_DPDK_BOND_TEST_ITEM="performance"

    CONN_TYPE=switch
    NETSCOUT_HOST=10.73.88.8
    TRAFFIC_TYPE=trex

    #TOPO PORT NAME
    SERVER_PORT_ONE=''
    SERVER_PORT_TWO=''
    CLIENT_PORT_ONE=''
    CLIENT_PORT_TWO=''
    
    SERVER_NIC1_MAC='3c:fd:fe:a0:3b:f0'
    SERVER_NIC2_MAC='3c:fd:fe:a0:3b:f1'
    CLIENT_NIC1_MAC='68:05:ca:32:3f:f0'
    CLIENT_NIC2_MAC='68:05:ca:32:3f:f1'

    if [[ $TRAFFIC_TYPE == "trex" ]]
    then
        TRAFFIC_PORT_ONE=$CLIENT_PORT_ONE
        TRAFFIC_PORT_TWO=$CLIENT_PORT_TWO
    else
        TRAFFIC_PORT_ONE=XENA_M7P0
        TRAFFIC_PORT_TWO=XENA_M7P1
    fi
    
    SWITCH_PORT_ONE=''
    SWITCH_PORT_TWO=''
    SWITCH_PORT_THREE=''
    SWITCH_PORT_FOUR=''
    SWITCH_NAME=6004
    SWITCH_PORT_NAME='Eth2/4 Eth2/5'
    SWITCH_PORT2_NAME='Eth2/10 Eth2/12'
    SW_PORT_ONE_NAME=`echo $SWITCH_PORT_NAME| awk '{print $1}'`
    SW_PORT_TWO_NAME=`echo $SWITCH_PORT_NAME| awk '{print $2}'`

    under_test_machine='dell-per730-18.rhts.eng.pek2.redhat.com,dell-per740-10.rhts.eng.pek2.redhat.com'
    local temp_machine=`echo ${under_test_machine} | tr -s ',' ' '`
    local temp_machine_list=($temp_machine)
    TREX_SERVER_IP=${temp_machine_list[1]}
    TREX_SERVER_PASSWORD=QwAo2U6GRxyNPKiZaOCx
}

mlx5_config()
{
    OVS_DPDK_BOND_TEST_ITEM="performance"
    CONN_TYPE=netscout
    NETSCOUT_HOST=10.73.88.8
    TRAFFIC_TYPE=xena

    #TOPO PORT NAME
    SERVER_PORT_ONE=01.01.07
    SERVER_PORT_TWO=01.01.08
    CLIENT_PORT_ONE=01.01.09
    CLIENT_PORT_TWO=01.01.10
    
    SERVER_NIC1_MAC='98:03:9b:2c:04:a4'
    SERVER_NIC2_MAC='98:03:9b:2c:04:a5'
    CLIENT_NIC1_MAC='98:03:9b:2c:05:74'
    CLIENT_NIC2_MAC='98:03:9b:2c:05:75'

    if [[ $TRAFFIC_TYPE == "trex" ]]
    then
        TRAFFIC_PORT_ONE=$CLIENT_PORT_ONE
        TRAFFIC_PORT_TWO=$CLIENT_PORT_TWO
    else
        TRAFFIC_PORT_ONE=01.01.21
        TRAFFIC_PORT_TWO=01.01.23
    fi

    #netscout 3200 01.01.11--------------5200-2----port22 
    #netscout 3200 01.01.12--------------5200-2----port23
    #netscout 3200 01.01.13--------------5200-2----port24 
    #netscout 3200 01.01.14--------------5200-2----port25 
    
    SWITCH_PORT_ONE=01.01.11
    SWITCH_PORT_TWO=01.01.12
    SWITCH_PORT_THREE=01.01.13
    SWITCH_PORT_FOUR=01.01.14
    SWITCH_NAME=5200-2
    SWITCH_PORT_NAME='et-0/0/22 et-0/0/23'
    SWITCH_PORT2_NAME='et-0/0/25 et-0/0/24'
    SW_PORT_ONE_NAME=`echo $SWITCH_PORT_NAME| awk '{print $1}'`
    SW_PORT_TWO_NAME=`echo $SWITCH_PORT_NAME| awk '{print $2}'`

    under_test_machine='dell-per730-18.rhts.eng.pek2.redhat.com,dell-per740-10.rhts.eng.pek2.redhat.com'
    local temp_machine=`echo ${under_test_machine} | tr -s ',' ' '`
    local temp_machine_list=($temp_machine)
    TREX_SERVER_IP=${temp_machine_list[1]}
    TREX_SERVER_PASSWORD=QwAo2U6GRxyNPKiZaOCx

    XENA_MODULE_INDEX=5
    XENA_MODULE_PORT=0    
}

nfp_config()
{
    OVS_DPDK_BOND_TEST_ITEM="iperf"
    CONN_TYPE=netscout
    NETSCOUT_HOST=10.73.88.8
    TRAFFIC_TYPE=trex

    SERVER_PORT_ONE=01.01.02
    SERVER_PORT_TWO=01.01.02-3
    #CLIENT_PORT_ONE=01.01.19-1
    #CLIENT_PORT_TWO=01.01.19-2
    CLIENT_PORT_ONE=01.01.05
    CLIENT_PORT_TWO=01.01.05-3

    SERVER_NIC1_MAC='00:15:4d:13:79:b1'
    SERVER_NIC2_MAC='00:15:4d:13:79:b1'
    #CLIENT_NIC1_MAC='3c:fd:fe:bb:1c:04'
    #CLIENT_NIC2_MAC='3c:fd:fe:bb:1c:05'
    CLIENT_NIC1_MAC='3c:fd:fe:c2:fe:b0'
    CLIENT_NIC2_MAC='3c:fd:fe:c2:fe:b1'


    if [[ $TRAFFIC_TYPE == "trex" ]]
    then
        TRAFFIC_PORT_ONE=$CLIENT_PORT_ONE
        TRAFFIC_PORT_TWO=$CLIENT_PORT_TWO
    else
        TRAFFIC_PORT_ONE=XENA_M7P0
        TRAFFIC_PORT_TWO=XENA_M7P1
    fi
    
    SWITCH_PORT_ONE=5010_Eth3
    SWITCH_PORT_TWO=5010_Eth4
    SWITCH_PORT_THREE=5010_Eth5
    SWITCH_PORT_FOUR=5010_Eth6
    SWITCH_NAME=5010
    SWITCH_PORT_NAME='Eth1/3 Eth1/4'
    SWITCH_PORT2_NAME='Eth1/5 Eth1/6'
    SW_PORT_ONE_NAME=`echo $SWITCH_PORT_NAME| awk '{print $1}'`
    SW_PORT_TWO_NAME=`echo $SWITCH_PORT_NAME| awk '{print $2}'`

    under_test_machine='dell-per730-55.rhts.eng.pek2.redhat.com,dell-per730-18.rhts.eng.pek2.redhat.com'
    local temp_machine=`echo ${under_test_machine} | tr -s ',' ' '`
    local temp_machine_list=($temp_machine)
    TREX_SERVER_IP=${temp_machine_list[1]}
    TREX_SERVER_PASSWORD=QwAo2U6GRxyNPKiZaOCx

    XENA_MODULE_INDEX=5
    XENA_MODULE_PORT=0 
}


broadcom_config()
{
    OVS_DPDK_BOND_TEST_ITEM="iperf"
    CONN_TYPE=netscout
    NETSCOUT_HOST=10.73.88.8
    TRAFFIC_TYPE=trex
    #TOPO PORT NAME
    SERVER_PORT_ONE=01.01.06
    SERVER_PORT_TWO=01.01.06-3
    CLIENT_PORT_ONE=01.01.05
    CLIENT_PORT_TWO=01.01.05-3
    
    SERVER_NIC1_MAC='00:10:18:ad:1f:20'
    SERVER_NIC2_MAC='00:10:18:ad:1f:21'
    CLIENT_NIC1_MAC='3c:fd:fe:c2:fe:b0'
    CLIENT_NIC2_MAC='3c:fd:fe:c2:fe:b1'

    if [[ $TRAFFIC_TYPE == "trex" ]]
    then
        TRAFFIC_PORT_ONE=$CLIENT_PORT_ONE
        TRAFFIC_PORT_TWO=$CLIENT_PORT_TWO
    else
        TRAFFIC_PORT_ONE=XENA_M7P0
        TRAFFIC_PORT_TWO=XENA_M7P1
    fi
    
    SWITCH_PORT_ONE=5010_Eth3
    SWITCH_PORT_TWO=5010_Eth4
    SWITCH_PORT_THREE=5010_Eth5
    SWITCH_PORT_FOUR=5010_Eth6
    SWITCH_NAME=5010
    SWITCH_PORT_NAME='Eth1/3 Eth1/4'
    SWITCH_PORT2_NAME='Eth1/5 Eth1/6'
    SW_PORT_ONE_NAME=`echo $SWITCH_PORT_NAME| awk '{print $1}'`
    SW_PORT_TWO_NAME=`echo $SWITCH_PORT_NAME| awk '{print $2}'`


    under_test_machine='dell-per740-10.rhts.eng.pek2.redhat.com,dell-per730-18.rhts.eng.pek2.redhat.com'
    local temp_machine=`echo ${under_test_machine} | tr -s ',' ' '`
    local temp_machine_list=($temp_machine)
    TREX_SERVER_IP=${temp_machine_list[1]}
    TREX_SERVER_PASSWORD=QwAo2U6GRxyNPKiZaOCx
        
    XENA_MODULE_INDEX=7
    XENA_MODULE_PORT=0  
}

xxv_config()
{
    OVS_DPDK_BOND_TEST_ITEM="iperf"
    CONN_TYPE=netscout
    NETSCOUT_HOST=10.73.88.8
    TRAFFIC_TYPE=trex
    #TOPO PORT NAME
    SERVER_PORT_ONE=01.01.05
    SERVER_PORT_TWO=01.01.05-3
    CLIENT_PORT_ONE=01.01.06
    CLIENT_PORT_TWO=01.01.06-3
    
    SERVER_NIC1_MAC='3c:fd:fe:c2:fe:b0'
    SERVER_NIC2_MAC='3c:fd:fe:c2:fe:b1'
    CLIENT_NIC1_MAC='00:10:18:ad:1f:20'
    CLIENT_NIC2_MAC='00:10:18:ad:1f:21'

    if [[ $TRAFFIC_TYPE == "trex" ]]
    then
        TRAFFIC_PORT_ONE=$CLIENT_PORT_ONE
        TRAFFIC_PORT_TWO=$CLIENT_PORT_TWO
    else
        TRAFFIC_PORT_ONE=XENA_M7P0
        TRAFFIC_PORT_TWO=XENA_M7P1
    fi
    
    SWITCH_PORT_ONE=5010_Eth3
    SWITCH_PORT_TWO=5010_Eth4
    SWITCH_PORT_THREE=5010_Eth5
    SWITCH_PORT_FOUR=5010_Eth6
    SWITCH_NAME=5010
    SWITCH_PORT_NAME='Eth1/3 Eth1/4'
    SWITCH_PORT2_NAME='Eth1/5 Eth1/6'
    SW_PORT_ONE_NAME=`echo $SWITCH_PORT_NAME| awk '{print $1}'`
    SW_PORT_TWO_NAME=`echo $SWITCH_PORT_NAME| awk '{print $2}'`


    under_test_machine='dell-per730-18.rhts.eng.pek2.redhat.com,dell-per740-10.rhts.eng.pek2.redhat.com'
    local temp_machine=`echo ${under_test_machine} | tr -s ',' ' '`
    local temp_machine_list=($temp_machine)
    TREX_SERVER_IP=${temp_machine_list[1]}
    TREX_SERVER_PASSWORD=QwAo2U6GRxyNPKiZaOCx
        
    XENA_MODULE_INDEX=7
    XENA_MODULE_PORT=0  
}

qede_config()
{
    OVS_DPDK_BOND_TEST_ITEM="iperf"
    CONN_TYPE=netscout
    NETSCOUT_HOST=10.73.88.8
    TRAFFIC_TYPE=trex

    #SERVER_PORT_ONE=01.01.15-3
    #SERVER_PORT_TWO=01.01.15-4
    SERVER_PORT_ONE=01.01.28-1
    SERVER_PORT_TWO=01.01.28-3

    #CLIENT_PORT_ONE=01.01.19-1
    #CLIENT_PORT_TWO=01.01.19-2
    CLIENT_PORT_ONE=01.01.05
    CLIENT_PORT_TWO=01.01.05-3


    # SERVER_NIC1_MAC='00:0e:1e:d3:f1:b2'
    # SERVER_NIC2_MAC='00:0e:1e:d3:f1:b3'
    SERVER_NIC1_MAC='f4:e9:d4:09:07:62'
    SERVER_NIC2_MAC='f4:e9:d4:09:07:63'

    #CLIENT_NIC1_MAC='3c:fd:fe:bb:1c:04'
    #CLIENT_NIC2_MAC='3c:fd:fe:bb:1c:05'
    CLIENT_NIC1_MAC='3c:fd:fe:c2:fe:b0'
    CLIENT_NIC2_MAC='3c:fd:fe:c2:fe:b1'

    if [[ $TRAFFIC_TYPE == "trex" ]]
    then
        TRAFFIC_PORT_ONE=$CLIENT_PORT_ONE
        TRAFFIC_PORT_TWO=$CLIENT_PORT_TWO
    else
        TRAFFIC_PORT_ONE=XENA_M7P0
        TRAFFIC_PORT_TWO=XENA_M7P1
    fi
    
    SWITCH_PORT_ONE=5010_Eth3
    SWITCH_PORT_TWO=5010_Eth4
    SWITCH_PORT_THREE=5010_Eth5
    SWITCH_PORT_FOUR=5010_Eth6
    SWITCH_NAME=5010
    SWITCH_PORT_NAME='Eth1/3 Eth1/4'
    SWITCH_PORT2_NAME='Eth1/5 Eth1/6'
    SW_PORT_ONE_NAME=`echo $SWITCH_PORT_NAME| awk '{print $1}'`
    SW_PORT_TWO_NAME=`echo $SWITCH_PORT_NAME| awk '{print $2}'`

    under_test_machine='dell-per730-55.rhts.eng.pek2.redhat.com,dell-per730-18.rhts.eng.pek2.redhat.com'
    local temp_machine=`echo ${under_test_machine} | tr -s ',' ' '`
    local temp_machine_list=($temp_machine)
    TREX_SERVER_IP=${temp_machine_list[1]}
    TREX_SERVER_PASSWORD=QwAo2U6GRxyNPKiZaOCx

    XENA_MODULE_INDEX=5
    XENA_MODULE_PORT=0 

}

enic_config()
{
    CONN_TYPE=netscout
    NETSCOUT_HOST=10.73.88.8
    #TRAFFIC_TYPE=xena
    TRAFFIC_TYPE=trex
    TREX_SERVER_IP=dell-per730-54.rhts.eng.pek2.redhat.com
    TREX_SERVER_PASSWORD=QwAo2U6GRxyNPKiZaOCx
    #TOPO PORT NAME
    #TRAFFIC_PORT=XENA_M7P0
    SERVER_PORT_ONE=CISCO_enp9s0
    SERVER_PORT_TWO=CISCO_enp10s0
    CLIENT_PORT_ONE=01.01.07
    CLIENT_PORT_TWO=01.01.08
    TRAFFIC_PORT=$CLIENT_PORT_ONE

    #here need fix
    SWITCH_PORT_ONE=5010_Eth1
    SWITCH_PORT_TWO=5010_Eth4
    SWITCH_PORT_THREE=5010_Eth3
     SWITCH_PORT_FOUR=5010_Eth6
    SWITCH_NAME=5010
    SWITCH_PORT_NAME='Eth1/3 Eth1/4'
    SWITCH_PORT2_NAME='Eth1/5 Eth1/6'
    SW_PORT_ONE_NAME=`echo $SWITCH_PORT_NAME| awk '{print $1}'`
    SW_PORT_TWO_NAME=`echo $SWITCH_PORT_NAME| awk '{print $2}'`

    SERVER_NIC1_MAC='70:7d:b9:30:d0:3c'
    SERVER_NIC2_MAC='70:7d:b9:30:d0:3d'
    CLIENT_NIC1_MAC='b4:96:91:14:b0:14'
    CLIENT_NIC2_MAC='b4:96:91:14:b0:16'

    under_test_machine='cisco-c220m4-01.rhts.eng.pek2.redhat.com,dell-per730-54.rhts.eng.pek2.redhat.com'
}

case "$NIC_DRIVER" in
    "ixgbe")
        echo "ixgbe"
        ixgbe_config
        ;;
    "i40e")
        echo "i40e"
        i40e_config
        ;;
    "xl710")
        echo "i40e 40G test"
        xl710_config
        ;;
    "nfp")
        echo "NFP 25G card test "
        nfp_config
        ;;
    "mlx5_core")
        echo "mlx5_core"
        mlx5_config
        ;;
    "broadcom")
        echo "broadcom 25G Test"
        broadcom_config
        ;;

    "xxv")
        echo "xxv 25G Test"
        xxv_config
        ;;
    "qede")
        echo "QLogic Test 25G"
        qede_config
        ;;
    "enic")
        echo "Cisco Nic Test"
        enic_config
        ;;
    
esac

manual_test()
{
    set -x
    modprobe -r bonding 
    local temp_machine=`echo ${under_test_machine} | tr -s ',' ' '`
    local temp_machine_list=($temp_machine)

    systemctl start openvswitch
    ovs-vsctl --if-exists del-br ovsbrup
	ovs-vsctl --if-exists del-br ovsbr0    
    systemctl stop openvswitch

    local hugepage_dir=`mount -l | grep hugetlbfs | awk '{print $3}'`
    rm -rf $hugepage_dir/*

    killall t-rex-64
    killall t-rex-64
    killall _t-rex-64
    killall _t-rex-64

    bus_list=`dpdk-devbind -s | grep  -E drv=vfio-pci\|drv=igb | awk '{print $1}'`
    for i in $bus_list
    do
        kernel_driver=`lspci -s $i -v | grep Kernel  | grep modules  | awk '{print $NF}'`
        dpdk-devbind -b $kernel_driver $i
        driverctl unset-override $i
    done

    virsh destroy guest30032
    virsh undefine guest30032

    export NAY=yes
    export NIC_DRIVER=${NIC_DRIVER}
    export SYSTEM_VERSION=${SYSTEM_VERSION}
    export version=${version}
    export IMG_GUEST=${IMAGE_GUEST}
    export BOND_TEST_MODE=${BOND_TEST_MODE}
    export DRIVERCTL_URL=${DRIVERCTL_URL}
    export CONTAINER_SELINUX_URL=${CONTAINER_SELINUX_URL}
    export OVS_SELINUX_URL=${OVS_SELINUX_URL}
    export OVS_URL=${OVS_URL}
    export PYTHON_OVS_URL=${PYTHON_OVS_URL}
    export OVS_TEST_URL=${OVS_TEST_URL}
    export DPDK_URL=${DPDK_URL}
    export DPDK_TOOL_URL=${DPDK_TOOL_URL}
    export DPDK_VERSION=${DPDK_VERSION}
    export GUEST_DPDK_VERSION=${GUEST_DPDK_VERSION}
    export GUEST_DPDK_URL=${GUEST_DPDK_URL}
    export GUEST_DPDK_TOOL_URL=${GUEST_DPDK_TOOL_URL}
    export CONN_TYPE=${CONN_TYPE}
    export NETSCOUT_HOST=${NETSCOUT_HOST}
    export TRAFFIC_TYPE=${TRAFFIC_TYPE}
    export TREX_SERVER_IP=${TREX_SERVER_IP}
    export TREX_SERVER_PASSWORD=${TREX_SERVER_PASSWORD}
    #TOPO PORT NAME
    export TRAFFIC_PORT_ONE=${TRAFFIC_PORT_ONE}
    export TRAFFIC_PORT_TWO=${TRAFFIC_PORT_TWO}
    export SERVER_PORT_ONE=${SERVER_PORT_ONE}
    export SERVER_PORT_TWO=${SERVER_PORT_TWO}
    export SWITCH_PORT_ONE=${SWITCH_PORT_ONE}
    export SWITCH_PORT_TWO=${SWITCH_PORT_TWO}
    export SWITCH_PORT_THREE=${SWITCH_PORT_THREE}
    export SWITCH_PORT_FOUR=${SWITCH_PORT_FOUR}
    export CLIENT_PORT_ONE=${CLIENT_PORT_ONE}
    export CLIENT_PORT_TWO=${CLIENT_PORT_TWO}
    export SWITCH_NAME=${SWITCH_NAME}
    export SWITCH_PORT_NAME="${SWITCH_PORT_NAME}"
    export SW_PORT_ONE_NAME=${SW_PORT_ONE_NAME}
    export SW_PORT_TWO_NAME=${SW_PORT_TWO_NAME}
    export SWITCH_PORT2_NAME="${SWITCH_PORT2_NAME}"
    export SERVER_NIC1_MAC=${SERVER_NIC1_MAC}
    export SERVER_NIC2_MAC=${SERVER_NIC2_MAC}
    export CLIENT_NIC1_MAC=${CLIENT_NIC1_MAC}
    export CLIENT_NIC2_MAC=${CLIENT_NIC2_MAC}

    export SERVERS=${temp_machine_list[0]}
    export CLIENTS=${temp_machine_list[1]}

    export TREX_URL=${TREX_URL}

    export OVS_DPDK_BOND_TEST_ITEM=${OVS_DPDK_BOND_TEST_ITEM}
    export XENA_CONFIG_FILE=${XENA_CONFIG_FILE}

    export XENA_MODULE_INDEX=${XENA_MODULE_INDEX}
    export XENA_MODULE_PORT=${XENA_MODULE_PORT}    
    
    set +x
}

#	--Scratch="http://netqe-bj.usersys.redhat.com/share/wanghekai/bug1677507/64-kernel/" \
func_test()
{
	set -x
    local temp_machine=`echo ${under_test_machine} | tr -s ',' ' '`
    local temp_machine_list=($temp_machine)
    local white_board="FD NIC PARTITION FOR BONDING | ${NIC_DRIVER} | `date` | "
    white_board=$white_board" $under_test_machine |"
    white_board=$white_board" $version |"
    local ovs_version=`basename $OVS_URL`
    local dpdk_version=`basename $DPDK_URL`
    white_board=$white_board" ovs version $ovs_version |"
    white_board=$white_board" host dpdk version $dpdk_version |"
    white_board=$white_board" image url $IMAGE_GUEST|"
    white_board=$white_board" $GUEST_DPDK_URL|"
    white_board=$white_board" $GUEST_DPDK_TOOL_URL|"
    white_board=$white_board" guest dpdk verison `basename $GUEST_DPDK_URL` |"

    temp_varient=server
    echo $version | grep "RHEL-8" && temp_varient=BaseOS
    echo $temp_varient

    lstest | runtest ${version} --machine=${under_test_machine} --wb="$white_board" \
        --param=NIC_DRIVER=${NIC_DRIVER} \
        --param=SYSTEM_VERSION=${SYSTEM_VERSION} \
        --param=version=${version} \
        --param=IMG_GUEST=${IMAGE_GUEST} \
        --param=BOND_TEST_MODE=${BOND_TEST_MODE} \
        --param=DRIVERCTL_URL=${DRIVERCTL_URL} \
        --param=CONTAINER_SELINUX_URL=${CONTAINER_SELINUX_URL} \
        --param=OVS_SELINUX_URL=${OVS_SELINUX_URL} \
        --param=OVS_URL=${OVS_URL} \
        --param=PYTHON_OVS_URL=${PYTHON_OVS_URL} \
        --param=OVS_TEST_URL=${OVS_TEST_URL} \
        --param=DPDK_URL=${DPDK_URL} \
        --param=DPDK_TOOL_URL=${DPDK_TOOL_URL} \
        --param=DPDK_VERSION=${DPDK_VERSION} \
        --param=GUEST_DPDK_VERSION=${GUEST_DPDK_VERSION} \
        --param=GUEST_DPDK_URL=${GUEST_DPDK_URL} \
        --param=GUEST_DPDK_TOOL_URL=${GUEST_DPDK_TOOL_URL} \
        --param=CONN_TYPE=${CONN_TYPE} \
        --param=NETSCOUT_HOST=${NETSCOUT_HOST} \
        --param=TRAFFIC_TYPE=${TRAFFIC_TYPE} \
        --param=TREX_SERVER_IP=${TREX_SERVER_IP} \
        --param=TREX_SERVER_PASSWORD=${TREX_SERVER_PASSWORD} \
        --param=TRAFFIC_PORT_ONE=${TRAFFIC_PORT_ONE} \
        --param=TRAFFIC_PORT_TWO=${TRAFFIC_PORT_TWO} \
        --param=SERVER_PORT_ONE=${SERVER_PORT_ONE} \
        --param=SERVER_PORT_TWO=${SERVER_PORT_TWO} \
        --param=SWITCH_PORT_ONE=${SWITCH_PORT_ONE} \
        --param=SWITCH_PORT_TWO=${SWITCH_PORT_TWO} \
        --param=SWITCH_PORT_THREE=${SWITCH_PORT_THREE} \
        --param=SWITCH_PORT_FOUR=${SWITCH_PORT_FOUR} \
        --param=CLIENT_PORT_ONE=${CLIENT_PORT_ONE} \
        --param=CLIENT_PORT_TWO=${CLIENT_PORT_TWO} \
        --param=SWITCH_NAME=${SWITCH_NAME} \
        --param=SWITCH_PORT_NAME="${SWITCH_PORT_NAME}" \
        --param=SW_PORT_ONE_NAME=${SW_PORT_ONE_NAME} \
        --param=SW_PORT_TWO_NAME=${SW_PORT_TWO_NAME} \
        --param=SWITCH_PORT2_NAME="${SWITCH_PORT2_NAME}" \
        --param=SERVER_NIC1_MAC=${SERVER_NIC1_MAC} \
        --param=SERVER_NIC2_MAC=${SERVER_NIC2_MAC} \
        --param=CLIENT_NIC1_MAC=${CLIENT_NIC1_MAC} \
        --param=CLIENT_NIC2_MAC=${CLIENT_NIC2_MAC} \
        --param=SERVERS=${temp_machine_list[0]} \
        --param=CLIENTS=${temp_machine_list[1]} \
        --param=NAY=yes \
        --param=NIC_DRIVER=${NIC_DRIVER} \
        --param=TREX_URL=${TREX_URL} \
        --param=OVS_DPDK_BOND_TEST_ITEM=${OVS_DPDK_BOND_TEST_ITEM} \
        --param=XENA_CONFIG_FILE=${XENA_CONFIG_FILE} \
        --param=XENA_MODULE_INDEX=${XENA_MODULE_INDEX} \
        --param=XENA_MODULE_PORT=${XENA_MODULE_PORT} \
        --variant=$temp_varient \
        --systype=Machine \
        --random=true \
        --ks-meta="method=nfs" \
        --kernel-options="kpti" \
        --kernel-options-post="kpti" \
        --kdump \
        --topo=multiHost.1.1 \
	--noavc
    set +x
}

#--Scratch="http://netqe-bj.usersys.redhat.com/share/wanghekai/bug1677507/" \
do_func_test()
{
    func_test
}

do_func_test
