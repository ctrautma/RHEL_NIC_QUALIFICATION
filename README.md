# Red Hat NIC NFV Qualification

# Ansible branch for RHEL 8.0 only.

The goal of this document is to guide you step by step through the process of
qualifying a NIC driver for NFV usage. This includes both the Linux Kernel
driver and the DPDK PMD driver.

IT IS CRITICAL for qualification to keep all logs and to execute the collection
script at the end of these tests. The collection script must be run on the
server and client side. Please see the end of this file for further details.

The QE Scripts are three separate scripts that all must pass.

- The VSPerf based performance test
- Custom Physical to Virtual back to Physical(PVP) test script, _ovs\_perf_
- OVS functional qualification


The performance based tests use an upstream project called VSPerf from OPNFV to
test performance using very basic flows rules and parameters. This is broken
into two scripts, the first script will test phy2phy, and PVP scenarios. The
second script requires SR-IOV to be enabled on the NICs in test.

The ovs_perf script is also an upstream project, which will give details on
performance and CPU usage. It also produces graphs which can be used to see if
the NIC behaves according to the customers quoted specifications. We will run
a series of these tests, which in total will run for about two days. This will
include testing of both the Linux Kernel and DPDK datapath.

The functional test script runs a plethora of tests to verify NICs pass
functional requirements.


The performance based tests (_VSPerf_ and _ovs\_perf_) require two servers.
One server will have TREX installed, the other will be a clean install system
running RHEL 7.5 or greater. The servers should be wired back to back from the
test NICs to the output NICs of the T-Rex server. These tests use two NIC ports
on the DUT and two ports on the T-Rex which are connected as shown below.
The two NIC ports on the DUT must be the brand and type of NICs which are to be
qualified. The first set of performance tests use a topology as seen below.


```_
       +---------------------------------------------------+  |
       |                                                   |  |
       |   +-------------------------------------------+   |  |
       |   |                 Application               |   |  |
       |   +-------------------------------------------+   |  |
       |       ^                                  :        |  |
       |       |                                  |        |  |  Guest
       |       :                                  v        |  |
       |   +---------------+           +---------------+   |  |
       |   | logical port 0|           | logical port 1|   |  |
       +---+---------------+-----------+---------------+---+ _|
               ^                                  :
               |                                  |
               :                                  v         _
       +---+---------------+----------+---------------+---+  |
       |   | logical port 0|          | logical port 1|   |  |
       |   +---------------+          +---------------+   |  |
       |       ^                                  :       |  |
       |       |                                  |       |  |  Host
       |       :                                  v       |  |
       |   +--------------+            +--------------+   |  |
       |   |   phy port   |  vSwitch   |   phy port   |   |  |
       +---+--------------+------------+--------------+---+ _|
                  ^                           :
                  |                           |
                  :                           v
       +--------------------------------------------------+
       |                                                  |
       |                traffic generator                 |
       |                                                  |
       +--------------------------------------------------+
```

All traffic on these tests are bi-directional and the results are calculated as a total of the
sum of both ports in frames per second.


## Setting up for Ansible script execution

First make sure both the Trex server and the DUT have their Red Hat subscriptions setup with your credentials to be
able to pull the repos correctly.

The Ansible scripts are located in ansible folder of this github project. Each of the PVP setups below can be
automated using the Ansible scripts so the manual steps can be ignored.  To properly run the Ansible scripts
the configuration files must be completed.

The configuration files are as follows

ansible.cfg
inventory
test_settings.yml

The changes required to make the scripts work is as follows.

# inventory file

Modify the trex and dut sections to reflect the system hostnames or ip addresses that are to be used for the test.

# test_settings.yml

In this file go through each setting and modify them as noted by the notes in the file.  It is imperative these are
done correctly for the scripts to work correctly in the setup.

For your redhat subscription password you have two options.  One option is to store it in the file in clear text.
If this is not desired you can use Ansible-vault to encrypt your password by doing the following.

Type in the command where password is your subscription password.
    ansible-vault encrypt_string --ask-vault-pass "password"

When prompted for a vault password you can use the same password as your subscription password.

You will get an output such as

    !vault |
          $ANSIBLE_VAULT;1.1;AES256
          34653862363363663232616338393231363136326164353731383036396439626434376335323936
          3134633465353832316165653634323936336665373462650a386239343164316234636661306630
          35373538633338323032303062303265396239663836373461646339356538643633633538336135
          6565616466613562320a363764643565326564633665353765653332666237363366613636353831
          3861

Copy this into your settings file under the rh_sub_pass var

rh_sub_pass: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          34653862363363663232616338393231363136326164353731383036396439626434376335323936
          3134633465353832316165653634323936336665373462650a386239343164316234636661306630
          35373538633338323032303062303265396239663836373461646339356538643633633538336135
          6565616466613562320a363764643565326564633665353765653332666237363366613636353831
          3861

Then whenever you run one of the ansible scripts make sure to supply the argument --ask-vault-pass and supply the same
password when prompted.  This way your password is stored only in history and not in an actual clear text file stored
on the system.

Even though you did this on the bare-metal systems we have to setup the subscription credentials inside of the virtual
image used for testing.  This is why this info must be supplied.

Once the settings are complete you will need to use a remote system to execute the scripts on the DUT and trex server.
You will need to setup keyless ssh login from your remote system to those test servers.  In a usual case this is done
from another Linux server which can talk to the other servers. The reason is the scripts will usually have to perform a
reboot which means the script would be interrupted and have to be executed again after to complete.  Using a remote
system allows for the script to run from start to finish in one pass.

In my case I use my work laptop which would go something like this.

    ctrautma@ctrautma ~/Downloads :( $ sudo ssh-keygen -b 2048 -t rsa
    [sudo] password for ctrautma:
    Generating public/private rsa key pair.
    Enter file in which to save the key (/root/.ssh/id_rsa):
    /root/.ssh/id_rsa already exists.
    Overwrite (y/n)? y
    Enter passphrase (empty for no passphrase):
    Enter same passphrase again:
    Your identification has been saved in /root/.ssh/id_rsa.
    Your public key has been saved in /root/.ssh/id_rsa.pub.
    The key fingerprint is:
    SHA256:wCsxim7WqvxAazIL4J2bl7Y1YuA7Qxul61+nw9Krnw8 root@ctrautma.bos.csb
    The key's randomart image is:
    +---[RSA 2048]----+
    |                 |
    |     .           |
    |    o o          |
    | . . + o         |
    |o...+ . S        |
    |= =+o.           |
    |+O.=+o+E .       |
    |Boo===++*        |
    |+oo**+==+.       |
    +----[SHA256]-----+


Now that I have generated a key I need to setup the access to the remote systems

    ctrautma@ctrautma ~/Downloads $ sudo ssh-copy-id root@10.19.15.11
    /bin/ssh-copy-id: INFO: Source of key(s) to be installed: "/root/.ssh/id_rsa.pub"
    The authenticity of host '10.19.15.11 (10.19.15.11)' can't be established.
    ECDSA key fingerprint is SHA256:g1nCqteynH4G8bG1JPbKDlWHzBvqtHk10i+pZKgZChk.
    ECDSA key fingerprint is MD5:d7:62:ae:e5:dd:42:97:db:a6:37:1e:f4:37:8e:83:48.
    Are you sure you want to continue connecting (yes/no)? yes
    /bin/ssh-copy-id: INFO: attempting to log in with the new key(s), to filter out any that are already installed
    /bin/ssh-copy-id: INFO: 1 key(s) remain to be installed -- if you are prompted now it is to install the new keys
    root@10.19.15.11's password:

    Number of key(s) added: 1

    Now try logging into the machine, with:   "ssh 'root@10.19.15.11'"
    and check to make sure that only the key(s) you wanted were added.

    ctrautma@ctrautma ~/Downloads $

If you get an error when trying to copy the file you will have to remove your entry from the /root/.ssh/known_hosts
file that corresponds to the remote system on your system you are running the commands from.

You must install Ansible on your system that will run the Ansible scripts.  Unfortunately the linux distros may not
automatically pull a high enough version for the scripts to work so follow the steps below to install a later version
of Ansible.

    sudo yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    sudo yum update https://releases.ansible.com/ansible/rpm/release/epel-7-x86_64/ansible-2.8.0-1.el7.ans.noarch.rpm

Version 2.8.0.1 or above should work with all of the Ansible scripts.

After all of these things are complete login into each system to make sure your access works, then proceed to each
section below and use the corresponding script.  The scripts only do the setup of the environments.  You will still
be required to run the PVP test script to start the test after.

If errors are seen and the Ansible script fails,  please check the config file.  If everything looks OK and you think
its a script issue please contact Red Hat PFT team at redhat-pft@redhat.com

Please be aware that the scripts must be run in order.  You cannot run the kernel script without running the ovs-dpdk
script first.  They are designed to be executed in order.  If you want to run just the kernel setup,  you must run
the ovs-dpdk script,  then move on to the kernel script.  Then you can run the test for Kernel PVP.

Also if the ovs-dpdk script fails at any point, you will have to stop the openvswitch server and unbind the nic to
restart the script if it completed a few steps.

## Download the guest image

Please visit https://access.redhat.com/downloads/content/69/ver=/rhel---7/7.0/x86_64/product-software and use the
combo boxes to select the correct guest image for use with the tests.  For example for 7.7 you would select 7.7 in the
version and then select Red Hat Enterprise Linux Fast Datapath from the Product Variant.  Save this to the DUT
as the Ansible script will use it for the test setup.  You will need to modify the trex_settings.yml file to specify
where this was saved.

For other streams such as 8.0 you just need to change the link to find 8.0 images

https://access.redhat.com/downloads/content/479/ver=/rhel---8/8.0/x86_64/product-software

## Setup the TRex traffic generator

Use the Ansible script trex_setup.yml to setup the trex server system.

    sudo ansible-playbook trex_setup.yml

For manual instructions please refer to [_ovs\_perf_ script documentation](https://github.com/chaudron/ovs_perf/tree/RHEL8#setup-the-trex-traffic-generator) on how to configure the TRex traffic generator.

## Setup the Device Under Test (DUT), Open vSwitch
<a name="DUTsetup"/>

Use the Ansible script pvp_ovsdpdk.yml to setup the DUT for the OVS-dpdk PVP test

    sudo ansible-playbook pvp_ovsdpdk.yml

Please note the last step will display the VM IP address in a long message that you will need to read through to find
the IP.  This is to be cleaned up and will be fixed later.  The VM IP is needed to run the test script below.

For manual instructions please refer to  [_ovs\_perf_ script documentation](https://github.com/chaudron/ovs_perf/tree/RHEL8#setup-the-device-under-test-dut-open-vswitch) on how to configure the DUT for OVS. Follow the above-linked chapter and stop at the [Running the PVP script](https://github.com/chaudron/ovs_perf/tree/RHEL8#running-the-pvp-script) chapter, and continue below.

### Running the PVP script

Now we are all set to run the PVP script. We move back to the TRex host as we
use this to execute the script.

Before we start we need to set the back-end to not use a GUI and create
a directory to store the results:

```
echo export MPLBACKEND="agg" >> ~/.bashrc
source ~/.bashrc
mkdir ~/pvp_results
cd ~/pvp_results/
```

Now we can do a quick 64 bytes packet run with 1000 flows to verify everything
has been set up correctly.

__NOTE:__ The PVP script assumes both machines are directly attached, i.e.
there is no switch in between. If you do have a switch in between the best
option is to disable learning. If this is not possible you need to use the
--mac-swap option. This will swap the MAC addresses on the VM side, so the
switch in the middle does not get confused.

For details on the supported PVP script options, see the
[ovs_performance.py Supported Options](#options) chapter.

```
# ~/ovs_perf/ovs_performance.py \
  -d -l testrun_log.txt \              # Enable script debugging, and save the output to testrun_log.txt
  --tester-type trex \                 # Set tester type to TRex
  --tester-address localhost \         # IP address of the TRex server
  --tester-interface 0 \               # Interface number used on the TRex
  --ovs-address 10.19.17.133 \         # DUT IP address
  --ovs-user root \                    # DUT login user name
  --ovs-password root \                # DUT login user password
  --dut-vm-address 192.168.122.5 \     # Address on which the VM is reachable, see above
  --dut-vm-user root \                 # VM login user name
  --dut-vm-password root \             # VM login user password
  --dut-vm-nic-queues=2 \              # Number of rx/tx queues to use on the VM
  --physical-interface dpdk0 \         # OVS Physical interface, i.e. connected to TRex
  --physical-speed=10 \                # Speed of the physical interface, for DPDK we can not detect it reliably
  --virtual-interface vhost0 \         # OVS Virtual interface, i.e. connected to the VM
  --dut-vm-nic-pci=0000:00:02.0 \      # PCI address of the interface in the VM
  --packet-list=64 \                   # Comma separated list of packets to test with
  --stream-list=1000 \                 # Comma separated list of number of flows/streams to test with
  --no-bridge-config \                 # Do not configure the OVS bridge, assume it's already done (see above)
  --skip-pv-test                       # Skip the Physical to Virtual test

- Connecting to the tester...
- Connecting to DUT, "10.19.17.133"...
- Stop any running test tools...
- Get OpenFlow and DataPath port numbers...
- Get OVS datapath type, "netdev"...
- Create "test_results.csv" for writing results...
- [TEST: test_p2v2p(flows=1000, packet_size=64)] START
  * Create OVS OpenFlow rules...
  * Clear all OpenFlow/Datapath rules on bridge "ovs_pvp_br0"...
  * Create 1000 L3 OpenFlow rules...
  * Create 1000 L3 OpenFlow rules...
  * Verify requested number of flows exists...
  * Initializing packet generation...
  * Clear all statistics...
  * Start packet receiver on VM...
  * Start CPU monitoring on DUT...
  * Start packet generation for 20 seconds...
  * Stop CPU monitoring on DUT...
  * Stopping packet stream...
  * Stop packet receiver on VM...
  * Gathering statistics...
    - Packets send by Tester      :          270,574,060
    - Packets received by physical:           44,172,736 [Lost 226,401,324, Drop 226,401,324]
    - Packets received by virtual :           44,172,290 [Lost 446, Drop 446]
    - Packets send by virtual     :           44,171,170 [Lost 1,120, Drop 0]
    - Packets send by physical    :           44,171,170 [Lost 0, Drop 0]
    - Packets received by Tester  :           44,171,170 [Lost 0]
    - Receive rate on VM: 2,319,236 pps
  ! Result, average: 2,254,424.93125 pps
  * Restoring state for next test...
- [TEST: test_p2v2p(flows=1000, packet_size=64)] END
- Done running performance tests!

```

If this is successful we can go ahead and do a full run. This will roughly take
a day to finish. For more details and background information on this see the
[_ovs\_perf_](https://github.com/chaudron/ovs_perf/tree/RHEL8/README.md#full-day-pvp-test)
documentation. This is done running the included __runfullday.sh__ script.

```
$./runfullday.sh
This script will run the tests as explained in the "Full day PVP test"
section. It will start the scripts according to the configuration given below,
and will archive the results.

NOTE: Make sure you are passing the basic test as explained in "Running the
      PVP script" before starting the full day run!

What datapath are you using, DPDK or Linux Kernel [dpdk/kernel/tc]? dpdk
What is the IP address where the DUT (Open vSwitch) is running? 10.19.17.133
What is the root password of the DUT? root
What is the IP address of the virtual machine running on the DUT? 192.168.122.186
What is the root password of the VM (default: root)? root
What is the IP address of the TRex tester? localhost
What is the physical interface being used, i.e. dpdk0, em1, p4p5? dpdk0
What is the virtual interface being used, i.e. vhost0, vnet0? vhost0
What is the virtual interface PCI id? 0000:00:06.0
Enter the Number of VM nic receive descriptors, 4096(default)? 4096
Enter the Number of Number of VM nic transmit descriptors, 1024(default)? 1024
What is the TRex tester physical interface being used? 0
What is the link speed of the physical interface, i.e. 10(default),25,40,50,100? 10
Enter L2/L3 streams list. default(10,1000,10000,100000,1000000)? 10,1000,10000,100000,1000000
- Connecting to the tester...
- Connecting to DUT, "10.19.17.133"...
...
...
=================================================================================
== ALL TESTS ARE DONE                                                         ===
=================================================================================

 Please verify all the results and make sure they are within the expected
 rates for the blade!!

=================================================================================
All tests are done, results are saved in: "/root/pvp_results_2017-10-12_055506.tgz"
```



## Running the _ovs\_perf_ script for the Linux Kernel datapath

With the above setup, we ran the PVP tests with the Open vSwitch DPDK datapath.
This section assumes you have the previous configuration running, and explains
the steps to convert it to a Linux datapath setup.

### Configuring the Linux Kernel datapath

Run the Ansible script pvp_kernel.yml

    sudo ansible-playbook pvp_kernel.yml

For manual steps refer to  [_ovs\_perf_ script documentation](https://github.com/chaudron/ovs_perf/tree/RHEL8#open-vswitch-with-linux-kernel-datapath)


### Run the PVP performance script

The PVP script should now work as before with some slide changes to the
interfaces being used. Below is the same _quick 64 bytes packet run with 1000
flows_ as ran before on the DPDK datapath:

```
# cd ~/pvp_results
# ~/ovs_perf/ovs_performance.py \
  -d -l testrun_log.txt \
  --tester-type trex \
  --tester-address localhost \
  --tester-interface 0 \
  --ovs-address 10.19.17.133 \
  --ovs-user root \
  --ovs-password root \
  --dut-vm-address 192.168.122.88 \
  --dut-vm-user root \
  --dut-vm-password root \
  --physical-interface em1 \
  --virtual-interface vnet0 \
  --dut-vm-nic-pci=0000:00:02.0 \
  --packet-list=64 \
  --stream-list=1000 \
  --no-bridge-config \
  --skip-pv-test
- Connecting to the tester...
- Connecting to DUT, "10.19.17.133"...
- Stop any running test tools...
- Get OpenFlow and DataPath port numbers...
- Get OVS datapath type, "system"...
- Create "test_results.csv" for writing results...
- [TEST: test_p2v2p(flows=1000, packet_size=64)] START
  * Create OVS OpenFlow rules...
  * Clear all OpenFlow/Datapath rules on bridge "ovs_pvp_br0"...
  * Create 1000 L3 OpenFlow rules...
  * Create 1000 L3 OpenFlow rules...
  * Verify requested number of flows exists...
  * Initializing packet generation...
  * Clear all statistics...
  * Start packet receiver on VM...
  * Start CPU monitoring on DUT...
  * Start packet generation for 20 seconds...
  * Stop CPU monitoring on DUT...
  * Stopping packet stream...
  * Stop packet receiver on VM...
  * Gathering statistics...
    - Packets send by Tester      :          271,211,729
    - Packets received by physical:           31,089,703 [Lost 240,122,026, Drop 0]
    - Packets received by virtual :           31,047,822 [Lost 41,881, Drop 41,824]
    - Packets send by virtual     :              701,931 [Lost 30,345,891, Drop 0]
    - Packets send by physical    :              661,301 [Lost 40,630, Drop 0]
    - Packets received by Tester  :              661,301 [Lost 0]
    - Receive rate on VM: 1,631,719 pps
  ! Result, average: 32,295.4875 pps
  * Restoring state for next test...
- [TEST: test_p2v2p(flows=1000, packet_size=64)] END
- Done running performance tests!
```

If this is successful we can go ahead and do a full run. This will roughly take
a day to finish. For more details and background information on this see the
[_ovs\_perf_](https://github.com/chaudron/ovs_perf/tree/RHEL8#full-day-pvp-test)
documentation. This is done running the included __runfullday.sh__ script.

```
$ ./runfullday.sh
This script will run the tests as explained in the "Full day PVP test"
section. It will start the scripts according to the configuration given below,
and will archive the results.

NOTE: Make sure you are passing the basic test as explained in "Running the
      PVP script" before starting the full day run!

What datapath are you using, DPDK or Linux Kernel [dpdk/kernel/tc]? kernel
What is the IP address where the DUT (Open vSwitch) is running? 10.19.17.133
What is the root password of the DUT? root
What is the IP address of the virtual machine running on the DUT? 192.168.122.186
What is the IP address of the TRex tester? localhost
What is the physical interface being used, i.e. dpdk0, em1, p4p5? em1
What is the virtual interface being used, i.e. vhost0, vnet0? vnet0
What is the virtual interface PCI id? 0000:00:06.0
Enter the Number of VM nic receive descriptors, 4096(default)? 4096
Enter the Number of Number of VM nic transmit descriptors, 1024(default)? 1024
What is the TRex tester physical interface being used? 0
What is the link speed of the physical interface, i.e. 10(default),25,40,50,100? 10
Enter L2/L3 streams list. default(10,1000,10000,100000,1000000)? 10,1000,10000,100000,1000000
- Connecting to the tester...
- Connecting to DUT, "10.19.17.1
...
...
=================================================================================
== ALL TESTS ARE DONE                                                         ===
=================================================================================

 Please verify all the results and make sure they are within the expected
 rates for the blade!!

=================================================================================
All tests are done, results are saved in: "/root/pvp_results_2017-10-13_055506_kernel.tgz"
```

## Running the _ovs\_perf_ script for the Linux Kernel datapath with TC Flower offload

This step is only required if you are running a blade that supports hardware
offload using TC flower.

### Configuring the Linux Kernel datapath with TC Flower offload

Run the Ansible script pvp_tcflower_offload.yml

    sudo ansible-playbook pvp_tcflower_offload.yml

For manual steps refer to  [_ovs\_perf_ script documentation](https://github.com/chaudron/ovs_perf/tree/RHEL8#open-vswitch-with-linux-kernel-datapath-and-tc-flower-offload)


### Run the PVP performance script

The PVP script should now work as before with some slide changes to the
interfaces being used. Below is the same _quick 64 bytes packet run with 1000
flows_ as ran before on the other datapaths:

```
# cd ~/pvp_results
# ~/ovs_perf/ovs_performance.py \
 ~/ovs_perf/ovs_performance.py \
  -d -l testrun_log.txt \
  --tester-type trex \
  --tester-address localhost \
  --tester-interface 0 \
  --ovs-address 10.19.17.133 \
  --ovs-user root \
  --ovs-password root \
  --dut-vm-address 192.168.122.153 \
  --dut-vm-user root \
  --dut-vm-password root \
  --physical-interface enp3s0np0 \
  --virtual-interface eth1 \
  --dut-vm-nic-pci=0000:00:06.0 \
  --stream-list=1000 \
  --packet-list=64 \
  --no-bridge-config \
  --skip-pv-test
- Connecting to the tester...
- Connecting to DUT, "wsfd-netdev16.ntdv.lab.eng.bos.redhat.com"...
- Stop any running test tools...
- Get OpenFlow and DataPath port numbers...
- Get OVS datapath type, "system"...
- Create "test_results.csv" for writing results...
- [TEST: test_p2v2p(flows=1000, packet_size=64)] START
  * Create OVS OpenFlow rules...
  * Clear all OpenFlow/Datapath rules on bridge "ovs_pvp_br0"...
  * Doing flow table cool-down...
  * Create 1000 L3 OpenFlow rules...
  * Create 1000 L3 OpenFlow rules...
  * Verify requested number of flows exists...
  * Initializing packet generation...
  * Clear all statistics...
  * Start packet receiver on VM...
  * Start CPU monitoring on DUT...
  * Start packet generation for 20 seconds...
  * Stop CPU monitoring on DUT...
  * Stopping packet stream...
  * Stop packet receiver on VM...
  * Gathering statistics...
    - Packets send by Tester      :        1,180,505,088
    - Packets received by physical:        1,180,505,088 [Lost 0, Drop 0]
    - Packets received by virtual :          211,455,733 [Lost 969,049,355, Drop 304,298,982]
    - Packets send by virtual     :          211,405,495 [Lost 50,238, Drop 0]
    - Packets send by physical    :          212,696,034 [Lost -1,290,539, Drop 0]
    - Packets received by Tester  :          211,405,249 [Lost 1,290,785]
    - Receive rate on VM: 10,662,126 pps
  ! Result, average: 10,659,505 pps
  * Restoring state for next test...
- [TEST: test_p2v2p(flows=1000, packet_size=64)] END
- Done running performance tests!
```

If this is successful we can go ahead and do a full run. This will roughly take
a day to finish. For more details and background information on this see the
[_ovs\_perf_](https://github.com/chaudron/ovs_perf/tree/RHEL8#full-day-pvp-test)
documentation. This is done running the included __runfullday.sh__ script.

```
$ ./runfullday.sh
This script will run the tests as explained in the "Full day PVP test"
section. It will start the scripts according to the configuration given below,
and will archive the results.

NOTE: Make sure you are passing the basic test as explained in "Running the
      PVP script" before starting the full day run!

What datapath are you using, DPDK or Linux Kernel [dpdk/kernel/tc]? tc
What is the IP address where the DUT (Open vSwitch) is running? 10.19.17.133
What is the root password of the DUT? root
What is the IP address of the virtual machine running on the DUT? 192.168.122.153
What is the IP address of the TRex tester? localhost
What is the physical interface being used, i.e. dpdk0, em1, p4p5? enp3s0np0
What is the virtual interface being used, i.e. vhost0, vnet0? eth1
What is the virtual interface PCI id? 0000:00:06.0
Enter the Number of VM nic receive descriptors, 4096(default)? 4096
Enter the Number of Number of VM nic transmit descriptors, 1024(default)? 1024
What is the TRex tester physical interface being used? 0
What is the link speed of the physical interface, i.e. 10(default),25,40,50,100? 10
Enter L2/L3 streams list. default(10,1000,10000,100000,1000000)? 10,1000,10000,100000,1000000
- Connecting to the tester...
- Connecting to DUT, "10.19.17.1
...
...
=================================================================================
== ALL TESTS ARE DONE                                                         ===
=================================================================================


Please verify all the results and make sure they are within the expected
rates for the blade!!

=================================================================================
All test results are saved in: "/root/pvp_results_2018-02-23_040540_tc.tgz"
```

## TC Flower Rule Rate Tests

If you card is going to support TC Flower rule offloading then please run the next
set of tests.

Use the Ansible script tc_flow_insertion.yml to setup needed packages to run the test script.

'''
sudo ansible-playbook tc_flow_insertion.yml
'''

The test is located in RHEL_NIC_QUALIFICATION/perf-flower/rule-install-rate and needs to be
executed on the DUT.

If this folder is empty you may have to force an init to pull the test package
from the RHEL_NIC_QUALIFICATION folder.

```
git submodule update --init
```


Now you shall execute the run.sh script as:

```
PATH=~/bin:$PATH ./run.sh -i <PF interface>
```

Please save the result files fl_change.dat and fl_change.png off to be processed later.


## Running VSPerf Performance tests

Once the 24 hour tests have completed we will now run a series of performance tests
using an upstream vswitch testing project called VSPerf.

The T-rex server should be installed as per the above instructions and the cabling is the
same. 2 NICs wired back to back from the T-Rex server to the server under test.

All tunings are similar as above on the device under test with the following considerations...

  1. The user must be root
  2. The total length of time for these tests is 12 to 14 hours approximately.
  3. The openvswitch service must be stopped. This is because VSPerf does a custom startup
     and a running instance will cause the tests to fail.

     ```
     systemctl stop openvswitch
     systemctl disable openvswitch
     ```


  4. The loopback virtual machine must be shutdown.

     ```
     virsh shutdown rhel_loopback
     virsh shutdown rhel_loopback_kerneldp
     ```

  5. The NICs to be tested are bound by kernel drivers. VSPerf will bind and unbind the NICs
     at the start and completion of a test.

     ```
     driverctl -v unset-override 0000:01:00.0
     ```

  6. You have at least 8 1G hugepages available.
  7. The device under test has an internet connection available to download a custom VNF image.
  8. The server has enough cores to support a PMD mask of 4 threads plus 5 VCPUs for the VNF image
     where the cores are on the same NUMA as the NIC if you are running on a multi numa system.
  9. Activate rhel-7-server-optional repository for libpcap-devel package that will be installed
     by the script. 
     ```
     subscription-manager repos --enable=rhel-7-server-optional-rpms
     ```

 The tests are located in the root folder of the git cloned repository. You MUST specify ALL values
 in the Perf-Verify.conf file. The settings are as follows.

 NIC1 and NIC2 NIC Device names such as p6p1 p6p2 enclosed in quotation marks

 These are the devices that will receive and forward packets on the device under test to the guest.

 PMD MASK for 2 PMDS
 A Hex mask for using one core/2HT pair and 2 core/4HT
 Example with a layout such as seen from the output of lscpu and cpu_layout.py
 cpu_layout.py can be obtained from the dpdk repository source code dpdk.org

    Architecture:          x86_64
    CPU op-mode(s):        32-bit, 64-bit
    Byte Order:            Little Endian
    CPU(s):                48
    On-line CPU(s) list:   0-47
    Thread(s) per core:    2
    Core(s) per socket:    12
    Socket(s):             2
    NUMA node(s):          2
    Vendor ID:             GenuineIntel
    CPU family:            6
    Model:                 79
    Model name:            Intel(R) Xeon(R) CPU E5-2687W v4 @ 3.00GHz
    Stepping:              1
    CPU MHz:               3000.044
    BogoMIPS:              6005.35
    Virtualization:        VT-x
    L1d cache:             32K
    L1i cache:             32K
    L2 cache:              256K
    L3 cache:              30720K
    NUMA node0 CPU(s):     0,2,4,6,8,10,12,14,16,18,20,22,24,26,28,30,32,34,36,38,40,42,44,46
    NUMA node1 CPU(s):     1,3,5,7,9,11,13,15,17,19,21,23,25,27,29,31,33,35,37,39,41,43

    python cpu_layout.py
    ======================================================================
    Core and Socket Information (as reported by '/sys/devices/system/cpu')
    ======================================================================

    cores =  [0, 1, 2, 3, 4, 5, 8, 9, 10, 11, 12, 13]
    sockets =  [0, 1]

            Socket 0        Socket 1
            --------        --------
    Core 0  [0, 24]         [1, 25]
    Core 1  [2, 26]         [3, 27]
    Core 2  [4, 28]         [5, 29]
    Core 3  [6, 30]         [7, 31]
    Core 4  [8, 32]         [9, 33]
    Core 5  [10, 34]        [11, 35]
    Core 8  [12, 36]        [13, 37]
    Core 9  [14, 38]        [15, 39]
    Core 10 [16, 40]        [17, 41]
    Core 11 [18, 42]        [19, 43]
    Core 12 [20, 44]        [21, 45]
    Core 13 [22, 46]        [23, 47]

 To use cores 44,20 if your NIC is on Numa 0 you would use a mask of 040000040000
 To use cores 44,20 and 42,18 I would use a mask of 050000050000

 If you need help calculating a mask string you can use the pmdmask.sh script
 which will calculate out the hex string for you.

    PMD2MASK="040000040000"
    PMD4MASK="050000050000"

 Virtual NIC Guest CPU Binding
 Using the same scripts above assign first VCPU to a single core. Then assign
 VCPU2 and VCPU3 to a core/HT pair such as 4,28. Should not be a core already
 in use by the PMD MASK. All CPU assignments should be on different
 Hyperthreads.

    VCPU1=""
    VCPU2=""
    VCPU3=""

 Will need additional VCPUs for 2 queue test

    VCPU4=""
    VCPU5=""

 Based on the output above this is a sample set of settings

    NIC1="p6p1"
    NIC2="p6p2"
    PMD2MASK="040000040000"
    PMD4MASK="050000050000"
    VCPU1="2"
    VCPU2="4"
    VCPU3="28"
    VCPU4="6"
    VCPU5="30"

 TestPMD runs inside the guest with a descriptor value for receive and transmit. Some cards
 may benefit from different sizes when executing TestPMD. You can modify these values by
 changing the following settings for OVS-DPDK/Kernel tests and SR-IOV tests

    TXD_SIZE=512
    RXD_SIZE=512
    SRIOV_TXD_SIZE=2048
    SRIOV_RXD_SIZE=2048

 Specify your Trex information in the conf file based on your T-Rex server.

    TRAFFICGEN_TREX_HOST_IP_ADDR=''
    TRAFFICGEN_TREX_USER=''
    TRAFFICGEN_TREX_BASE_DIR
 The place, where 't-rex-64' file is stored on Trex Server such as /root/trex-core/scripts/
 If you setup according to the instructions above then /root/trex/v2.29/ should work

 ***Note*** the trailing / in the path

    TRAFFICGEN_TREX_BASE_DIR='/root/trex/v2.29/'

 Mac addresses of the ports configured in TRex Server as found in

      cat /etc/trex_cfg.yaml

    ### Config file generated by dpdk_setup_ports.py ###

    - port_limit: 2
      version: 2
      interfaces: ['04:00.0', '04:00.1']
      port_info:
          - dest_mac: a0:36:9f:65:ee:7a # MAC OF LOOPBACK TO IT'S DUAL INTERFACE
            src_mac:  a0:36:9f:65:ee:78
          - dest_mac: a0:36:9f:65:ee:78 # MAC OF LOOPBACK TO IT'S DUAL INTERFACE
            src_mac:  a0:36:9f:65:ee:7a

      platform:
          master_thread_id: 4
          latency_thread_id: 6
          dual_if:
            - socket: 0
              threads: [2,4,6,8,10,12,14,16,18,20,22,24,26,28,30,32,34,36,38,40,42,44,46]

    TRAFFICGEN_TREX_PORT1='a0:36:9f:65:ee:7a'
    TRAFFICGEN_TREX_PORT2='a0:36:9f:65:ee:78'

By default the VSPerf api calls to T-rex will try to determine the best speed to operate.

For generating traffic with some cards it may be useful to specify a lower speed. For example
if you wanted to force the maximum speed of your T-Rex server to operate at 10G speed you can
modify the following lines. Simple set the TREX_FORCE_CUSTOM_SPEED to be True.  The speed option
is already set to 10 gigabit. For 25 gigabit you could modify it to 25000.

    TREX_FORCE_CUSTOM_SPEED=False
    TREX_CUSTOM_SPEED=10000

 SR-IOV Information
 To run SR-IOV tests please complete the following info
 NIC Device name for VF on NIC1 and NIC2 Example p6p1_0 for vf0 on p6p1

    NIC1_VF=""
    NIC2_VF=""

NOTE: One will need to set up ssh login to not use passwords between the server
running Trex and the device under test (running the VSPERF test
infrastructure). This is because VSPERF on one server uses 'ssh' to
configure and run Trex upon the other server. This needs to be executed on both
the T-Rex server and the device under test.

One can set up this ssh access by doing the following on both servers:

    ssh-keygen -b 2048 -t rsa

    ** NOTE ** Make sure to leave the password field blank.

    ssh-copy-id <other server>

The T-Rex application must now be running on the T-Rex server for VSPerf to connect
to it using the Python API as part of its execution. The program should be located
in the scripts folder of the T-Rex install location.

./t-rex-64 -i

For RHEL 8 Beta you must enable other repos through subscription manager for VSPerf installation
to correctly work.

    subscription-manager repos --enable rhel-8-for-x86_64-supplementary-beta-rpms

Once all settings are complete one should be able to execute Perf-Verify.sh to start execution
of VSPerf tests. This only needs to be executed on the DUT. Not on the T-Rex server. The script
will do some checks to try and verify the setup is complete and ready for testing. Any issues
will be shown on the screen.

There is an option to only execute specific tests by running Perf-Verify.sh with a -t argument
followed by the test name. Here is a list of the tests with their respective argument;

1Q - 1 queue running 4 PMD threads on 2 Hyper threads for 64 and 1500 byte packet sizes
2Q - 2 queues running 8 PMD threads on 4 Hyper threads for 64 and 1500 byte packet sizes
Jumbo - 1 queue running 4 PMD threads on 2 Hyper threads running 2000 and 9000 byte packet sizes
Kernel - Kernel datapath with no DPDK enabled.

If you wanted to run just the 1Q test to troubleshoot a possible issue you could execute the script
like so:

./Perf-Verify.sh -t 1Q

There is also a fast execution test to check VSPerf functionality and to verify your T-Rex server
configuration. You can run the script and specify the pvp_cont test like so:

./Perf-Verify.sh -t pvp_cont

You will see the following output when the tests start to execute and cycle this banner for each
test.

    ***********************************************************
    *** Running 64/1500 Bytes 2PMD OVS/DPDK PVP VSPerf TEST ***
    ***********************************************************

 The tests should meet the following pass criteria when viewing the final results.

 DPDK tests
 - 64 bytes PVP will achieve 3 Mpps at 0 loss for 10 minutes
 - 1500 bytes PVP will achieve 1.5 Mpps at 0 loss for 10 minutes
 - 64 Bytes PVP 2 Queue 4 PMD will achieve 6 Mpps at 0 loss for 10 minutes
 - 1500 bytes PVP 2 Queue 4 PMD will achieve 1.5 Mpps at 0 loss for 10 minutes
 - 2000 byte jumbo frames PVP will achieve 1100000 Mpps at 0 loss for 10 minutes
 - 9000 byte jumbo frames PVP will achieve 250 Kpps at 0 loss for 10 minutes
 Kernel OVS tests
 - 64 bytes PVP will achieve 100 Kpps at 0.002 loss for 10 minutes
 - 1500 bytes PVP will achieve 100 Kpps at 0.002 loss for 10 minutes

 Once all tests completed the next script will execute a VSPerf tests using SR-IOV
 to bypass the switch and send packets from a VF directly to the guest.

 Enable SR-IOV on the NICs under test.

 Verify the VFs can be seen

    ip link show p6p1
    14: p6p1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT qlen 1000
        link/ether 90:e2:ba:cb:b4:78 brd ff:ff:ff:ff:ff:ff
        vf 0 MAC 36:34:66:94:28:d2, spoof checking on, link-state auto, trust off, query_rss off
        vf 1 MAC 02:18:7c:11:3b:dd, spoof checking on, link-state auto, trust off, query_rss off
        vf 2 MAC 5a:f3:c5:5a:bc:ce, spoof checking on, link-state auto, trust off, query_rss off

 You can enable a single vf per port as 3 vfs are not required. Just verify the setting in the
 Perf-Verify.conf for the vf names is appropriate 'NIC1_VF' 'NIC2_VF' and points to the correct
 vf device.

 Make sure all VFs have a valid non 0 mac address set otherwise the packets from the traffic
 generator will not flow to the correct VF and the test will fail.

 Now execute the Perf-Verify-sriov.sh test which will run for 3-4 hours.

 If the test has been running for 5 minutes then it should run the full 3-4 hours.

    ************************************************
    *** Running 64/1500 Bytes SR-IOV VSPerf TEST ***
    ************************************************

    ...running for 5 minutes

 For this test to be considered a pass by Red Hat the results must meet the following specifications

 - 64 Bytes PVP passthrough will achieve 10 Mpps at 0 loss for 10 minutes
 - 1500 Bytes PVP passthrough will achieve 1.6 Mpps at 0 loss for 10 minutes

 Result logs are placed into the following folder '/root/RHEL_NIC_QUAL_LOGS/<date_time>'

 The contents will appear as something similar to below.

```
drwxr-xr-x. 2 root root   83 Oct 16 16:27 2017-10-16-16:24:44
drwxr-xr-x. 2 root root    6 Oct 16 16:30 2017-10-16-16:30:45
drwxr-xr-x. 2 root root  116 Oct 16 16:38 2017-10-16-16:34:59
drwxr-xr-x. 2 root root 4096 Oct 16 16:59 2017-10-16-16:49:26
drwxr-xr-x. 2 root root   83 Oct 16 17:02 2017-10-16-17:02:03
drwxr-xr-x. 2 root root 4096 Oct 16 17:30 2017-10-16-17:19:41
drwxr-xr-x. 2 root root 4096 Oct 16 17:44 2017-10-16-17:34:07
drwxr-xr-x. 2 root root  116 Oct 16 17:50 2017-10-16-17:47:14
drwxr-xr-x. 2 root root  116 Oct 17 09:45 2017-10-17-09:41:09
drwxr-xr-x. 2 root root 4096 Oct 17 10:06 2017-10-17-09:55:18
drwxr-xr-x. 2 root root   83 Oct 17 10:08 2017-10-17-10:07:09
drwxr-xr-x. 2 root root  149 Oct 17 11:07 2017-10-17-11:00:41
-rw-r--r--. 1 root root   60 Oct 17 11:00 vsperf_logs_folder.txt
```

 The vsperf_logs_folder.txt contains the most recent folder of execution which is used by
 the collections script to collect the logs. If you wish to review the VSPerf output you
 can look at the logs in the appropriate folder.

 Once this test has passed disable SR-IOV and begin execution of the functional QE scripts

## Running the _OVS functional qualification_

These tests follow a server/client model where the client is the DUT and the server will
be used to execute certain functions to verify the client.

If you are going to use the T-Rex server as the server system, please stop the T-Rex client
before continuing. You may need to unbind the NICs that were used for T-Rex using dpdk-devbind
or simply reboot the system.

Also there are bonding tests that require a switch configuration to pass. For this part of
the test to work both the server and client must be plugged into a Juniper or Cisco switch.

Most of the tests will pass if still connected back to back as per the above tests, however;
the bonding tests require a switch as a broadcast domain to work correctly.

```
   +---------+                +--------+               +---------+
   |         | p5p1     e1/9  |        |               |         |
   |         +----------------+        | e1/11    p5p1 |         |
   | CLIENTS |                | Switch +---------------+ SERVERS |
   |         +----------------+        |               |         |
   |         | p5p2     e1/10 |        |               |         |
   +----+----+                +----+---+               +----+----+
        |                          |                        |
        +--------------------------+------------------------+
                                   |
                              To Internet
```

To setup these tests git clone the qualification suite onto the Server, the client should already have the
folder available.

```
    git clone https://github.com/ctrautma/RHEL_NIC_QUALIFICATION.git
```

To execute the functional tests you need to expand the rh_nic_cert.tar file on both systems.

From the root of the git cloned folder expand the tar file.

```
    tar -xvf rh_nic_cert.tar
```

The files will expand into the rh_nic_cert folder. The settings in the Perf-Verify.conf
are used for a single test in this suite of tests so verify the conf file is correct on the client
side.

Before starting the tests please uninstall openvswitch and reinstall openvswitch. This is because VSPerf does not
use systemctl to start openvswitch and can cause some db configuration problems when going back to using systemctl.
If using a custom openvswitch please re-install the custom version instead of the one from the fast datapath channel.

```
    yum remove openvswitch
    yum install openvswitch
```

It is also recommnded to reboot the systems.

Inside the rh_nic_cert folder is a rh_nic_cert.sh script. This script has settings at the top
that must be completed as follows

  1. 'CLIENTS' must be set to the DUT hostname

  2. 'SERVERS' must be set to the server hostname

  3. 'NIC_CLIENT' must be set to the NIC device names on the DUT

  4. 'NIC_SERVER' must be set to the NIC device name on the server which will be used to send traffic

  5. If doing the topology with a switch for bonding tests then it must be defined correctly in the
     lib/lib_swcfg_list.sh file and referenced by the correct name for the 'SW_NAME' parameter in the
     rh_nic_cert.sh. The following must be correct in the lib/swlist_list.sh file. This only needs to
     be done on the client side.

     If using a Juniper Junos or Cisco NXOS switch the switch may already be programmed into the
     scripts. See item a below.

     a. Make sure the SW_NAME specified in the rh_nic_cert.sh 'SW_NAME' appears in the SWITCH LIST file
        at rh_nic_cert/lib/lib_swcfg_list.sh. If it does not it is possible to add your own switch file
        for your switch brand. Create a new script file to your brand of switch as lib_swcfg_api_xyz.sh
        in the lib folder. For example for nxos we use the lib_swcfg_api_nxos.sh so you can use this as
        a template to define the needed commands. Once the new file is created populate the
        lib_swcfg_list.sh making sure to name the sw_os per xyz of the newly created file. If you created
        a new configuration for a switch please do a pull request to the github so we can add it for
        future executions.

     b. Populate the values needed for a pre-defined switch name or create a new one in the SW_LIST where
        the value should be the model number, the switch type, the ssh login and IP, and the password.

     c. Populate the SW_NAME per the first sw_name of the switch as listed in the lib_swcfg_list.sh file.

  6. Populate 'SW_PORT_CLIENT' with the switch ports the client side is connected

  7. 'SW_PORT_SERVER' the switch port where the server is connected

  8. 'IMG_GUEST' this specifies the location of the IMG to use for testing. For 7.5 testing leave it as is. For 7.6
     please modify the location to http://people.redhat.com/ctrautma/RHEL76-1Q.qcow2.lrz

  9. 'SRC_NETPERF' set to use the following location people.redhat.com/ctrautma/netperf-20160222.tar.bz2

  10. 'RPM_KERNEL' leave alone, internal use only

  11. 'IPERF_RPM' leave alone, already set to an external location to download iperf

  12. 'SETENFORCE' leave alone

  13. 'QE_SKIP_TEST' can be set to skip particular tests, leave alone unless wanting to skip bonding tests

  14. 'QE_TEST' leave alone unless wanting to run a specific test only

  15. 'BONDING_TEST' set of bonding tests to execute, can be modified if wishing to run a specific test only

  16. 'RPM_OVS' change to the current RPM name from

  17. 'RPM_DPDK' change to location of DPDK standalone RPM

  18. 'RPM_DPDK_TOOLS' change to location of DPDK standlone tools RPM

  19. 'RPM_DRIVERCTL' change to location of driverctl RPM

```
    rpm -qa | grep openvswitch
```

Make sure the settings in rh_nic_cert.sh are completed on both the server and client systems.

In some cases it may be easier to just copy the file from one system to the other once all values have
been added.

Then you can execute rh_nic_cert.sh from both the server and client systems. They should be executed as
close together as possible. The scripts will wait for the other side but may time out after some time.

```
    ./rh_nic_cert.sh
```

The tests will execute for 4-6 hours and report the results at the end.

## Analyzing and gathering the results

To collect the results for the performance and functional tests execute the collections.sh script on the
client and server which will attempt to retrieve the most recent results from the system and provides a file.

```
    ./collection.sh
    ......collection output
    Please provide file <hostname>_2017-10-17-11:18:08.tar to Redhat Certification Team
```

The collection script will install sos if it is not already installed and run an sos report. It will also
collect the "LAST" iteration of the performance QE tests and functional tests. It is assumed that the
last run was the iteration you wish to send for review. If you have a different iteration you wish to
submit modify the txt files in RHEL_NIC_QUAL_LOGS to point to the dated folder you wish to submit and
run the collection script again.

The files are vsperf\_logs\_folder.txt and kernel\_functional\_logs.txt which point to specific folders.

Once all tests have been executed and the output from the collection.sh script and pvp results are collected
you can generate a reporting spreadsheet to glance and see how your tests went.

To run the process\_my\_results.py script. You will need both the client and
server side files from collection.sh script. You will also need the files from
the pvp testing results, and the fl_change.dat, fl_change.png files from the TC
Flower tests. Use the -o argument to give an output filename for your report,
i.e. results.xlsx.


```
    python process_my_results.py -h
    usage: process_my_results.py [-h] -o OUTPUT -s SERVER_TAR_FILE -c
                             CLIENT_TAR_FILE

    optional arguments:
    -h, --help            show this help message and exit
    -o OUTPUT, --output OUTPUT
                          Output file name
    -s SERVER_TAR_FILE, --server_tar_file SERVER_TAR_FILE
                          Server tar file name
    -c CLIENT_TAR_FILE, --client_tar_file CLIENT_TAR_FILE
                          Client tar file name
```

__NOTE__: To run the _process\_my\_results.py_ script you might need to install
the following additional tools:

```
    yum install -y python-pip
    pip install xlsxwriter
```


You __MUST__ provide the following files to the certification team for review:
- Client-side tar from the collection.sh script
- Server-side tar from the collection.sh script
- The relevant PVP results based on the tested datapaths, i.e. pvp_results_*.tgz
- The fl_chance.dat and fl_change.png files if the submission includes TC Flower support
- The result spreadsheet file generated by _process\_my\_results.py_
