# Red Hat NIC NFV Qualification

The goal of this document is to guide you step by step through the process of
qualifying a NIC driver for NFV usage. This includes both the Linux Kernel
driver and the DPDK PMD driver.

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
running RHEL 7.4 or greater. The servers should be wired back to back from the
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




## Setup the TRex traffic generator
One of the two machines we will use for the TRex traffic generator. We will
also use this machine to run the actual PVP script, so some additional setup
steps are related to this.


Please check out the [TRex Installation Manual](https://trex-tgn.cisco.com/trex/doc/trex_manual.html#_download_and_installation)
for the minimal system requirements to run TRex. For example having a Haswell
or newer CPU. Also, do not forget to enable VT-d in the BIOS



### Register Red Hat Enterprise Linux
We continue here right after installing Red Hat Enterprise Linux. First need to
register the system, so we can download all the packages we need:

```
# subscription-manager register
Registering to: subscription.rhsm.redhat.com:443/subscription
Username: user@domain.com
Password:
The system has been registered with ID: xxxxxxxx-xxxx-xxxx-xxxxxxxxxxxxxxxxxx

# subscription-manager attach --pool=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
Successfully attached a subscription for: xxxxxxxxxxxxxxxxxx
```


### Install the packages we need
We need _"Red Hat Enterprise Linux Fast Datapath 7"_ for the DPDK package.
If you do not have access to these repositories, please contact your Red Had
representative.

```
subscription-manager repos --enable=rhel-7-fast-datapath-rpms
```


Add the epel repository for some of the python packages:

```
yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
```

Add the extras channel for the dpdk-tools package:

```
subscription-manager repos --enable rhel-7-server-extras-rpms
```

Now we can install the packages we need:

```
yum -y clean all
yum -y update
yum -y install dpdk dpdk-tools emacs gcc git lshw pciutils python-devel \
               python-setuptools python-pip tmux \
               tuned-profiles-cpu-partitioning wget
```


### Tweak the kernel
Rather than using the default 2M huge pages we configure 32 1G pages. You can
adjust this to your system's specifications. In this step we also enable iommu
needed by some of the DPDK PMD drivers used by TRex:

```
sed -i -e 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="default_hugepagesz=1G hugepagesz=1G hugepages=32 iommu=pt intel_iommu=on /'  /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg
```


### Download and installation of TRex
Download and unpack the TRex traffic generator:

```
mkdir trex
cd trex
wget http://trex-tgn.cisco.com/trex/release/v2.29.tar.gz
tar -xvzf v2.29.tar.gz
cd v2.29
```

Figure out PCI address of the card we would like to use, using the _lshw_
utility:

```
# lshw -c network -businfo
Bus info          Device     Class          Description
=======================================================
pci@0000:01:00.0  em1        network        82599ES 10-Gigabit SFI/SFP+ Network
pci@0000:01:00.1  em2        network        82599ES 10-Gigabit SFI/SFP+ Network
pci@0000:07:00.0  em3        network        I350 Gigabit Network Connection
pci@0000:07:00.1  em4        network        I350 Gigabit Network Connection
```

In our case, we will use em1, so PCI 0000:01:00.0. However as TRex likes
port pairs, we will also assign em2, 0000:01:00.1, to TRex.

__NOTE__: Make sure your network card has a kernel driver loaded, i.e. has a
_Device_ name in the output above, or else configuration in the step below
might fail.


Next step is to configure TRex:

```
# cd ~/trex/v2.29
# ./dpdk_setup_ports.py -i
By default, IP based configuration file will be created. Do you want to use MAC based config? (y/N)y
+----+------+---------+-------------------+------------------------------------------------+-----------+-----------+----------+
| ID | NUMA |   PCI   |        MAC        |                      Name                      |  Driver   | Linux IF  |  Active  |
+====+======+=========+===================+================================================+===========+===========+==========+
| 0  | 0    | 01:00.0 | 24:6e:96:3c:4b:c0 | 82599ES 10-Gigabit SFI/SFP+ Network Connection | ixgbe     | em1       |          |
+----+------+---------+-------------------+------------------------------------------------+-----------+-----------+----------+
| 1  | 0    | 01:00.1 | 24:6e:96:3c:4b:c2 | 82599ES 10-Gigabit SFI/SFP+ Network Connection | ixgbe     | em2       |          |
+----+------+---------+-------------------+------------------------------------------------+-----------+-----------+----------+
| 2  | 0    | 07:00.0 | 24:6e:96:3c:4b:c4 | I350 Gigabit Network Connection                | igb       | em3       | *Active* |
+----+------+---------+-------------------+------------------------------------------------+-----------+-----------+----------+
| 3  | 0    | 07:00.1 | 24:6e:96:3c:4b:c5 | I350 Gigabit Network Connection                | igb       | em4       |          |
+----+------+---------+-------------------+------------------------------------------------+-----------+-----------+----------+
Please choose even number of interfaces from the list above, either by ID , PCI or Linux IF
Stateful will use order of interfaces: Client1 Server1 Client2 Server2 etc. for flows.
Stateless can be in any order.
Enter list of interfaces separated by space (for example: 1 3) : 0 1

For interface 0, assuming loopback to it's dual interface 1.
Destination MAC is 24:6e:96:3c:4b:c2. Change it to MAC of DUT? (y/N).
For interface 1, assuming loopback to it's dual interface 0.
Destination MAC is 24:6e:96:3c:4b:c0. Change it to MAC of DUT? (y/N).
Print preview of generated config? (Y/n)y
### Config file generated by dpdk_setup_ports.py ###

- port_limit: 2
  version: 2
  interfaces: ['01:00.0', '01:00.1']
  port_info:
      - dest_mac: 24:6e:96:3c:4b:c2 # MAC OF LOOPBACK TO IT'S DUAL INTERFACE
        src_mac:  24:6e:96:3c:4b:c0
      - dest_mac: 24:6e:96:3c:4b:c0 # MAC OF LOOPBACK TO IT'S DUAL INTERFACE
        src_mac:  24:6e:96:3c:4b:c2

  platform:
      master_thread_id: 0
      latency_thread_id: 27
      dual_if:
        - socket: 0
          threads: [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26]


Save the config to file? (Y/n)y
Default filename is /etc/trex_cfg.yaml
Press ENTER to confirm or enter new file:
Saved to /etc/trex_cfg.yaml.
```

As we would like to run the performance script on this machine, we decided
to not dedicate all CPUs to TRex. Below you see what we changed in the
/etc/trex_cfg.yaml file to exclude threads 1-3:

```
    threads: [4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26]
```


### Tweak the system for TRex usage
We know which threads will be used by TRex, let's dedicate them to this task.
We do this by applying the cpu-partitioning profile and configure the isolated
core mask:

```
systemctl enable tuned
systemctl start tuned
echo isolated_cores=4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26 >> /etc/tuned/cpu-partitioning-variables.conf
tuned-adm profile cpu-partitioning
```

Now it's time to reboot the machine to active the isolated cores and use the
configured 1G huge pages:

```
# reboot
```


### Start the TRex server
Now we're ready to start the TRex server in a tmux session, so we can look at
the console if we want to:

```
cd ~/trex/v2.29
tmux
./t-rex-64 -i
```


## Installing the qualification scripts

As our TRex machine has enough resources to also run the qualification script
we decided to run it there. However, in theory, you can run the scripts on a
third machine or even the DUT. But make sure to keep the machine close to the
traffic generator, as it needs to communicate with it to capture statistics.

The exception to this are the _OVS functional qualification_ scripts they need
to be run on two machines. More details on this in the respective chapter.


### Install the scripts
First, we need to install the script on the machine:

```
cd ~
git clone https://github.com/ctrautma/RHEL_NIC_QUALIFICATION.git
cd RHEL_NIC_QUALIFICATION
git submodule update --init --recursive
ln -s ~/RHEL_NIC_QUALIFICATION/ovs_perf/ ~/ovs_perf
```

### Install additional packages needed by the PVP script
We need to install a bunch of Python libraries we need for the PVP script.

We will use pip to do this:

```
pip install --upgrade enum34 natsort netaddr matplotlib scapy spur
```


We also need the Xena Networks traffic generator libraries:

```
cd ~
git clone https://github.com/fleitner/XenaPythonLib
cd XenaPythonLib/
python setup.py install
```


Finally we need to install the TRex stateless libraries:

```
cd ~/trex/v2.29
tar -xzf trex_client_v2.29.tar.gz
cp -r trex_client/stl/trex_stl_lib/ ~/ovs_perf
cp -r trex_client/external_libs/ ~/ovs_perf/trex_stl_lib/

```




## Setup the Device Under Test (DUT), Open vSwitch
<a name="DUTsetup"/>

For this tutorial, we use Open vSwitch in combination with the DPDK,
userspace datapath. At the end of this document, we also explain how to
redo the configuration to use the Linux kernel datapath.


### Register Red Hat Enterprise Linux
As with the TRex system we first need to register the system:

```
# subscription-manager register
Registering to: subscription.rhsm.redhat.com:443/subscription
Username: user@domain.com
Password:
The system has been registered with ID: xxxxxxxx-xxxx-xxxx-xxxxxxxxxxxxxxxxxx

# subscription-manager attach --pool=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
Successfully attached a subscription for: xxxxxxxxxxxxxxxxxx
```


### Add the packages we need
We need _"Red Hat Enterprise Linux Fast Datapath 7"_ for Open vSwitch,
_"RHEL Extras"_ for dpdk rpms, and _"Red Hat Virtualization 4"_
for Qemu. If you do not have access to these repositories, please contact
your Red Had representative.

```
subscription-manager repos --enable=rhel-7-fast-datapath-rpms
subscription-manager repos --enable=rhel-7-server-rhv-4-mgmt-agent-rpms
subscription-manager repos --enable rhel-7-server-extras-rpms
subscription-manager repos --enable rhel-7-server-optional-rpms
```


Add the epel repository for sshpass and others:

```
yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
```


Now we can install the packages we need:

```
yum -y clean all
yum -y update
yum -y install aspell aspell-en autoconf automake bc checkpolicy \
               desktop-file-utils dpdk dpdk-tools driverctl emacs gcc \
               gcc-c++ gdb git graphviz groff hwloc intltool kernel-devel \
               libcap-ng libcap-ng-devel libguestfs libguestfs-tools-c libtool \
               libvirt lshw openssl openssl-devel openvswitch procps-ng python \
               python-six python-twisted-core python-zope-interface \
               qemu-kvm-rhev rpm-build selinux-policy-devel sshpass sysstat \
               systemd-units tcpdump time tmux tuned-profiles-cpu-partitioning \
               virt-install virt-manager wget
```



### Tweak the system for OVS-DPDK and Qemu usage
There is work in progress for Open vSwitch DPDK to play nicely with SELinux,
but for now, the easiest way is to disable it:

```
sed -i -e 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
setenforce permissive
```


Rather than using the default 2M huge pages we configure 32 1G pages. You can
adjust this to your system's specifications. In this step we also enable iommu
needed by the DPDK PMD driver:

```
sed -i -e 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="default_hugepagesz=1G hugepagesz=1G hugepages=32 iommu=pt intel_iommu=on/'  /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg
```


Our system is a single NUMA node using Hyper-Threading and we would like to
use the first Hyper-Threading pair for system usage. The remaining threads
we would like dedicate to Qemu and Open vSwitch.


__NOTE__ that if you have a multi-NUMA system the cores you assign to both Open
vSwitch and Qemu need to be one same NUMA node as the network card. For some
more background information on this see the [OVS-DPDK Parameters: Dealing with
multi-NUMA](https://developers.redhat.com/blog/2017/06/28/ovs-dpdk-parameters-dealing-with-multi-numa/)
blog post.


To figure out the numbers of threads, and the first thread pair we execute
the following:

```
# lscpu |grep -E "^CPU\(s\)|On-line|Thread\(s\) per core"
CPU(s):                28
On-line CPU(s) list:   0-27
Thread(s) per core:    2

# lstopo-no-graphics
Machine (126GB)
  Package L#0 + L3 L#0 (35MB)
    L2 L#0 (256KB) + L1d L#0 (32KB) + L1i L#0 (32KB) + Core L#0
      PU L#0 (P#0)
      PU L#1 (P#14)
    L2 L#1 (256KB) + L1d L#1 (32KB) + L1i L#1 (32KB) + Core L#1
      PU L#2 (P#1)
      PU L#3 (P#15)
    L2 L#2 (256KB) + L1d L#2 (32KB) + L1i L#2 (32KB) + Core L#2
      ...
      ...
```


Now we apply the cpu-partitioning profile, and configure the isolated
core mask:

```
systemctl enable tuned
systemctl start tuned
echo isolated_cores=1-13,15-27 >> /etc/tuned/cpu-partitioning-variables.conf
tuned-adm profile cpu-partitioning
```
<a name="isolcpus"/>

In addition, we would also like to remove these CPUs from the  SMP balancing
and scheduler algroithms. With the tuned cpu-partitioning starting with version
2.9.0-1 this can be done with the no_balance_cores= option. As this is not yet
available to us, we have to do this using the isolcpus option on the kernel
command line. This can be done as follows:

```
sed -i -e 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="isolcpus=1-13,15-27 /'  /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg
```


Now it's time to reboot the machine to active the isolated cores, and use the
configured 1G huge pages:

```
# reboot
...
# cat /proc/cmdline
BOOT_IMAGE=/vmlinuz-3.10.0-693.1.1.el7.x86_64 root=/dev/mapper/rhel_wsfd--netdev67-root ro default_hugepagesz=1G hugepagesz=1G hugepages=4 crashkernel=auto rd.lvm.lv=rhel_wsfd-netdev67/root rd.lvm.lv=rhel_wsfd-netdev67/swap console=ttyS1,115200 nohz=on nohz_full=1-13,15-27 rcu_nocbs=1-13,15-27 tuned.non_isolcpus=00004001 intel_pstate=disable nosoftlockup
```


## Running the _ovs\_perf_ script for the DPDK datapath

We first need to do some additional configuration before we can run the
_ovs\_perf_ script.


### Setup Open vSwitch
In the Open vSwitch DPDK configuration the physical interface is under direct
control of DPDK, hence it needs to be removed from the kernel. To do this
we first need to figure out the interface's PCI address. An easy way of doing
this is using the _lshw_ utility:

```
# lshw -c network -businfo
Bus info          Device      Class          Description
========================================================
pci@0000:01:00.0  em1         network        82599ES 10-Gigabit SFI/SFP+ Network Connection
pci@0000:01:00.1  em2         network        82599ES 10-Gigabit SFI/SFP+ Network Connection
pci@0000:07:00.0  em3         network        I350 Gigabit Network Connection
pci@0000:07:00.1  em4         network        I350 Gigabit Network Connection
```


For our performance test, we would like to use the 10GbE interface _em1_. You
could use the _dpdk-devbind_ utility to bind the interface to DPDK, however,
this configuration will not survive a reboot. The preferred solution is to use
_driverctl_:

```
# driverctl -v set-override 0000:01:00.0 vfio-pci
driverctl: setting driver override for 0000:01:00.0: vfio-pci
driverctl: loading driver vfio-pci
driverctl: unbinding previous driver ixgbe
driverctl: reprobing driver for 0000:01:00.0
driverctl: saving driver override for 0000:01:00.0

# lshw -c network -businfo
Bus info          Device      Class          Description
========================================================
pci@0000:01:00.0              network        82599ES 10-Gigabit SFI/SFP+ Network Connection
pci@0000:01:00.1  em2         network        82599ES 10-Gigabit SFI/SFP+ Network Connection
pci@0000:07:00.0  em3         network        I350 Gigabit Network Connection
pci@0000:07:00.1  em4         network        I350 Gigabit Network Connection

```


Start Open vSwitch, and automatically start it after every reboot:

```
systemctl enable openvswitch
systemctl start openvswitch
```


For OVS-DPDK we would like to use the second Hyper Thread pair (CPU 1,15) for
the PMD threads. And the third Hyper Thread pair (CPU 2,16) for the none PMD
DPDK threads. To configure this we execute the following commands:

```
ovs-vsctl set Open_vSwitch . other_config:dpdk-init=true
ovs-vsctl set Open_vSwitch . other_config:dpdk-socket-mem=2048
ovs-vsctl set Open_vSwitch . other_config:pmd-cpu-mask=0x00008002
ovs-vsctl set Open_vSwitch . other_config:dpdk-lcore-mask=0x00010004
systemctl restart openvswitch
```

For the Physical to Virtual back to Physical(PVP) test we only need one bridge
with two ports. In addition, we will configure our interfaces with 2 receive
queues:

```
ovs-vsctl --if-exists del-br ovs_pvp_br0
ovs-vsctl add-br ovs_pvp_br0 -- \
          set bridge ovs_pvp_br0 datapath_type=netdev
ovs-vsctl add-port ovs_pvp_br0 dpdk0 -- \
          set Interface dpdk0 type=dpdk -- \
          set Interface dpdk0 options:dpdk-devargs=0000:01:00.0 -- \
          set interface dpdk0 options:n_rxq=2 \
            other_config:pmd-rxq-affinity="0:1,1:15" -- \
          set Interface dpdk0 ofport_request=1
ovs-vsctl add-port ovs_pvp_br0 vhost0 -- \
          set Interface vhost0 type=dpdkvhostuserclient -- \
          set Interface vhost0 options:vhost-server-path="/tmp/vhost-sock0" -- \
          set interface vhost0 options:n_rxq=2 \
            other_config:pmd-rxq-affinity="0:1,1:15" -- \
          set Interface vhost0 ofport_request=2
```


### Create the loopback Virtual Machine

Get the [Red Hat Enterprise Linux 7.4 KVM Guest Image](https://access.redhat.com/downloads/content/69/ver=/rhel---7/7.4/x86_64/product-software).
If you do not have access to the image please contact your Red Had
representative. Copy the image for use by qemu:

```
# ls -l ~/*.qcow2
-rw-r--r--. 1 root root 556247552 Jul 13 06:10 rhel-server-7.4-x86_64-kvm.qcow2
```
```
mkdir -p /opt/images
cp ~/rhel-server-7.4-x86_64-kvm.qcow2 /opt/images
```


Start and enable libvirtd:

```
systemctl enable libvirtd.service
systemctl start libvirtd.service
```


Setup as much as possible with a single call to _virt-install_:

```
# virt-install --connect=qemu:///system \
  --network vhostuser,source_type=unix,source_path=/tmp/vhost-sock0,source_mode=server,model=virtio,driver_queues=2 \
  --network network=default \
  --name=rhel_loopback \
  --disk path=/opt/images/rhel-server-7.4-x86_64-kvm.qcow2,format=qcow2 \
  --ram 8192 \
  --memorybacking hugepages=on,size=1024,unit=M,nodeset=0 \
  --vcpus=4,cpuset=3,4,5,6 \
  --check-cpu \
  --cpu Haswell-noTSX,+pdpe1gb,cell0.id=0,cell0.cpus=0,cell0.memory=8388608 \
  --numatune mode=strict,nodeset=0 \
  --nographics --noautoconsole \
  --import \
  --os-variant=rhel7
```

If you have a multi-NUMA system and you are not on NUMA node 0, you need to
change the _nodeset_ values above accordingly.


Note that we have been using cores 1,2,15,16 for OVS, and above we have assigned
cores 3-6 to the loopback Virtual Machine (VM). For optimal performance we need
to pin the vCPUs to real CPUs. In addition, we will also assign an additional
core for Qemu related task to make sure they will not interrupt any PMD threads
running in the VM:

```
virsh vcpupin rhel_loopback 0 3
virsh vcpupin rhel_loopback 1 4
virsh vcpupin rhel_loopback 2 5
virsh vcpupin rhel_loopback 3 6
virsh emulatorpin rhel_loopback 7
```

We need to tweak some Virtual Machine profile settings manually, as not all
options are available through _virt-install_. This is related to memory sharing,
and pinning of the Virtual Machine to dedicated CPUs (the above commands will
no survive a reboot). We will do this using _virsh edit_. Below are the
commands used, and the diff of the applied changes:

```
# virsh shutdown rhel_loopback
# virsh edit rhel_loopback

diff:
@@ -18,2 +18,9 @@
   <vcpu placement='static' cpuset='3-6'>4</vcpu>
+  <cputune>
+    <vcpupin vcpu='0' cpuset='3'/>
+    <vcpupin vcpu='1' cpuset='4'/>
+    <vcpupin vcpu='2' cpuset='5'/>
+    <vcpupin vcpu='3' cpuset='6'/>
+    <emulatorpin cpuset='7'/>
+  </cputune>
   <numatune>
@@ -33,3 +40,3 @@
     <numa>
-      <cell id='0' cpus='0' memory='8388608' unit='KiB'/>
+      <cell id='0' cpus='0' memory='8388608' unit='KiB' memAccess='shared'/>
     </numa>
```


Tweak the virtual machine such that it will have the interfaces named trough
network manager, and the cloud configuration removed on the next boot:

```
# LIBGUESTFS_BACKEND=direct virt-customize -d rhel_loopback \
  --root-password password:root \
  --firstboot-command 'rm /etc/systemd/system/multi-user.target.wants/cloud-config.service' \
  --firstboot-command 'rm /etc/systemd/system/multi-user.target.wants/cloud-final.service' \
  --firstboot-command 'rm /etc/systemd/system/multi-user.target.wants/cloud-init-local.service' \
  --firstboot-command 'rm /etc/systemd/system/multi-user.target.wants/cloud-init.service' \
  --firstboot-command 'nmcli c | grep -o --  "[0-9a-fA-F]\{8\}-[0-9a-fA-F]\{4\}-[0-9a-fA-F]\{4\}-[0-9a-fA-F]\{4\}-[0-9a-fA-F]\{12\}" | xargs -n 1 nmcli c delete uuid' \
  --firstboot-command 'nmcli con add con-name ovs-dpdk ifname eth0 type ethernet ip4 1.1.1.1/24' \
  --firstboot-command 'nmcli con add con-name management ifname eth1 type ethernet' \
  --firstboot-command 'reboot'
```


Start the VM, and attach to the console:

```
# virsh start rhel_loopback
Domain rhel_loopback started

# virsh console rhel_loopback
Connected to domain rhel_loopback
Escape character is ^]

[root@localhost ~]#
```

The VM needs the same tweaking as the OVS-DPDK instance. Below is a quick
command sequence that needs to be executed on the VM. For details see the
beginning of the [Setup the Device Under Test (DUT), Open vSwitch](#DUTsetup)
section above:

```
[root@localhost ~]# subscription-manager register
[root@localhost ~]# subscription-manager attach --pool=xxxxxxxxxxxxxxxxxxxxxxxxx
[root@localhost ~]# subscription-manager repos --enable=rhel-7-fast-datapath-rpms
[root@localhost ~]# yum -y clean all
[root@localhost ~]# yum -y update
[root@localhost ~]# yum -y install driverctl gcc kernel-devel numactl-devel tuned-profiles-cpu-partitioning wget
[root@localhost ~]# yum -y update kernel
[root@localhost ~]# sed -i -e 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="default_hugepagesz=1G hugepagesz=1G hugepages=2 /'  /etc/default/grub
[root@localhost ~]# grub2-mkconfig -o /boot/grub2/grub.cfg
[root@localhost ~]# echo "options vfio enable_unsafe_noiommu_mode=1" > /etc/modprobe.d/vfio.conf
[root@localhost ~]# driverctl -v set-override 0000:00:02.0 vfio-pci
[root@localhost ~]# systemctl enable tuned
[root@localhost ~]# systemctl start tuned
[root@localhost ~]# echo isolated_cores=1,2,3 >> /etc/tuned/cpu-partitioning-variables.conf
[root@localhost ~]# tuned-adm profile cpu-partitioning
[root@localhost ~]# reboot
```


We need the _testpmd_ tool from DPDK on this VM. As an exercise we build it
from source:

```
[root@localhost ~]# cd ~
[root@localhost ~]# wget http://fast.dpdk.org/rel/dpdk-17.08.tar.xz
[root@localhost ~]# tar xf dpdk-17.08.tar.xz
[root@localhost ~]# cd dpdk-17.08
[root@localhost dpdk-17.08]# make install T=x86_64-native-linuxapp-gcc DESTDIR=_install
[root@localhost dpdk-17.08]# ln -s /root/dpdk-17.08/x86_64-native-linuxapp-gcc/app/testpmd /usr/bin/testpmd
```

You can quickly check if your VM is setup correctly by starting _testpmd_
as follows:

```
[root@localhost dpdk-17.08]# cd ~
[root@localhost dpdk-17.08]# testpmd -c 0x7 -n 4 --socket-mem 1024,0 -w 0000:00:02.0 -- \
  --burst 64 --disable-hw-vlan -i --rxq=2 --txq=2 \
  --rxd=4096 --txd=1024 --coremask=0x6 --auto-start \
  --port-topology=chained

EAL: Detected 4 lcore(s)
EAL: Probing VFIO support...
EAL: WARNING: cpu flags constant_tsc=yes nonstop_tsc=no -> using unreliable clock cycles !
EAL: PCI device 0000:00:02.0 on NUMA socket -1
EAL:   Invalid NUMA socket, default to 0
EAL:   probe driver: 1af4:1000 net_virtio
Interactive-mode selected
previous number of forwarding cores 1 - changed to number of configured cores 2
Auto-start selected
USER1: create a new mbuf pool <mbuf_pool_socket_0>: n=163456, size=2176, socket=0
Configuring Port 0 (socket 0)
Port 0: 52:54:00:70:39:86
Checking link statuses...
Done
Start automatic packet forwarding
io packet forwarding - ports=1 - cores=2 - streams=2 - NUMA support enabled, MP over anonymous pages disabled
Logical Core 1 (socket 0) forwards packets on 1 streams:
  RX P=0/Q=0 (socket 0) -> TX P=0/Q=0 (socket 0) peer=02:00:00:00:00:00
Logical Core 2 (socket 0) forwards packets on 1 streams:
  RX P=0/Q=1 (socket 0) -> TX P=0/Q=1 (socket 0) peer=02:00:00:00:00:00

  io packet forwarding - CRC stripping enabled - packets/burst=64
  nb forwarding cores=2 - nb forwarding ports=1
  RX queues=2 - RX desc=4096 - RX free threshold=0
  RX threshold registers: pthresh=0 hthresh=0 wthresh=0
  TX queues=2 - TX desc=1024 - TX free threshold=0
  TX threshold registers: pthresh=0 hthresh=0 wthresh=0
  TX RS bit threshold=0 - TXQ flags=0xf00
testpmd> quit
Telling cores to stop...
Waiting for lcores to finish...

  ---------------------- Forward statistics for port 0  ----------------------
  RX-packets: 0              RX-dropped: 0             RX-total: 0
  TX-packets: 0              TX-dropped: 0             TX-total: 0
  ----------------------------------------------------------------------------

  +++++++++++++++ Accumulated forward statistics for all ports+++++++++++++++
  RX-packets: 0              RX-dropped: 0             RX-total: 0
  TX-packets: 0              TX-dropped: 0             TX-total: 0
  ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

Done.

Shutting down port 0...
Stopping ports...
Done
Closing ports...
Done

Bye...

Shutting down port 0...
Stopping ports...
Done
Closing ports...
Port 0 is already closed
Done

Bye...
[root@localhost ~]#
```

Finally get the IP address assigned to this VM, as we need it later when
executing the PVP script.

```
[root@localhost ~]# ip address show eth1
3: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP qlen 1000
    link/ether 52:54:00:06:7e:0a brd ff:ff:ff:ff:ff:ff
    inet 192.168.122.5/24 brd 192.168.122.255 scope global dynamic eth1
       valid_lft 3590sec preferred_lft 3590sec
    inet6 fe80::1c38:e5d7:1687:d254/64 scope link
       valid_lft forever preferred_lft forever
```

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
[_ovs\_perf_](https://github.com/chaudron/ovs_perf/blob/master/README.md#full-day-pvp-test)
documentation. This is done running the included __runfullday.sh__ script.

```
$ ./runfullday.sh
This script will run the tests as explained in the "Full day PVP test"
section. It will start the scripts according to the configuration given below,
and will archive the results.

NOTE: Make sure you are passing the basic test as explained in "Running the
      PVP script" before starting the full day run!

This script will run the tests as explained in the "Full day PVP test"
section. It will start the scripts according to the configuration given below,
and will archive the results.

NOTE: Make sure you are passing the basic test as explained in "Running the
      PVP script" before starting the full day run!

What datapath are you using, DPDK or Linux Kernel [dpdk/kernel/tc]? dpdk
What is the IP address where the DUT (Open vSwitch) is running? 10.19.17.133
What is the root password of the DUT? root
What is the IP address of the virtual machine running on the DUT? 192.168.122.186
What is the IP address of the TRex tester? localhost
What is the physical interface being used, i.e. dpdk0, em1, p4p5? dpdk0
What is the virtual interface being used, i.e. vhost0, vnet0? vhost0
What is the virtual interface PCI id? 0000:00:06.0
What is the TRex tester physical interface being used? 0
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
All tests are done, results are saved in: "/root/pvp_results_2017-10-12_055506_dpdk.tgz"
```




## Running the _ovs\_perf_ script for the Linux Kernel datapath

With the above setup, we ran the PVP tests with the Open vSwitch DPDK datapath.
This section assumes you have the previous configuration running, and explains
the steps to convert it to a Linux datapath setup.

### Configuring the Linux Kernel datapath

See the main  [_ovs\_perf_ script documentation](https://github.com/chaudron/ovs_perf#open-vswitch-with-linux-kernel-datapath)
on how to configure the Kernel datapath.


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
[_ovs\_perf_](https://github.com/chaudron/ovs_perf/blob/master/README.md#full-day-pvp-test)
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
What is the TRex tester physical interface being used? 0
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

See the main  [_ovs\_perf_ script documentation](https://github.com/chaudron/ovs_perf#open-vswitch-with-linux-kernel-datapath-and-tc-flower-offload)
on how to configure the Kernel datapath with TC Flower offload.


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
  --skip-pv-test \
  --warm-up
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
  * Doing flow table warm-up...
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
[_ovs\_perf_](https://github.com/chaudron/ovs_perf/blob/master/README.md#full-day-pvp-test)
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
What is the TRex tester physical interface being used? 0
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

    TRAFFICGEN_TREX_BASE_DIR='/root/trex/v2.29'

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

To setup these tests git clone the qualification suite onto the Server.

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

Inside the rh_nic_cert folder is a rh_nic_cert.sh script. This script has settings at the top
that must be completed as follows

  1. 'CLIENTS' must be set to the DUT hostname

  2. 'SERVERS' must be set to the server hostname

  3. 'NIC_CLIENT' must be set to the NIC device names on the DUT

  4. 'NIC_SERVER' must be set to the NIC device name on the server which will be used to send traffic

  5. If doing the topology with a switch then it must be defined correctly in the bin/swlist file
     and referenced by the correct name for the 'SW_NAME' parameter in the rh_nic_cert.sh. The following
     must be correct in the bin/swlist file. This only needs to be done on the client side.

     a. Make sure the SW_NAME specified in the rh_nic_cert.sh 'SW_NAME' appears in the SWITCH LIST

     b. Populate the values needed for a pre-defined switch name or create a new one


         set SWITCH(5010,ostype)         "cisco-nxos"

         set SWITCH(5010,login)          "redhat@10.x.x.x"

         set SWITCH(5010,passwd)         "password"

         set SWITCH(5010,prompt)         "sw-5010"

         set SWITCH(5010,spid)           -1

     c. 'ostype' needs to be the type of switch

     d. 'login' needs to be the username and ip for ssh login

     e. 'passwd' password for the switch

     f. 'prompt' the prompt on the switch CLI

     g. 'spid' leave it as -1

  6. Back to the rh_nic_cert.sh continue with 'SW_PORT_CLIENT' the switch ports the client side is connected
     to

  7. 'SW_PORT_SERVER' the switch port where the server is connected

  8. 'IMG_GUEST' this specifies the location of the IMG to use for testing. For 7.4 testing leave it as is. For 7.5
     please modify the location to http://people.redhat.com/ctrautma/RHEL7-5VNF-1Q.qcow2.lrz

  9. 'SRC_NETPERF' set to use the following location people.redhat.com/ctrautma/netperf-20160222.tar.bz2

  10. 'RPM_KERNEL' leave alone, internal use only

  11. 'IPERF_RPM' leave alone, already set to an external location to download iperf

  12. 'SETENFORCE' leave alone

  13. 'QE_SKIP_TEST' can be set to skip particular tests, leave alone unless wanting to skip bonding tests

  14. 'QE_TEST' leave alone unless wanting to run a specific test only

  15. 'BONDING_TEST' set of bonding tests to execute, can be modified if wishing to run a specific test only

  16. 'RPM_OVS' change to the current RPM name from

```
    rpm -qa | grep openvswitch
```

Make sure the settings in rh_nic_cert.sh are completed on both the server and client systems.

Then you can execute rh_nic_cert.sh from both the server and client systems.

```
    ./rh_nic_cert.sh
```

The tests will execute for 4-6 hours and report the results at the end.

## Analyzing and gathering the results

To collect the results for the performance and functional tests execute the collections.sh script on the
client only which will attempt to retrieve the most recent results from the system and provides a file.
Provide this file to the certification team for review.

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
