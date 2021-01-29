# Red Hat NIC NFV Qualification

# Ansible branch for RHEL 8.x only.

The goal of this document is to guide you step by step through the process of
qualifying a NIC driver for NFV usage. This includes both the Linux Kernel
driver and the DPDK PMD driver.

Please reach to Red Hat PFT team at redhat-pft@redhat.com, if you have any questions. 

IT IS CRITICAL for qualification to keep all logs and to execute the collection
script at the end of these tests. The collection script must be run on the
server and client side. Please see the end of this file for further details.

The QE Scripts are three separate scripts that all must pass.

- Custom Physical to Virtual back to Physical(PVP) test script, _ovs\_perf_
- RFC 2544-Based Benchmarking throughput tests
- OVS functional qualification

The ovs_perf script is an upstream project, which will give details on
performance and CPU usage. It also produces graphs which can be used to see if
the NIC behaves according to the customers quoted specifications. We will run
a series of these tests, which in total will run for about two days. This will include
testing of both the Linux Kernel and DPDK datapath.

The throughput tests use an upstream project from https://github.com/atheurer/trafficgen
that conducts a binary-search for maximum packet throughput.

The functional test script runs a plethora of tests to verify NICs pass
functional requirements.

This document has 4 chapters:
1. PVP test
2. Throughput test
3. Functional test
4. Collect test results

## 1. PVP test (OVS_Perf)

The performance tests (_ovs\_perf_ and throughput test) both require two servers.
One server will have TREX installed, the other will be a clean install system
running RHEL 8.1 or greater. The servers should be wired back to back from the
test NICs to the output NICs of the T-Rex server. These tests use two NIC ports
on the Device Under Test (DUT) and two ports on the T-Rex which are connected as shown below.
The two NIC ports on the DUT must be the brand and type of NICs which are to be
qualified. The first set of performance tests use a topology as seen below.

```
     +---------------------------------------+
     |   +--------------------------------+  |
     |   |                          Guest |  |
     |   |   +------------------------+   |  |
     |   |   |        testpmd         |   |  |
     |   |   +------------------------+   |  |
     |   |       ^               :        |  |
     |   |       |               |        |  | 
     |   |       :               v        |  |
     |   |   +------------------------+   |  |
     |   |   |       logical port     |   |  |
     |   +---+------------------------+---+  |
     |           ^               :           |
     |           |               |           |
     |           :               v           |
     |       +-----------------------+       |
     |       |      logical port     |       |
     |       +-----------------------+       |
     |           ^               :           |
     |           |               |           |
     |           :               v           |
     |       +-----------------------+       |
     |       |   physical port       |  Host |
     +-------+-----------------------+-------+
                  ^        :           
                  |        |  
                  :        v
       +-------------------------------+
       |                               |
       |       traffic generator       |   
       |                               |
       +-------------------------------+
```       

All traffic on these tests are bi-directional and the results are calculated as a total of the
sum of both ports in frames per second.

### 1.1 Setup test environment
#### 1.1.1 Setting up for Ansible script execution

First make sure both the Trex server and the DUT have their Red Hat subscriptions setup with your credentials to be
able to pull the repos correctly.  If you do not have this info please contact your Red Hat representative to get
this info.  If the systems are not subscribed correctly the yum installs will fail.  If you are using this test
inside the Red Hat network this step can be ignored.

The Ansible scripts are located in ansible folder of this github project. Each of the PVP setups below can be
automated using the Ansible scripts so the manual steps can be ignored.  To properly run the Ansible scripts
the configuration files must be completed.

The configuration files are as follows

ansible.cfg
inventory
test_settings.yml

The changes required to make the scripts work is as follows.

##### inventory file

Modify the trex and dut sections to reflect the system hostnames or ip addresses that are to be used for the test.

##### test_settings.yml

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
password when prompted.

The reason this info must be entered into a settings file is because the guest will require installing some rpms so
we need to setup the subscriptions in the Ansible script.  This is separate from setting up the subscriptions on the
bare metal systems.

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

Version 2.8.0.1 or above should work with all of the Ansible scripts.  In my case my work laptop is running RHEL 7 which
is ideal for this task.

After all of these things are complete login into each system to make sure your access works, then proceed to each
section below and use the corresponding script.  The scripts only do the setup of the environments.  You will still
be required to run the PVP test script to start the test after.

If errors are seen and the Ansible script fails,  please check the config file.  If everything looks OK and you think
its a script issue please contact Red Hat PFT team at redhat-pft@redhat.com

Please be aware that the scripts must be run in order.  You cannot run the kernel script without running the ovs-dpdk
script first.  They are designed to be executed in order.  If you want to run just the kernel test,  you must run
the ovs-dpdk script,  then move on to the kernel script.  Then you can run the test for Kernel PVP.

Also if the ovs-dpdk script fails at any point, you will have to stop the openvswitch server and unbind the nic to
restart the script if it completed a few steps.  The NIC will be bound using driverctl utility.

##### Download the guest image
  
Please visit https://access.redhat.com/downloads/content/479/ver=/rhel---8/8.2/x86_64/product-software and use the
combo boxes to select the correct guest image for use with the tests.  For example for 8.2 you would select 8.2 in the version and then select Red Hat Enterprise Linux for x86_64 from the Product Variant, then download the latest Red Hat Enterprise Linux 8.2 Update KVM Guest Image.  Save this to the DUT
as the Ansible script will use it for the test setup.  You will need to modify the trex_settings.yml file to specify
where this was saved.

#### 1.1.2 Setup the TRex traffic generator

Use the Ansible script trex_setup.yml to setup the trex server system.

    sudo ansible-playbook trex_setup.yml

For manual instructions please refer to [_ovs\_perf_ script documentation](https://github.com/chaudron/ovs_perf/tree/RHEL8#setup-the-trex-traffic-generator) on how to configure the TRex traffic generator.

Once the script is complete you must still start the T-rex application on the server itself.  Log into the T-Rex server
and perform the following steps

    cd ~/trex/v2.82

Note if you picked a different version to use for T-Rex the above command may change.
Then start the server

    ./t-rex-64 -c 4 -i --no-scapy-server

### 1.2 Run tests

#### 1.2.1 Running the _ovs\_perf_ script for ovsdpdk testing

##### Setup the DUT 
<a name="DUTsetup"/>

Use the Ansible script pvp_ovsdpdk.yml to setup the DUT for the OVS-dpdk PVP test

    sudo ansible-playbook pvp_ovsdpdk.yml

Please note the last step will display the VM IP address in a long message that you will need to read through to find
the IP. The VM IP is needed to run the test script below.

Also note that you may have to enter your ssh key passphrase that you specified when you created your token file.  This
may need to be entered at the start of the script and during the reboot of the DUT.

For manual instructions please refer to  [_ovs\_perf_ script documentation](https://github.com/chaudron/ovs_perf/tree/RHEL8#setup-the-device-under-test-dut-open-vswitch) on how to configure the DUT for OVS. Follow the above-linked chapter and stop at the [Running the PVP script](https://github.com/chaudron/ovs_perf/tree/RHEL8#running-the-pvp-script) chapter, and continue below.


##### Running the PVP script

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



#### 1.2.2 Running the _ovs\_perf_ script for the Linux Kernel datapath

With the above setup, we ran the PVP tests with the Open vSwitch DPDK datapath.
This section assumes you have the previous configuration running, and explains
the steps to convert it to a Linux datapath setup.

##### Configuring the Linux Kernel datapath

Run the Ansible script pvp_kernel.yml

    sudo ansible-playbook pvp_kernel.yml

Please note the last step will display the VM IP address in a long message that you will need to read through to find
the IP. The VM IP is needed to run the test script below.

Also note that you may have to enter your ssh key passphrase that you specified when you created your token file.  This
may need to be entered at the start of the script and during the reboot of the DUT.

For manual steps refer to  [_ovs\_perf_ script documentation](https://github.com/chaudron/ovs_perf/tree/RHEL8#open-vswitch-with-linux-kernel-datapath)


##### Run the PVP performance script

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

#### 1.2.3 Running the _ovs\_perf_ script for the Linux Kernel datapath with TC Flower offload

This step is only required if you are running a blade that supports hardware
offload using TC flower.

##### Configuring the Linux Kernel datapath with TC Flower offload

Run the Ansible script pvp_tcflower_offload.yml

    sudo ansible-playbook pvp_tcflower_offload.yml

For manual steps refer to  [_ovs\_perf_ script documentation](https://github.com/chaudron/ovs_perf/tree/RHEL8#open-vswitch-with-linux-kernel-datapath-and-tc-flower-offload)


##### Run the PVP performance script

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

#### 1.2.4 TC Flower Rule Rate Tests

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


## 2. Throughput test

Once the 24 hour tests have completed we will now run a series of throughput tests.

RFC 2544-Based Benchmarking Tests use binary search algorithm to test throughput 
using very basic flows rules and parameters. 

The script includes 5 tests (base on 3 logical topology) that run in the sequence as below:
* SRIOV  --sriov datapath pvp 64/1500 bytes throughput test (topo #1)
* OVS-DPDK 1Q     --ovs dpdk datapath pvp 64/1500 bytes throughput test (topo #2)
* OVS-DPDK 2Q     --ovs dpdk datapath pvp 64/1500 bytes throughput test (topo #2)
* OVS-DPDK Jumbo  --ovs dpdk datapath pvp 2000/9000 bytes throughput test (topo #2)
* Kernel --ovs kernel datapath pvp 64/1500 bytes throughput test (topo #3)
     
The three logical topology are SRIOV, OVS dpdk datapath pvp and OVS kernel datapath pvp. As below are the topology and test traffic path.


* Test topo#1 for sriov

```_
+DUT--------------------------------+         +----------------------------+
|------------------|                |         |                       Trex |
|  VM      |-----NIC1(VF)----------NIC1-------|TRAFFICGEN_TREX_PORT1       |
|        testpmd   |                |         |                            |
|          |-----NIC2(VF)----------NIC2-------|TRAFFICGEN_TREX_PORT2       |
|                  |                |         |                            |
|-------------------                |         +----------------------------+
+-----------------------------------+
```
Bidirectional traffic datapath:
TRAFFICGEN_TREX_PORT1 <--> NIC1 <--> NIC1 VF <--> TestPMD <--> NIC2 VF <--> NIC2 <--> TRAFFICGEN_TREX_PORT2



* Test topo#2 for ovs dpdk datapath pvp
```_
+DUT-----------------------------------------+       +----------------------+
|VM----------------|                         |       |                 Trex |
|     |-----NIC1(vhostuserclient)--|(vf)----NIC1-----|TRAFFICGEN_TREX_PORT1 |          
| testpmd          |         ovs-bridge       |      |                      |
|     |-----NIC2(vhostuserclient)--|(vf)----NIC2-----|TRAFFICGEN_TREX_PORT2 |            
|                  |                         |       |                      |
|-------------------                         |       +----------------------+
+--------------------------------------------+
```
Bidirectional traffic datapath:
TRAFFICGEN_TREX_PORT1 <--> NIC1 <--> NIC1 VF <--> ovs-bridge (openflow) <--> Guest-NIC1 <--> TestPMD <--> Guest-NIC2 <--> ovs-bridge (openflow) <-->NIC2 VF <--> NIC2 <--> TRAFFICGEN_TREX_PORT2



* Test topo#3 for ovs kernel datapath pvp
```_
+DUT-----------------------------------------+       +-----------------------+
|------------------|                         |       |                   Trex|
|VM   |-----eth1(tap0)-------------|-------NIC1------|TRAFFICGEN_TREX_PORT1  |
|   bridge         |         ovs-bridge      |       |                       |
|     |-----eth2(tap1)-------------|-------NIC2------|TRAFFICGEN_TREX_PORT2  |         
|                  |                         |       |                       |
|-------------------                         |       +-----------------------+
+--------------------------------------------+
```
Bidirectional traffic datapath:
TRAFFICGEN_TREX_PORT1 <--> NIC1 <--> ovs-bridge (openflow) <--> Guest-eth1 <--> bridge <--> Guest-eth2 <--> ovs-bridge (openflow) <--> NIC2 <--> TRAFFICGEN_TREX_PORT2

The total duration for these tests is about 1.5 hours.

The T-rex server should be installed as per the above ovs_perf instructions and the cabling is the same. Two NICs wired back to back from the T-Rex server to the server under test.

The system requirements are similar as above ovs_perf test on the DUT:

* The user must be root
* At least 24 1G hugepages available.
* The DUT has an internet connection available to download a custom VNF images and to install proper rpm packages includes openvswitch, dpdk, dpdk-tools, qemu-kvm, kernel-tools, qemu-img, etc.
* The server has enough cores to support a PMD mask of 4 threads plus 5 VCPUs for the VNF image where the cores are on the same NUMA as the NIC if you are running on a multi numa system.


### 2.1 Setup Test environment

#### 2.1.1 Setup Trex

The T-rex server should be installed as per the above ovs_perf instructions and the cabling is the same. Two NICs wired back to back from the T-Rex server to the server under test.


As following brief steps of setting up Trex is as same as the above ovs_perf test. You could skip this section and jump to the DUT setup section, if the Trex still has ovs_perf test settings.

Ansible playbook will help with the process. Assuming a laptop with rhel 8 is used to config Trex and DUT.  Following commands should be run on the laptop:
```
$ sudo ssh-keygen -b 2048 -t rsa
$ sudo ssh-copy-id root@<Trex>
```

Install ansible if it was not installed:
```
$yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
$yum install -y ansible
```

Download test scripts from github.
```
$git clone -b ansible --single-branch https://github.com/ctrautma/RHEL_NIC_QUALIFICATION.git
```

Modify configuration files to get ready for installing Trex server.
```
$vim ~/RHEL_NIC_QUALIFICATION/ansible/inventory

  [trex]
  <REPLACE HERE WITH THE TREX ADMIN IP>

  [dut]
  <REPLACE HERE WITH THE DUT ADMIN IP>
```

```
$vim test_settings.yml

  #current latest Trex version is v2.82 
  trex_version: v2.82
  trex_url: https://trex-tgn.cisco.com/trex/release/v2.82.tar.gz

  trex_interface_1: ens1f0
  trex_interface_2: ens1f1

  #command "sudo lshw -c network -businfo" or "ethtool -i <NIC>" could be used to find out pciid

  trex_interface_1_pciid: "0000:3b:00.0"  
  trex_interface_2_pciid: "0000:3b:00.1"
```


Use the Ansible playbook trex_setup.yml to setup the trex server system.
```
$sudo ansible-playbook ~/RHEL_NIC_QUALIFICATION/ansible/trex_setup.yml
```

#### 2.1.2 Setup the DUT


##### Install packages
  
Install some tools
```
#yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
#yum -y install git wget python3 hwloc hwloc-gui grubby tuned-profiles-cpu-partitioning
#alternatives --set python /usr/bin/python3
#pip install lxml
```
  
Install openvswitch and dpdk

DUT needs Red Hat subscriptions setup, if the systems are not subscribed correctly the yum installs will fail. For more subscription information, please find from the ovs_perf test section.  


```
#yum -y install openvswitch2.13 openvswitch-selinux-extra-policy
#yum -y install dpdk dpdk-tools
```
If you have any difficulty to install openvswitch, please let us know through email at redhat-pft@redhat.com.  
  
Download the test scripts if it has not been done already.
```
#git clone -b ansible --single-branch https://github.com/ctrautma/RHEL_NIC_QUALIFICATION.git
```
  
Install lrzip
```
#yum install -y ~/RHEL_NIC_QUALIFICATION/throughput-test/lrzip-0.616-5.el7.x86_64.rpm
```
  



##### Set variables in configuration files

The test scripts are located in the throughput-test folder of the git cloned repository and there are two configuration files.

* **throughput-test/env.sh**

By default, the test script main-perf-test.sh runs 5 tests in a sequence once the script starts. There is an option to only execute individual tests by toggling the switches. Without any change, the default values are 0 (not to skip, run the test); or change to 1 (to skip, not to run the test).

|  Switches in env.sh |  Test modules | Description  |
| ------------ | ------------ | ------------ |
|  SKIP_SRIOV |  SRIOV-VF-PCI-PASSTHROUGH-64-Bytes-1Q-2PMD-TEST |  SRIOV VF PCI-Passthrough without OVS |
| SKIP_SRIOV  |  SRIOV-VF-PCI-PASSTHROUGH-1500-Bytes-1Q-2PMD-TEST |  SRIOV VF PCI-Passthrough without OVS |
| SKIP_1Q  | OVS-DPDK-PVP-64-BYTES-1Q-2PMD-TEST  | 4 PMD threads on 2 Hyper threads using 64 byte packet size  |
| SKIP_1Q  | OVS-DPDK-PVP-1500-BYTES-1Q-2PMD-TEST  |  4 PMD threads on 2 Hyper threads using 1500 byte packet size |
| SKIP_2Q  | OVS-DPDK-PVP-64-BYTES-2Q-4PMD-TEST  | 8 PMD threads on 4 Hyper threads using 64 and 1500 byte packet size  |
|SKIP_2Q   | OVS-DPDK-PVP-1500-BYTES-2Q-4PMD-TEST  | 8 PMD threads on 4 Hyper threads using 64 and 1500 byte packet size  |
| SKIP_JUMBO  |  OVS-DPDK-PVP-2000-BYTES-1Q-2PMD-TEST | 4 PMD threads on 2 Hyper threads running 2000 byte packet size  |
| SKIP_JUMBO  | OVS-DPDK-PVP-9000-BYTES-2Q-4PMD-TEST  |  4 PMD threads on 2 Hyper threads running 9000 byte packet size |
|  SKIP_KERNEL | OVS-KERNEL-DATAPATH-PVP-64-Bytes-1Q-2PMD-TEST  |  Kernel datapath without DPDK enabled |
| SKIP_KERNEL  |  OVS-KERNEL-DATAPATH-PVP-1500-Bytes-2Q-4PMD-TEST | Kernel datapath without DPDK enabled  |

* **throughput-test/Perf-Verify.conf**

All the variables needed by scripts are sitting in this config file. We add few comments for some of them here.




*NIC1* and *NIC2*

They are the NIC names on DUT side, that will receive and forward packets on the DUT to the guest. In our case, p6p1 and p6p2, and they need to be enclosed by quotation marks.

*PMD_CPU*

To specify PMD_CPU, the script cpu_layout.py is needed. If dpdk and dpdk-tools have been installed, the script cpu_layout.py should be under folder /usr/share/dpdk/usertools. 

```
#python /usr/share/dpdk/usertools/cpu_layout.py
```
The command lstopo can tell which numa node the test NICs belong to. 
```
#lstopo
```


*TESTPMD descriptor size*

Please keep the numbers without change.


*NIC1_VF * and *NIC2_VF*

On Rhel8, VF nic name usually is NIC name + “v0”, for example, the name for ens1f0 vf 0 is ens1f0v0, so in this case, NIC1_VF=”ens1f0v0”.

*IMAGE INFO*   

Please download the compressed qcow2 image from below online storage and unzip to a NAS.  

http://people.redhat.com/zfang/rhel8.3-vsperf-1Q-noviommu.qcow2.tar.lrz  
http://people.redhat.com/zfang/rhel8.3-vsperf-2Q-noviommu.qcow2.tar.lrz  
http://people.redhat.com/zfang/rhel8.3-vsperf-1Q-viommu.qcow2.tar.lrz  
http://people.redhat.com/zfang/rhel8.3-vsperf-2Q-viommu.qcow2.tar.lrz

Then give the image paths to ONE_QUEUE_IMAGE and TWO_QUEUE_IMAGE.  
```
ONE_QUEUE_IMAGE="<NAS location>/rhel8.3-vsperf-1Q-noviommu.qcow2"         
TWO_QUEUE_IMAGE="<NAS location>/rhel8.3-vsperf-2Q-noviommu.qcow2"  
```       
Depending on your test scenario, you might use rhel8.3-vsperf-1Q-viommu.qcow2 and/or rhel8.3-vsperf-2Q-viommu.qcow2.

__NOTE:__ 
md5sum *.tar.lrz

55e664cb1917324d6b60e5b54296a941  rhel8.3-vsperf-1Q-noviommu.qcow2.tar.lrz  
b634ef21a92b972649602b300859bb47  rhel8.3-vsperf-1Q-viommu.qcow2.tar.lrz  
8eb67c970d5e26f0f41c7d57cd095136  rhel8.3-vsperf-2Q-noviommu.qcow2.tar.lrz  
05e45aa77395b926abe20d0230a79952  rhel8.3-vsperf-2Q-viommu.qcow2.tar.lrz  




##### Set hugepage and isolated CPU

```
#grubby --args='intel_iommu=on iommu=pt default_hugepagesz=1G hugepagesz=1G hugepages=32' --update-kernel=$(grubby --default-kernel)
```
Depending on your settings in throughput-test/Perf-Verify.conf, add all these cores to the tuned profile. As below is an example and you might change the cpu numbers.
```
#echo "isolated_cores=2,4,6,14,16,24,26,34,36" >> /etc/tuned/cpu-partitioning-variables.conf
# tuned-adm profile cpu-partitioning
# systemctl enable tuned
# reboot
```


### 2.2 Start testing

#### 2.2.1 Start Trex server

The T-Rex application must now be running on the T-Rex server for binary-search.py script to connect to it using the Python API as part of its execution. To start the server go to the folder where the T-Rex was installed.
```
#cd ~/trex/v2.82
#./t-rex-64 --no-ofed-check -i --no-scapy-server -c <number of isolated CPU>
```
You need to count the “number of isolated CPU” from the configuration file as below.
```
#cat /etc/tuned/cpu-partitioning-variables.conf
```
__NOTE :__ "-c" is a mandatory option here as the test script will verify it. This is a difference from ovs_perf test.

#### 2.2.2 Start test script on DUT

Turn on VF on test NICs. Please skip this step if you only run kernel datapath pvp test.

```
#echo 1 > /sys/bus/pci/devices/<pciid of test NIC1>/sriov_numvfs
#echo 1 > /sys/bus/pci/devices/<pciid of test NIC2>/sriov_numvfs
```
For example,
```
#echo 1 > /sys/bus/pci/devices/0000\:3b\:00.0/sriov_numvfs
#echo 1 > /sys/bus/pci/devices/0000\:3b\:00.1/sriov_numvfs
```

If there was an error “bash: echo: write error: Cannot allocate memory”, try below command and enable VF again:
```
#grubby --args='pci=realloc' --update-kernel=$(grubby --default-kernel)
```

Turn off spoof checking and turn on trust on VF:
```
#ip link set <test NIC1> vf 0 spoofchk off 
#ip link set <test NIC2> vf 0 spoofchk off 
#ip link set <test NIC1> vf 0 trust on 
#ip link set <test NIC2> vf 0 trust on
```

For example,
```
#ip link set ens1f0 vf 0 spoofchk off 
#ip link set ens1f1 vf 0 spoofchk off
#ip link set ens1f0 vf 0 trust on
#ip link set ens1f1 vf 0 trust on
```

Verify the VFs can be seen and spoofchk turned off:
```
# ip link show ens1f0
148: ens1f0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc mq master ovs-system state DOWN mode DEFAULT group default qlen 1000
    link/ether 3c:fd:fe:ea:f7:20 brd ff:ff:ff:ff:ff:ff
    vf 0     link/ether 00:00:00:00:00:00 brd ff:ff:ff:ff:ff:ff, spoof checking off, link-state auto, trust off
```

Please note that for certain NICs, for example, Intel X540-AT2, only dpdk 19.11+ can support promisc mode on SRIOV guest. If guest uses promisc mode, the PF setting needs to be PROMISC mode and VF trust setting needs to be turned on. As below is an example of host NIC settings for SRIOV test. Please check with the manufacturer for details.
```
# ip link show enp131s0f0
36: enp131s0f0: <BROADCAST,MULTICAST,PROMISC,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000
    link/ether a0:36:9f:08:2b:c4 brd ff:ff:ff:ff:ff:ff
    vf 0     link/ether 52:54:00:11:8f:ea brd ff:ff:ff:ff:ff:ff, spoof checking off, link-state auto, trust on, query_rss off
```

Once all settings are complete, it should be able to run the script to start testing:
```
#cd /root/RHEL_NIC_QUALIFICATION/throughput-test
#./main-perf-test.sh
```

This only needs to be executed on the DUT, not on the T-Rex server. The script will do pre-check, run 5 tests (10 modules) in a row and save logs. Any issues will be output to the terminal.

If the test has been running for 10 minutes then it should run all the tests for about 1.5 hours. As below is the first test.
```
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
::   SRIOV-VF-PCI-PASSTHROUGH-64-Bytes-1Q-2PMD-TEST
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
```



The table as below lists the test iterations and approximate duration.

| Modules in Test script   | Approximate duration  |
| ------------ | ------------ |
| Install packages | 5m |
|  OS DISTRO CHECK | <10s  |
|  HUGEPAGE CHECK |  <10s |
|  CONFIG CHECK | <10s  |
|  CONFIG FILE CHECK | <10s  |
|  NIC CARD CHECK | <10s  |
| RPM PACKAGES CHECK  |  <10s |
|  NETWORK CONNECTION CHECK | <10s  |
| OVS RUNNING CHECK  |  <10s |
|  SRIOV-VF-PCI-PASSTHROUGH-64-Bytes-1Q-2PMD-TEST | 5m (could be quite longer depending on the speed of VNF image downloading)  |
| SRIOV-VF-PCI-PASSTHROUGH-1500-Bytes-1Q-2PMD-TEST  |  5m |
|  OVS-DPDK-PVP-64-BYTES-1Q-2PMD-TEST | 10m  |
| OVS-DPDK-PVP-1500-BYTES-1Q-2PMD-TEST  | 10m   |
|  OVS-DPDK-PVP-64-BYTES-2Q-4PMD-TEST |  10m  |
| OVS-DPDK-PVP-1500-BYTES-2Q-4PMD-TEST  | 5m  |
|  OVS-DPDK-PVP-2000-BYTES-1Q-2PMD-TEST |  5m |
|  OVS-DPDK-PVP-9000-BYTES-2Q-4PMD-TEST | 5m  |
| OVS-KERNEL-DATAPATH-PVP-64-Bytes-1Q-2PMD-TEST  | 15m  |
| OVS-KERNEL-DATAPATH-PVP-1500-Bytes-2Q-4PMD-TEST  |  10m |
|  COPY CONFIG FILES TO LOG FOLDER | 5m  |
|   |  Around 90m in total |




##### Explanation of a few samples of logs


The scripts leverage beaker lib (more details at https://beaker-project.org/) and the output of the test script will look like this format:
```
:: [ 09:21:41 ] :: [   PASS   ] :: Command 'rm -rf /dev/hugepages/*' (Expected 0, got 0)
```
*PASS* means the command execution result is expected. In this case, we expect the command 'rm -rf /dev/hugepages/*' to execute successfully (return 0) and we “got 0” as expected, so this step PASS.

Another sample as below, no matter the command 'systemctl start openvswitch' executes OK (return 0) or NOK (return 1), this step will PASS anyways, as we expect 0 or 1.
```
:: [ 09:21:21 ] :: [   PASS   ] :: Command 'systemctl start openvswitch' (Expected 0,1, got 0)
```

As below the example shows a failure. It started python script binary-search.py, and then got Error with return code 1. As we expected 0, this step failed. The cause of this issue was that the Trex server was not started.
```
:: [ 07:54:23 ] :: [  BEGIN   ] :: Running 'python ./binary-search.py         --trex-host…
...
[2020-08-26 07:54:24.264970][PQO] Establishing connection to TRex server...
[2020-08-26 07:54:27.279155][PQO] *** [RPC] - Failed to get server response from tcp://10.19.107.76:4501
[2020-08-26 07:54:27.279395][PQO] Disconnecting from TRex server...
[2020-08-26 07:54:27.279408][PQO] Connection severed
[2020-08-26 07:54:27.295726][BSO] return code: 1
[2020-08-26 07:54:27.295818][BSO] ERROR: Acquiring trex port info exited with a non-zero return value
:: [ 07:54:28 ] :: [ FAIL ] :: Command 'python ./binary-search.py --trex-host=10.19.107.76 --traffic-generator=trex-txrx --frame-size=64 --traffic-direction=bidirectional --search-runtime=30 --search-granularity=0.5 --validation-runtime=10 --negative-packet-loss=fail --max-loss-pct=0.0 --rate-unit=% --rate=100' (Expected 0, got 1)
```
The failure below due to the test NIC PF down and command “ip link set *test_NIC* up” would fix the issue.
```
:: [ 23:25:18 ] :: [  BEGIN   ] :: Running 'virsh attach-device gg /root/RHEL_NIC_QUALIFICATION/throughput-test/vf1.xml'
error: Failed to attach device from /root/RHEL_NIC_QUALIFICATION/throughput-test/vf1.xml
error: internal error: Unable to configure VF 0 of PF 'ens1f0' because the PF is not online. Please change host network config to put the PF online.
:: [ 23:25:18 ] :: [   FAIL   ] :: Command 'virsh attach-device gg /root/RHEL_NIC_QUALIFICATION/throughput-test/vf1.xml' (Expected 0, got 1)
```

__NOTE__:

When you encounter any issues in the middle of the tests, such as an unacceptable failure like above FAIL examples, the script might not exit out but go to the next command or test. You could use Ctrl + C to stop the script and try to fix the issue then restart the script. The test script has the ability of cleaning up the environment, such as virsh undefine guest, restart service, etc.

Please note that the script will disable VF at some point during the tests, so if you believe you had enabled VF for previous tests, it might need to be enabled manually again (except kernel based tests). Use command “ip link show <test NIC>” to check, to enable VF by below commands if needed.
```
  #echo 1 > /sys/bus/pci/devices/<pciid of test NIC1>/sriov_numvfs
  #echo 1 > /sys/bus/pci/devices/<pciid of test NIC2>/sriov_numvfs
```
And then again disable VF spoof checking.
 ```
  #ip link set <test NIC1> vf 0 spoofchk off 
  #ip link set <test NIC2> vf 0 spoofchk off
```

Result logs are placed into the following folder '/root/RHEL_NIC_QUAL_LOGS/<date_time>'
The contents will appear as something similar to below.
```
drwxr-xr-x. 2 root root  116 Oct 16 17:50 2017-10-16-17:47:14
drwxr-xr-x. 2 root root  116 Oct 17 09:45 2017-10-17-09:41:09
drwxr-xr-x. 2 root root 4096 Oct 17 10:06 2017-10-17-09:55:18
-rw-r--r--. 1 root root   60 Oct 17 11:00 throughput_logs_folder.txt
```

Once this test has passed disable SR-IOV and begin execution of the functional QE scripts.





## 3. Running the OVS functional qualification test

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

Before starting the tests please uninstall openvswitch and reinstall openvswitch. This is because throughput-test does not
use systemctl to start openvswitch and can cause some db configuration problems when going back to using systemctl.
If using a custom openvswitch please re-install the custom version instead of the one from the fast datapath channel.

```
    yum remove openvswitch2.13
    yum install openvswitch2.13
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

## 4. Analyzing and gathering the results

To collect the results for the performance, throughtput and functional tests execute the collections.sh script on the
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

The files are throughput-test\_logs\_folder.txt and kernel\_functional\_logs.txt which point to specific folders.

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
