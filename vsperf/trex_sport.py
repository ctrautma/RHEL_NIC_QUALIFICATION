#!/usr/bin/env python
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   trex_sport.py of /kernel/networking/vnic/sriov_dpdk_pft
#   Author: Hekai Wang <hewang@redhat.com>
#
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


import sys
import getopt

sys.path.append('/opt/trex/current/automation/trex_control_plane/stl/examples')
sys.path.append('./v2.48/automation/automation/trex_control_plane/interactive/trex/examples')
sys.path.append('./v2.48/automation/trex_control_plane/interactive/trex/examples/stl')

import stl_path
from trex_stl_lib.api import *
import json
import argparse

#import trex
#import trex_stl_lib


class TrexTest(object):
    def __init__(self, trex_host,pkt_size=64,duration=10,max_try=10,vlan_flag=False,dst_mac=None):
        self.trex_host = trex_host
        self.pkt_size = pkt_size
        self.duration = duration
        self.max_try = max_try         
        self.vlan_flag = vlan_flag
        self.dst_mac = dst_mac
        pass
    
    def create_stl_client(self):
        self.client = None
        self.client = STLClient(server=self.trex_host)
        return self.client
    

    def build_test_stream_basic(self):
        l2 = Ether()
        if self.vlan_flag == True:
            self.base_pkt = l2/Dot1Q(vlan=3)/IP(src="192.168.100.10",dst="192.168.100.20")/UDP(dport=12, sport=1025)
        else:
            self.base_pkt = l2/IP(src="192.168.100.10", dst="192.168.100.20")/UDP(dport=12, sport=1025)

        self.pad = max(0, self.pkt_size - len(self.base_pkt)) * 'x'

        return  STLStream(isg=10.0,
                        packet=STLPktBuilder(pkt=self.base_pkt/self.pad),
                        #flow_stats=STLFlowStats(pg_id=1),
                        flow_stats=None,
                        mode=STLTXCont(percentage=100)
                        )
        pass

    def build_test_stream(self):
        self.all_stream = []
        temp_stream = self.build_test_stream_basic()
        self.all_stream.append(temp_stream)
        self.streams = STLProfile(streams=self.all_stream).get_streams()
        return self.streams

    def test_stream_create(self,src_mac,dst_mac):
        l2 = Ether(dst=dst_mac,src=src_mac)
        pad = max(0, self.pkt_size - len(l2)) * 'x'
        return STLStream(isg=10.0,
                packet=STLPktBuilder(pkt=l2 / pad),
                #flow_stats=STLFlowStats(pg_id=1),
                flow_stats=None,
                mode=STLTXCont(percentage=100)
                )

    def test_conn_ok(self):
        if self.client:
            all_ports = self.client.get_all_ports()
            self.client.reset(all_ports)
            self.port_stream_map = {}
            # import pdb
            # pdb.set_trace()
            self.dst_mac_list = str(self.dst_mac).split(" ")
            all_stream = []
            all_stream.append(self.test_stream_create(
                self.dst_mac_list[0], self.dst_mac_list[1]))
            all_stream.append(self.test_stream_create(
                self.dst_mac_list[1], self.dst_mac_list[0]))
            for port in all_ports:
                for stream in all_stream:
                    self.client.reset(all_ports)
                    self.client.set_port_attr(ports=all_ports, promiscuous=True)
                    self.client.acquire(ports=all_ports, force=True)
                    self.client.add_streams(stream, ports=port)
                    print("start test conn test with 1pps duration 10s ")
                    self.client.start(ports=port,mult="1pps", duration=5)
                    self.client.wait_on_traffic(ports=all_ports)
                    ret_stat=self.client.get_stats(ports = all_ports)
                    # from pprint import pprint
                    # pprint(ret_stat)
                    """
                    'total': {'ibytes': 680,
                    'ierrors': 0,
                    'ipackets': 10,
                    'obytes': 680,
                    'oerrors': 0,
                    'opackets': 10,
                    'rx_bps': 538.2561645507812,
                    'rx_bps_L1': 696.5668067932129,
                    'rx_pps': 0.9894415140151978,
                    'rx_util': 6.965668067932129e-06,
                    'tx_bps': 538.7817132472992,
                    'tx_bps_L1': 697.2469528019428,
                    'tx_pps': 0.9904077472165227,
                    'tx_util': 6.9724695280194286e-06}}
                    """
                    if ret_stat["total"]["ipackets"] == ret_stat["total"]["opackets"]:
                        print("Port info {}".format(port))
                        print(self.client.get_port_attr(port))
                        print("Below Stream Info")
                        stream.to_pkt_dump()
                        self.port_stream_map[port] = stream
            if len(self.port_stream_map) > 0 :
                return True
            else:
                return False
        else:
            return False

    def test_one_cycle(self,speed_percent="100%",duration=10):
        all_ports = self.client.get_all_ports()
        self.client.reset(all_ports)
        self.client.set_port_attr(ports=all_ports, promiscuous=True)
        self.client.acquire(ports=all_ports,force=True)
        for key in self.port_stream_map.keys():
            self.client.add_streams(self.port_stream_map[key],ports=key)
        #self.client.add_streams(self.streams,ports=all_ports)
        self.client.clear_stats()
        print("start {} throughput begin".format(speed_percent))
        self.client.start(ports=all_ports, mult=speed_percent, duration=duration)
        self.client.wait_on_traffic(ports=all_ports)
        return self.client.get_stats(ports=all_ports)

    def start_test(self):
        self.client.connect()
        self.test_conn_ok()
        max_value = 100
        min_value = 0
        cur_value = 100
        for i in range(self.max_try):
            print("Current try {} cycle ".format(i))
            stat = self.test_one_cycle(str(cur_value)+"%")
            """
            {
                "global": {
                    "cpu_util": 20.869110107421875,
                    "rx_cpu_util": 0.0,
                    "bw_per_core": 21.410884857177734,
                    "tx_bps": 15638914048.0,
                    "tx_pps": 27150892.0,
                    "rx_bps": 13119664128.0,
                    "rx_pps": 22777192.0,
                    "rx_drop_bps": 2519249920.0,
                    "queue_full": 0
                },
                "1": {
                    "opackets": 135869430,
                    "ipackets": 113993959,
                    "obytes": 9782598960,
                    "ibytes": 8207565048,
                    "oerrors": 0,
                    "ierrors": 0,
                    "tx_bps": 7819472384.0,
                    "tx_pps": 13575472.0,
                    "tx_bps_L1": 9991547904.0,
                    "tx_util": 99.91547904,
                    "rx_bps": 6560308736.0,
                    "rx_pps": 11389424.0,
                    "rx_bps_L1": 8382616576.0,
                    "rx_util": 83.82616576000001
                },
                "0": {
                    "opackets": 135869430,
                    "ipackets": 113970768,
                    "obytes": 9782598960,
                    "ibytes": 8205895296,
                    "oerrors": 0,
                    "ierrors": 0,
                    "tx_bps": 7819441664.0,
                    "tx_pps": 13575420.0,
                    "tx_bps_L1": 9991508864.0,
                    "tx_util": 99.91508864000001,
                    "rx_bps": 6559354880.0,
                    "rx_pps": 11387768.0,
                    "rx_bps_L1": 8381397760.0,
                    "rx_util": 83.8139776
                },
                "total": {
                    "opackets": 271738860,
                    "ipackets": 227964727,
                    "obytes": 19565197920,
                    "ibytes": 16413460344,
                    "oerrors": 0,
                    "ierrors": 0,
                    "tx_bps": 15638914048.0,
                    "tx_pps": 27150892.0,
                    "tx_bps_L1": 19983056768.0,
                    "tx_util": 199.83056768,
                    "rx_bps": 13119663616.0,
                    "rx_pps": 22777192.0,
                    "rx_bps_L1": 16764014336.0,
                    "rx_util": 167.64014336000002
                },
                "flow_stats": {},
                "latency": {}
            }
            """
            print(json.dumps(stat, indent=4, sort_keys=False))
            if stat["total"]["opackets"] > stat["total"]["ipackets"]:
                max_value = cur_value
                cur_value = (min_value + max_value)/(2 * 1.0)
            else:
                self.last_value = cur_value
                min_value = cur_value
                cur_value = (min_value + max_value)/(2 * 1.0)
                last_result = json.dumps(stat["total"], indent=4, sort_keys=False)
                self.last_value = cur_value
                self.last_result = last_result
                print(last_result)
        
        self.client.disconnect()
        return self.last_result

    def report_test_result(self):
        print("x"*100)
        
        if self.last_result:
            print(self.last_result)
        else:
            print("Trex throughput performance failed ")
        print("x"*100)

    def start_trex_server(self):
        #trex.CTRexClient
        #import trex_client.stf.trex_stf_lib
        trex = trex_client.CTRexClient(self.trex_host)
        trex.force_kill(confirm=False)
        time.sleep(3)
        print("Before Running, TRex status is: {}".format(trex.is_running()))
        print("Before Running, TRex status is: {}".format(trex.get_running_status()))

        self.trex_config = trex.get_trex_config()
        import yaml
        t_config_obj = yaml.load(self.trex_config)
        """
        - version: 2
        interfaces: ['05:00.0', '05:00.1']
        #interfaces: ['enp5s0f0', 'enp5s0f1']
        port_info:
            - dest_mac: 90:e2:ba:29:bf:15 # MAC OF LOOPBACK TO IT'S DUAL INTERFACE
              src_mac:  90:e2:ba:29:bf:14
            - dest_mac: 90:e2:ba:29:bf:14 # MAC OF LOOPBACK TO IT'S DUAL INTERFACE
              src_mac:  90:e2:ba:29:bf:15

        platform:
            master_thread_id: 0
            latency_thread_id: 1
            dual_if:
                - socket: 0
                threads: [2,4,6,8,10,12,14]
        """
        core_num = len(t_config_obj[0]['platform']['dual_if'][0]['threads'])
        #t_config_obj["platform"]["dual_if"]["threads"].len()
        trex.trex_args = "-c {}".format(core_num)
        trex.start_stateless()
        #trex.get_trex_config()
        print("After Starting, TRex status is: {},{}".format(trex.is_running(), trex.get_running_status()))
        print("Is TRex running? {},{}".format(trex.is_running(), trex.get_running_status()))
        self.trex = trex 
        self.trex_config = trex.get_trex_config()
        return self.trex

    def start_all_test(self):
        self.start_trex_server()
        import time
        time.sleep(60)
        self.create_stl_client()
        self.build_test_stream()
        self.start_test()
        self.report_test_result()

if __name__ == "__main__":
    sys.path.append('./v2.48/automation/trex_control_plane/stf/trex_stf_lib/')
    import trex_client
    import trex_status

    parser = argparse.ArgumentParser(description='Test ovs dpdk bonding trex')
    parser.add_argument('-c', '--connect',  type=str,help='trex server ip ', required=True)
    parser.add_argument('-m', '--maxcycle', type=int,help='get no loss packets cycle times', required=False)
    parser.add_argument('-t', '--time', type=int,help='one time test duration', required=False)
    parser.add_argument('-s', '--pkt_size', type=int,help='init packet size', required=False)
    parser.add_argument('-v', '--vlan', type=bool,help='enable vlan or else', required=False)
    parser.add_argument('-d', '--dst_mac', type=str,help='packet dest mac', required=False)
    args = parser.parse_args()
    print(args)
    if args.connect:
        trex_obj = TrexTest(args.connect,
        pkt_size=args.pkt_size,
        duration=args.time,
        max_try=args.maxcycle,
        vlan_flag=args.vlan,
        dst_mac=args.dst_mac)
        trex_obj.start_all_test()
    else:
        parser.print_help()
        import sys
        sys.exit(1)


