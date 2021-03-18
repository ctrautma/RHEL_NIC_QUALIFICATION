import argparse
import csv
import glob
import io
import os
import re
import sys
import tarfile
import xlsxwriter

if sys.version_info[0] == 3:
    raw_input = input

DPDK_L3_PVP_PNGS = ['root/pvp_results_1_l3_dpdk/test_p2v2p_all_l3_ref.png',
                    'root/pvp_results_1_l3_dpdk/test_p2v2p_all_l3.png',
                    'root/pvp_results_1_l3_dpdk/test_p2v2p_1000000_l3.png',
                    'root/pvp_results_1_l3_dpdk/test_p2v2p_100000_l3.png',
                    'root/pvp_results_1_l3_dpdk/test_p2v2p_10000_l3.png',
                    'root/pvp_results_1_l3_dpdk/test_p2v2p_1000_l3.png',
                    'root/pvp_results_1_l3_dpdk/test_p2v2p_10_l3.png',]

DPDK_L2_PVP_PNGS = ['root/pvp_results_1_l2_dpdk/test_p2v2p_all_l2_ref.png',
                    'root/pvp_results_1_l2_dpdk/test_p2v2p_all_l2.png',
                    'root/pvp_results_1_l2_dpdk/test_p2v2p_1000000_l2.png',
                    'root/pvp_results_1_l2_dpdk/test_p2v2p_100000_l2.png',
                    'root/pvp_results_1_l2_dpdk/test_p2v2p_10000_l2.png',
                    'root/pvp_results_1_l2_dpdk/test_p2v2p_1000_l2.png',
                    'root/pvp_results_1_l2_dpdk/test_p2v2p_10_l2.png',]

KERNEL_L3_PVP_PNGS = ['root/pvp_results_1_l3_kernel/test_p2v2p_all_l3_ref.png',
                      'root/pvp_results_1_l3_kernel/test_p2v2p_all_l3.png',
                      'root/pvp_results_1_l3_kernel/test_p2v2p_1000000_l3.png',
                      'root/pvp_results_1_l3_kernel/test_p2v2p_100000_l3.png',
                      'root/pvp_results_1_l3_kernel/test_p2v2p_10000_l3.png',
                      'root/pvp_results_1_l3_kernel/test_p2v2p_1000_l3.png',
                      'root/pvp_results_1_l3_kernel/test_p2v2p_10_l3.png',]

KERNEL_L2_PVP_PNGS = ['root/pvp_results_1_l2_kernel/test_p2v2p_all_l2_ref.png',
                      'root/pvp_results_1_l2_kernel/test_p2v2p_all_l2.png',
                      'root/pvp_results_1_l2_kernel/test_p2v2p_1000000_l2.png',
                      'root/pvp_results_1_l2_kernel/test_p2v2p_100000_l2.png',
                      'root/pvp_results_1_l2_kernel/test_p2v2p_10000_l2.png',
                      'root/pvp_results_1_l2_kernel/test_p2v2p_1000_l2.png',
                      'root/pvp_results_1_l2_kernel/test_p2v2p_10_l2.png',]

TC_L3_PVP_PNGS = ['root/pvp_results_1_l3_tc/test_p2v2p_all_l3_ref.png',
                  'root/pvp_results_1_l3_tc/test_p2v2p_all_l3.png',
                  'root/pvp_results_1_l3_tc/test_p2v2p_1000000_l3.png',
                  'root/pvp_results_1_l3_tc/test_p2v2p_100000_l3.png',
                  'root/pvp_results_1_l3_tc/test_p2v2p_10000_l3.png',
                  'root/pvp_results_1_l3_tc/test_p2v2p_1000_l3.png',
                  'root/pvp_results_1_l3_tc/test_p2v2p_10_l3.png',]

TC_L2_PVP_PNGS = ['root/pvp_results_1_l2_tc/test_p2v2p_all_l2_ref.png',
                  'root/pvp_results_1_l2_tc/test_p2v2p_all_l2.png',
                  'root/pvp_results_1_l2_tc/test_p2v2p_1000000_l2.png',
                  'root/pvp_results_1_l2_tc/test_p2v2p_100000_l2.png',
                  'root/pvp_results_1_l2_tc/test_p2v2p_10000_l2.png',
                  'root/pvp_results_1_l2_tc/test_p2v2p_1000_l2.png',
                  'root/pvp_results_1_l2_tc/test_p2v2p_10_l2.png',]



class ResultsSheet(object):
    def __init__(self, args):
        """
        Constructor
        :param args: arguments parse object from command line output
        """
        self._args = args
        self._workbook = xlsxwriter.Workbook(self._args.output)
        self.client_file = args.client_tar_file
        self.server_file = args.server_tar_file
        self.pvp_dpdk_l2_ws = self._workbook.add_worksheet(
            'pvp_dpdk_l2_results')
        self.pvp_dpdk_l3_ws = self._workbook.add_worksheet(
            'pvp_dpdk_l3_results')
        self.pvp_kernel_l2_ws = self._workbook.add_worksheet(
            'pvp_kernel_l2_results')
        self.pvp_kernel_l3_ws = self._workbook.add_worksheet(
            'pvp_kernel_l3_results')
        self.vsperf_ws = self._workbook.add_worksheet(
            'throughput results')
        self.functional_ws = self._workbook.add_worksheet(
            'functional results')
        self.row = 0

    def close_workbook(self):
        """
        Close the workbook
        :return: None
        """
        self._workbook.close()

    def process_functional_results(self):
        """
        Process functional test results
        :return: None
        """
        # Open the tar files from the arguments
        tar1 = tarfile.open(self.client_file, "r")
        tar2 = tarfile.open(self.server_file, "r")
        self.functional_ws.set_column(0, 4, 30)

        def process_log(tar, member, column):
            """
            Process the log
            :param tar: tar file
            :param member: member inside tar file to process
            :param column: column to write to
            :return: Boolean if any test was a failure
            """
            self.row = 1
            column = column
            fh1 = tar.extractfile(member)
            data = fh1.readlines()
            fail_test = False
            fail_format = self._workbook.add_format()
            fail_format.set_color('red')
            for line in data:
                line = line.decode('utf8').strip()
                if "RESULT" in line:
                    findresult = re.search(
                        r'::\s+RESULT:\s+(PASS|FAIL)\s+\((\S+)\)', line)
                    if findresult:
                        self.functional_ws.write_string(self.row, column,
                                                        findresult.group(2))
                        if findresult.group(1) == 'FAIL':
                            fail_test = True
                            self.functional_ws.write_string(
                                self.row, column + 1, findresult.group(1),
                                fail_format)
                        else:
                            self.functional_ws.write_string(
                                self.row, column + 1, findresult.group(1))
                        self.row += 1
            return fail_test

        failed_results = list()
        for member in tar1.getnames():
            if 'client.log' in member:
                self.functional_ws.write_string(0, 0, 'Client results')
                failed_results.append(process_log(tar1, member, 0))
        for member in tar2.getnames():
            if 'server.log' in member:
                self.functional_ws.write_string(0, 2, 'Server results')
                failed_results.append(process_log(tar2, member, 2))

        if any(failed_results):
            self.functional_ws.name = self.functional_ws.name + ' (FAIL)'
        else:
            self.functional_ws.name = self.functional_ws.name + ' (PASS)'

    def process_pvp_results(self):
        """
        Process Eelcos pvp results
        :return: None
        """
        # get the pvp result files
        pvp_files = glob.glob('./pvp*.tgz')
        for result_file in pvp_files:
            tar = tarfile.open(result_file, "r:gz")
            # find the dpdk result file and process it
            if 'dpdk' in result_file:
                if self.write_pvp_worksheet(tar, 'root/pvp_results_1_l2_dpdk/test_results_l2.csv',
                                            self.pvp_dpdk_l2_ws, DPDK_L2_PVP_PNGS):
                    self.pvp_dpdk_l2_ws.name = self.pvp_dpdk_l2_ws.name + ' (FAIL)'
                else:
                    self.pvp_dpdk_l2_ws.name = self.pvp_dpdk_l2_ws.name + ' (PASS)'
                if self.write_pvp_worksheet(tar, 'root/pvp_results_1_l3_dpdk/test_results_l3.csv',
                                            self.pvp_dpdk_l3_ws, DPDK_L3_PVP_PNGS):
                    self.pvp_dpdk_l3_ws.name = self.pvp_dpdk_l3_ws.name + ' (FAIL)'
                else:
                    self.pvp_dpdk_l3_ws.name = self.pvp_dpdk_l3_ws.name + ' (PASS)'
            # find the kernel result file and process it
            elif 'kernel' in result_file:
                if self.write_pvp_worksheet(tar, 'root/pvp_results_1_l2_kernel/test_results_l2.csv',
                                            self.pvp_kernel_l2_ws, KERNEL_L2_PVP_PNGS):
                    self.pvp_kernel_l2_ws.name = self.pvp_kernel_l2_ws.name + ' (FAIL)'
                else:
                    self.pvp_kernel_l2_ws.name = self.pvp_kernel_l2_ws.name + ' (PASS)'
                if self.write_pvp_worksheet(tar, 'root/pvp_results_1_l3_kernel/test_results_l3.csv',
                                            self.pvp_kernel_l3_ws, KERNEL_L3_PVP_PNGS):
                    self.pvp_kernel_l3_ws.name = self.pvp_kernel_l3_ws.name + ' (FAIL)'
                else:
                    self.pvp_kernel_l3_ws.name = self.pvp_kernel_l3_ws.name + ' (PASS)'
            # find the tc_flower result file and process it
            elif 'tc' in result_file:
                #
                # Add TC flower results only if data is available as they are
                # optional.
                #
                self.pvp_tc_l2_ws = self._workbook.add_worksheet(
                    'pvp_tc_flower_l2_results')
                self.pvp_tc_l3_ws = self._workbook.add_worksheet(
                    'pvp_tc_flower_l3_results')
                self.pvp_tc_troughput_ws = self._workbook.add_worksheet(
                    'PVP TC Flower Throughput')

                if self.write_pvp_worksheet(tar, 'root/pvp_results_1_l2_tc/test_results_l2.csv',
                                            self.pvp_tc_l2_ws, TC_L2_PVP_PNGS):
                    self.pvp_tc_l2_ws.name = self.pvp_tc_l2_ws.name + ' (FAIL)'
                else:
                    self.pvp_tc_l2_ws.name = self.pvp_tc_l2_ws.name + ' (PASS)'
                if self.write_pvp_worksheet(tar, 'root/pvp_results_1_l3_tc/test_results_l3.csv',
                                            self.pvp_tc_l3_ws, TC_L3_PVP_PNGS):
                    self.pvp_tc_l3_ws.name = self.pvp_tc_l3_ws.name + ' (FAIL)'
                else:
                    self.pvp_tc_l3_ws.name = self.pvp_tc_l3_ws.name + ' (PASS)'
                if self.write_tc_throughput_worksheet(
                        tar,
                        'root/pvp_results_10_l3_tc/test_results_l3.csv'):
                    self.pvp_tc_troughput_ws.name = \
                        self.pvp_tc_troughput_ws.name + ' (FAIL)'
                else:
                    self.pvp_tc_troughput_ws.name = \
                        self.pvp_tc_troughput_ws.name + ' (PASS)'

    # def process_throughput_results(self):
    #     """
    #     Process the vsperf results
    #     :return: None
    #     """
    #     self.vsperf_ws.set_column(0, 2, 30)

    #     bold_format = self._workbook.add_format()
    #     bold_format.set_bold()

    #     # setup column headers and passing result column
    #     self.vsperf_ws.write_string(0, 0, 'Test name', bold_format)
    #     self.vsperf_ws.write_string(0, 1, 'Test result', bold_format)
    #     self.vsperf_ws.write_string(0, 2, 'Required to pass', bold_format)
    #     self.vsperf_ws.write_string(1, 2, '3000000')
    #     self.vsperf_ws.write_string(2, 2, '1500000')
    #     self.vsperf_ws.write_string(3, 2, '6000000')
    #     self.vsperf_ws.write_string(4, 2, '1500000')
    #     self.vsperf_ws.write_string(5, 2, '1100000')
    #     self.vsperf_ws.write_string(6, 2, '250000')
    #     self.vsperf_ws.write_string(7, 2, '100000')
    #     self.vsperf_ws.write_string(8, 2, '100000')
    #     self.vsperf_ws.write_string(9, 2, '10000000')
    #     self.vsperf_ws.write_string(10, 2, '1500000')

    #     tar = tarfile.open(self.client_file, "r")
    #     test_fail = list()
    #     for member in tar.getnames():
    #         # find the vsperf result file
    #         if 'vsperf_result' in member:
    #             fh1 = tar.extractfile(member)
    #             data = fh1.readlines()

    #             for line in data:
    #                 line = line.decode('utf8').strip()
    #                 if "64   Byte 2PMD OVS/DPDK PVP test result" in line:
    #                     self.vsperf_ws.write_string(1, 0, '64 Byte 2PMD 1Q DPDK', bold_format)
    #                     test_fail.append(self.write_throughput_pass_fail(
    #                         1, 1, str(int(float(line.split()[8]))), 3000000))
    #                 elif "1500 Byte 2PMD OVS/DPDK PVP test result" in line:
    #                     self.vsperf_ws.write_string(2, 0, '1500 Byte 2PMD 1Q DPDK', bold_format)
    #                     test_fail.append(self.write_throughput_pass_fail(
    #                         2, 1, str(int(float(line.split()[8]))), 1500000))
    #                 elif "64   Byte 4PMD 2Q OVS/DPDK PVP test result" in line:
    #                     self.vsperf_ws.write_string(3, 0, '64 Byte 4PMD 2Q DPDK', bold_format)
    #                     test_fail.append(self.write_throughput_pass_fail(
    #                         3, 1, str(int(float(line.split()[9]))), 6000000))
    #                 elif "1500 Byte 4PMD 2Q OVS/DPDK PVP test result" in line:
    #                     self.vsperf_ws.write_string(4, 0, '1500 Byte 4PMD 2Q DPDK', bold_format)
    #                     test_fail.append(self.write_throughput_pass_fail(
    #                         4, 1, str(int(float(line.split()[9]))), 1500000))
    #                 elif ("2000 Byte 2PMD OVS/DPDK PVP test result" in line or
    #                               "2000 Byte 2PMD OVS/DPDK Phy2Phy test result" in line):
    #                     self.vsperf_ws.write_string(5, 0, '2000 Byte 2PMD 1Q DPDK', bold_format)
    #                     test_fail.append(self.write_throughput_pass_fail(
    #                         5, 1, str(int(float(line.split()[8]))), 1100000))
    #                 elif ("9000 Byte 2PMD OVS/DPDK PVP test result" in line or
    #                               "9000 Byte 2PMD OVS/DPDK Phy2Phy test result" in line):
    #                     self.vsperf_ws.write_string(6, 0, '9000 Byte 2PMD 1Q DPDK', bold_format)
    #                     test_fail.append(self.write_throughput_pass_fail(
    #                         6, 1, str(int(float(line.split()[8]))), 250000))
    #                 elif "64   Byte OVS Kernel PVP test result" in line:
    #                     self.vsperf_ws.write_string(7, 0, '64 Byte Kernel',bold_format)
    #                     test_fail.append(self.write_throughput_pass_fail(
    #                         7, 1, str(int(float(line.split()[8]))), 100000))
    #                 elif "1500 Byte OVS Kernel PVP test result" in line:
    #                     self.vsperf_ws.write_string(8, 0, '1500 Byte Kernel', bold_format)
    #                     test_fail.append(self.write_throughput_pass_fail(
    #                         8, 1, str(int(float(line.split()[8]))), 100000))
    #         elif 'vsperf_sr_iov_results' in member:
    #             fh1 = tar.extractfile(member)
    #             data = fh1.readlines()
    #             for line in data:
    #                 line = line.decode('utf8').strip()
    #                 if "64   Byte SR_IOV PVP test result" in line:
    #                     self.vsperf_ws.write_string(9, 0, '64 Byte SRIOV', bold_format)
    #                     test_fail.append(self.write_throughput_pass_fail(
    #                         9, 1, str(int(float(line.split()[7]))), 10000000))
    #                 elif "1500 Byte SR_IOV PVP test result" in line:
    #                     self.vsperf_ws.write_string(10, 0, '1500 Byte SRIOV', bold_format)
    #                     test_fail.append(self.write_throughput_pass_fail(
    #                         10, 1, str(int(float(line.split()[7]))), 1500000))
    #     if any(test_fail):
    #         self.vsperf_ws.name = self.vsperf_ws.name + ' (FAIL)'
    #     else:
    #         self.vsperf_ws.name = self.vsperf_ws.name + ' (PASS)'

    def process_throughput_results(self):
        """
        Process the vsperf results
        :return: None
        """
        def get_test_item_line_range(key_string,all_log_data):
            index_start = -1
            index_end = -1
            for number,line in enumerate(all_log_data):
                if key_string in line.decode():
                    if index_start == -1:
                        index_start = number
                        continue
                    else:
                        index_end = number
                        break
            return index_start,index_end

        def is_single_port_mode(all_log_data):
            for line in all_log_data[0:10]:
                if "SINGLE_PORT_MODE" in line.decode():
                    line_val = line.decode().lower()
                    if "true" in line_val:
                        return True
                    else:
                        return False
            return False


        self.vsperf_ws.set_column(0, 2, 30)
        bold_format = self._workbook.add_format()
        bold_format.set_bold()

        # setup column headers and passing result column
        self.vsperf_ws.write_string(0, 0, 'Test name', bold_format)
        self.vsperf_ws.write_string(0, 1, 'Test result', bold_format)
        self.vsperf_ws.write_string(0, 2, 'Required to pass', bold_format)
        self.vsperf_ws.write_string(1, 2, '3000000')
        self.vsperf_ws.write_string(2, 2, '1500000')
        self.vsperf_ws.write_string(3, 2, '6000000')
        self.vsperf_ws.write_string(4, 2, '1500000')
        self.vsperf_ws.write_string(5, 2, '1100000')
        self.vsperf_ws.write_string(6, 2, '250000')
        self.vsperf_ws.write_string(7, 2, '100000')
        self.vsperf_ws.write_string(8, 2, '100000')
        self.vsperf_ws.write_string(9, 2, '10000000')
        self.vsperf_ws.write_string(10, 2, '1500000')

        tar = tarfile.open(self.client_file, "r")
        test_fail = list()
        for member in tar.getnames():
            # find throughput pvp all performance.txt file from tar package
            if 'throughput_pvp_all_performance.txt' in member:
                fh1 = tar.extractfile(member)
                data = fh1.readlines()
                # SRIOV-VF-PCI-PASSTHROUGH-64-Bytes-1Q-2PMD-TEST
                # SRIOV-VF-PCI-PASSTHROUGH-1500-Bytes-1Q-2PMD-TEST
                # OVS-DPDK-PVP-64-BYTES-1Q-2PMD-TEST
                # OVS-DPDK-PVP-1500-BYTES-1Q-2PMD-TEST
                # OVS-DPDK-PVP-64-BYTES-2Q-4PMD-TEST
                # OVS-DPDK-PVP-1500-BYTES-2Q-4PMD-TEST
                # OVS-DPDK-PVP-2000-BYTES-1Q-2PMD-TEST
                # OVS-DPDK-PVP-9000-BYTES-2Q-4PMD-TEST
                # OVS-KERNEL-DATAPATH-PVP-64-Bytes-1Q-2PMD-TEST
                # OVS-KERNEL-DATAPATH-PVP-1500-Bytes-2Q-4PMD-TEST
                sriov_64_start,sriov_64_end = get_test_item_line_range('SRIOV-VF-PCI-PASSTHROUGH-64-Bytes-1Q-2PMD-TEST',data)
                sriov_1500_start,sriov_1500_end = get_test_item_line_range('SRIOV-VF-PCI-PASSTHROUGH-1500-Bytes-1Q-2PMD-TEST',data)
                ovs_dpdk_64_1q_start,ovs_dpdk_64_1q_end = get_test_item_line_range('OVS-DPDK-PVP-64-BYTES-1Q-2PMD-TEST',data)
                ovs_dpdk_1500_1q_start,ovs_dpdk_1500_1q_end = get_test_item_line_range('OVS-DPDK-PVP-1500-BYTES-1Q-2PMD-TEST',data)
                ovs_dpdk_64_2q_start,ovs_dpdk_64_2q_end = get_test_item_line_range('OVS-DPDK-PVP-64-BYTES-2Q-4PMD-TEST',data)
                ovs_dpdk_1500_2q_start,ovs_dpdk_1500_2q_end = get_test_item_line_range('OVS-DPDK-PVP-1500-BYTES-2Q-4PMD-TEST',data)
                ovs_dpdk_2000_1q_start,ovs_dpdk_2000_1q_end = get_test_item_line_range('OVS-DPDK-PVP-2000-BYTES-1Q-2PMD-TEST',data)
                ovs_dpdk_9000_2q_start,ovs_dpdk_9000_2q_end = get_test_item_line_range('OVS-DPDK-PVP-9000-BYTES-2Q-4PMD-TEST',data)
                if not is_single_port_mode(data):
                    ovs_kernel_64_1q_start,ovs_kernel_64_1q_end = get_test_item_line_range('OVS-KERNEL-DATAPATH-PVP-64-Bytes-1Q-2PMD-TEST',data)
                    ovs_kernel_1500_2q_start,ovs_kernel_1500_2q_end = get_test_item_line_range('OVS-KERNEL-DATAPATH-PVP-1500-Bytes-2Q-4PMD-TEST',data)
                def internal_update_data(line_start,line_end,all_data,row,col,baseline_value):
                    if line_start >=0 and line_end > 0:
                        #single port mode test result
                        if is_single_port_mode(data):
                            for line in data[line_start:line_end]:
                                if 'last result is' in line.decode():
                                    float_pps = float(line.decode().split()[-2])
                                    int_pps = int(float_pps)
                                    str_pps = str(int_pps)
                                    return self.write_throughput_pass_fail(row, col ,str_pps , baseline_value)
                                else:
                                    continue
                        else:
                            for line in data[line_start:line_end]:
                                if '"rx_pps":' in line.decode():
                                    float_pps = float(line.decode().split()[-1].strip(',')) * 2
                                    int_pps = int(float_pps)
                                    str_pps = str(int_pps)
                                    return self.write_throughput_pass_fail(row, col ,str_pps , baseline_value)
                                else:
                                    continue
                        return self.write_throughput_pass_fail(row, col, '0' , baseline_value)
                    else:
                        return self.write_throughput_pass_fail(row, col, '0', baseline_value)
                    pass

                #for sriov 64 1Q
                if sriov_64_start >=0 and sriov_64_end > 0:
                    self.vsperf_ws.write_string(9, 0, 'SRIOV-VF-PCI-PASSTHROUGH-64-Bytes-1Q-2PMD-TEST', bold_format)
                    test_fail.append(internal_update_data(sriov_64_start,sriov_64_end,data,9,1,10000000))

                #for sriov 1500 1Q
                if sriov_1500_start >= 0 and sriov_1500_end > 0 :
                    self.vsperf_ws.write_string(10, 0, 'SRIOV-VF-PCI-PASSTHROUGH-1500-Bytes-1Q-2PMD-TEST', bold_format)
                    test_fail.append(internal_update_data(sriov_1500_start,sriov_1500_end,data,10,1,1500000))

                #for ovs dpdk 64 1Q 3000000
                if ovs_dpdk_64_1q_start >= 0 and ovs_dpdk_64_1q_end > 0:
                    self.vsperf_ws.write_string(1, 0, 'OVS-DPDK-PVP-64-BYTES-1Q-2PMD-TEST', bold_format)
                    test_fail.append(internal_update_data(ovs_dpdk_64_1q_start,ovs_dpdk_64_1q_end,data,1,1,3000000))

                #for ovs dpdk 1500 1Q 1500000
                if ovs_dpdk_1500_1q_start >= 0 and ovs_dpdk_1500_1q_end > 0 :
                    self.vsperf_ws.write_string(2, 0, 'OVS-DPDK-PVP-1500-BYTES-1Q-2PMD-TEST', bold_format)
                    test_fail.append(internal_update_data(ovs_dpdk_1500_1q_start,ovs_dpdk_1500_1q_end,data,2,1,1500000))

                #for ovs dpdk 64 2Q 6000000
                if ovs_dpdk_64_2q_start >= 0 and ovs_dpdk_64_2q_end > 0:
                    self.vsperf_ws.write_string(3, 0, 'OVS-DPDK-PVP-64-BYTES-2Q-4PMD-TEST', bold_format)
                    test_fail.append(internal_update_data(ovs_dpdk_64_2q_start,ovs_dpdk_64_2q_end,data,3,1,6000000))

                #for ovs dpdk 1500 2Q 1500000
                if ovs_dpdk_1500_2q_start >= 0 and ovs_dpdk_1500_2q_end > 0:
                    self.vsperf_ws.write_string(4, 0, 'OVS-DPDK-PVP-1500-BYTES-2Q-4PMD-TEST', bold_format)
                    test_fail.append(internal_update_data(ovs_dpdk_1500_2q_start,ovs_dpdk_1500_2q_end,data,4,1,1500000))

                #for ovs dpdk 2000 1Q 1100000
                if ovs_dpdk_2000_1q_start >= 0 and ovs_dpdk_2000_1q_end > 0:
                    self.vsperf_ws.write_string(5, 0, 'OVS-DPDK-PVP-2000-BYTES-1Q-2PMD-TEST', bold_format)
                    test_fail.append(internal_update_data(ovs_dpdk_2000_1q_start,ovs_dpdk_2000_1q_end,data,5,1,1100000))

                #for ovs dpdk 9000 2Q 250000
                if ovs_dpdk_9000_2q_start >= 0 and ovs_dpdk_9000_2q_end > 0 :
                    self.vsperf_ws.write_string(6, 0, 'OVS-DPDK-PVP-9000-BYTES-2Q-4PMD-TEST', bold_format)
                    test_fail.append(internal_update_data(ovs_dpdk_9000_2q_start,ovs_dpdk_9000_2q_end,data,6,1,250000))

                if not is_single_port_mode(data):
                    #for ovs kernel datapath 64 1Q 100000
                    if ovs_kernel_64_1q_start >= 0 and ovs_kernel_64_1q_end > 0:
                        self.vsperf_ws.write_string(7, 0, 'OVS-KERNEL-DATAPATH-PVP-64-Bytes-1Q-2PMD-TEST', bold_format)
                        test_fail.append(internal_update_data(ovs_kernel_64_1q_start,ovs_kernel_64_1q_end,data,7,1,100000))

                    #for ovs kernel datapath 1500 2Q 100000
                    if ovs_kernel_1500_2q_start >= 0 and ovs_kernel_1500_2q_end > 0:
                        self.vsperf_ws.write_string(8, 0, 'OVS-KERNEL-DATAPATH-PVP-1500-Bytes-2Q-4PMD-TEST', bold_format)
                        test_fail.append(internal_update_data(ovs_kernel_1500_2q_start,ovs_kernel_1500_2q_end,data,8,1,100000))

        if any(test_fail):
            self.vsperf_ws.name = self.vsperf_ws.name + ' (FAIL)'
        else:
            self.vsperf_ws.name = self.vsperf_ws.name + ' (PASS)'

    def write_pvp_worksheet(self, tar_file, csv_file, worksheet, png_list):
        """
        Write out the pvp results to the specified worksheet, write pass fail on worksheet name
        :param tar_file: tar file
        :param csv_file: csv file to process inside of tar
        :param worksheet: worksheet to write to
        :param png_list: png list from CONSTANT values
        :return: return boolean if any test failed
        """
        fh = io.StringIO(tar_file.extractfile(csv_file).read().decode('ascii'))
        reader = csv.reader(fh, delimiter=',', quotechar='|')
        test_fail = False
        max_column = 0
        self.row = 0
        for row in reader:
            column = 0
            try:
                if len(row) > 0 and 'cpu' not in row[0]:
                    for i in range(len(row)):
                        # try to convert to int to round.
                        try:
                            entry = int(float(row[i]))
                            if entry <= 0:
                                test_fail = True
                        except ValueError:
                            entry = row[i]
                        worksheet.write_string(self.row, column, str(entry))
                        column += 1
                    self.row += 1
                    max_column = column if column > max_column else max_column
            except IndexError:
                continue
        for png in png_list[1:2]:
            tar_file.extractall()
            worksheet.insert_image(self.row, 0, png)

        worksheet.set_column(0, max_column, 30)
        self.row = 0
        return test_fail

    def write_throughput_pass_fail(self, row, column, text, pass_value):
        """
        Write out the vsperf results to the location specified
        :param row: row in sheet
        :param column: column in sheet
        :param text: result text
        :param pass_value: minimum value to pass for the result
        :return: Boolean if test was a failure
        """
        fail_format = self._workbook.add_format()
        fail_format.set_color('red')

        if int(text) < pass_value:
            self.vsperf_ws.write_string(row, column, text, fail_format)
            return True
        else:
            self.vsperf_ws.write_string(row, column, text)
            return False

    def write_tc_throughput_worksheet(self, tar_file, csv_file):
        speed_pass_table = {
            10: {64: 2490513, 128: 2400604, 256: 2256274, 512: 2114661,
                 768: 1427664, 1024: 1077586, 1514: 733376},
            25: {64: 9637204, 128: 6508473, 256: 4000375, 512: 3693513,
                 768: 3462503, 1024: 2671544, 1514: 1819386},
            40: {64: 10217438, 128: 9092933, 256: 8657281, 512: 6536093,
                 768: 5280149, 1024: 4024205, 1514: 2619575},
            50: {64: 26067795, 128: 23473241, 256: 18772297, 512: 10476825,
                 768: 7083181, 1024: 5347950, 1514: 3640232},
            100: {64: 26899051, 128: 24033668, 256: 18772297, 512: 13542611,
                  768: 9978782, 1024: 7948678, 1514: 5451593}
        }

        fh = io.StringIO(tar_file.extractfile(csv_file).read().decode('ascii'))
        reader = csv.reader(fh, delimiter=',', quotechar='|')
        nic_speed = None
        packet_sizes = None
        tenK_results = None
        failure = False
        for row in reader:

            if len(row) == 0:
                #
                # Empty line means new test results (we should have only one)
                #
                packet_sizes = None
                tenK_results = None
            elif nic_speed is None:
                #
                # We need the NIC speed
                #
                if row[0] == '\"Physical port':
                    nic_speed = int(float(row[2].split()[1]))
                    if nic_speed not in [10, 25, 40, 50, 100]:
                        raise ValueError(
                            "Unsupported link rate, please report!!")

            elif packet_sizes is None:
                #
                # See if this is the line with the packet size info
                #
                if len(row) >= 2 and row[0] == 'Number of flows':
                    try:
                        packet_sizes = [int(i) for i in row[1:]]
                    except ValueError:
                        packet_sizes = None
            else:
                #
                # Here we are processing results
                #
                if (len(row) == len(packet_sizes) + 1):
                    try:
                        results_values = [int(float(i)) for i in row]
                    except ValueError:
                        if row[0].startswith("cpu_"):
                            #
                            # If line starts with cpu_x it's the embedded
                            # cpu statistics which we should ignore those
                            #
                            continue
                        else:
                            #
                            # Rest are real issues, start over...
                            #
                            packet_sizes = None
                            continue
                    #
                    # Normal result line processing
                    #
                    if results_values[0] == 10000:
                        tenK_results = results_values[1:]
                        break

        if nic_speed is None or packet_sizes is None or tenK_results is None:
            raise ValueError("The TC L3 PVP results is missing data, i.e. "
                             "Link speed, or 10K packet results!!")

        #
        # Write default workbook layout
        #
        self.pvp_tc_troughput_ws.set_column(0, 3, 16)

        bold_format = self._workbook.add_format()
        red_format = self._workbook.add_format()
        bold_format.set_bold()
        red_format.set_color('red')

        self.pvp_tc_troughput_ws.write_string(
            0, 0,
            "PVP test for 10K TC Flower rules with NIC speed of {} Gbps".
            format(nic_speed),
            bold_format)

        self.pvp_tc_troughput_ws.write_string(2, 0, "Packet Size", bold_format)
        self.pvp_tc_troughput_ws.write_string(2, 1, "pps", bold_format)
        self.pvp_tc_troughput_ws.write_string(2, 2, "pass criteria pps",
                                              bold_format)

        #
        # Write results, and check pass/fail criteria
        #
        results = dict(list(zip(packet_sizes, tenK_results)))
        pass_table = speed_pass_table[nic_speed]
        all_packet_sizes = sorted(list(set(packet_sizes + list(pass_table.keys()))))

        for i, pkt_size in enumerate(all_packet_sizes):
            self.pvp_tc_troughput_ws.write_string(i + 3, 0, str(pkt_size))
            try:
                self.pvp_tc_troughput_ws.write_string(i + 3, 1,
                                                      str(results[pkt_size]))
            except KeyError:
                self.pvp_tc_troughput_ws.write_string(i + 3, 1, "N/A")
            try:
                if pkt_size not in results or \
                   results[pkt_size] < pass_table[pkt_size]:
                    failure = True
                    self.pvp_tc_troughput_ws.write_string(
                        i + 3, 2, str(pass_table[pkt_size]), red_format)
                else:
                    self.pvp_tc_troughput_ws.write_string(
                        i + 3, 2, str(pass_table[pkt_size]))

            except KeyError:
                self.pvp_tc_troughput_ws.write_string(i + 3, 2, "-")

        return failure

    def process_tc_flower_result(self):
        """
        write the tc flower to work sheet
        :return: Boolean if test was a failure
        """
        def get_average_rate(data_file):
            rate_list = []
            entry_list = []
            if os.path.exists(data_file):
                with open("fl_change.dat") as fd:
                    all_data_list = fd.read().split("\n\n")
                    for data in all_data_list:
                        if data is not None and \
                           data not in ['\n', '\r', '\r\n']:
                            data_list = data.strip('\n').split('\n')
                            begin_time = data_list[0].split(" ")[0]
                            end_time, total_rule = data_list[-1].split(" ")
                            total_time = float(end_time) - float(begin_time)
                            try:
                                rate = int(total_rule) / total_time
                                rate_list.append(rate)
                            except:
                                rate = int(total_rule)
                                rate_list.append(rate)
                            pass
                            entry_list.append(len(data_list))
                        else:
                            pass
                pass
            else:
                print("Can not find the data file")
            return rate_list, entry_list

        row = 0
        column = 0
        failure = False
        data_file = "fl_change.dat"
        test_names = ["Cumulative", "SW only", "HW only", "Just flower"]
        if os.path.exists(data_file):
            self.flower_rule_ws = self._workbook.add_worksheet(
                'tc-flower insert rate')
            bold_format = self._workbook.add_format()
            bold_format.set_bold()
            self.flower_rule_ws.set_column(0, 3, 16)

            # setup column headers and passing result column
            self.flower_rule_ws.write_string(row, column + 1, "Average rate per sec",
                                             bold_format)
            self.flower_rule_ws.write_string(row, column + 2, "Insertions",
                                             bold_format)
            self.flower_rule_ws.write_string(row, column + 3,
                                             "Required to pass", bold_format)
            self.flower_rule_ws.write_string(row + 1, column + 3,
                                             "1.5k/s average rate")
            self.flower_rule_ws.write_string(row + 3, column + 3,
                                             "10K concurrent hardware flows")

            row += 1
            rate_list, entry_list = get_average_rate(data_file)
            if rate_list:
                for index, rate in enumerate(rate_list):
                    if index < len(test_names):
                        label = test_names[index]
                    else:
                        label = "Test %d" % (index+1)

                    self.flower_rule_ws.write_string(row, column, label,
                                                     bold_format)

                    if index == 0 and rate < 1500:
                        fail_format = self._workbook.add_format()
                        fail_format.set_color('red')

                        self.flower_rule_ws.write_string(row, column + 1,
                                                         str(rate),
                                                         fail_format)
                        failure = True
                    else:
                        self.flower_rule_ws.write_string(row, column + 1,
                                                         str(rate))

                    if index == 2 and entry_list[index] < 10000:
                        fail_format = self._workbook.add_format()
                        fail_format.set_color('red')

                        self.flower_rule_ws.write_string(row, column + 2,
                                                         str(entry_list[index]),
                                                         fail_format)
                        failure = True
                    else:
                        self.flower_rule_ws.write_string(row, column + 2,
                                                         str(entry_list[index]))

                    row += 1
        else:
            self.flower_rule_ws = None
            return False

        if failure:
            self.flower_rule_ws.name = self.flower_rule_ws.name + ' (FAIL)'
        else:
            self.flower_rule_ws.name = self.flower_rule_ws.name + ' (PASS)'

        if os.path.exists('fl_change.png'):
            self.flower_rule_ws.insert_image(row + 3, 0, 'fl_change.png')
            return True
        else:
            return False


def main():
    mysheet = ResultsSheet(args)
    mysheet.process_throughput_results()
    mysheet.process_functional_results()
    mysheet.process_pvp_results()
    mysheet.process_tc_flower_result()
    mysheet.close_workbook()


def yes_no(answer):
    yes = set(['yes', 'y', 'ye', ''])
    no = set(['no', 'n'])

    while True:
        choice = raw_input(answer).lower()
        if choice in yes:
            return True
        elif choice in no:
            return False
        else:
            print("Please respond with 'yes' or 'no'\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('-o', '--output', type=str, required=True,
                        help='Output file name')
    parser.add_argument('-s', '--server_tar_file', type=str, required=True,
                        help='Server tar file name')
    parser.add_argument('-c', '--client_tar_file', type=str, required=True,
                        help='Client tar file name')
    args = parser.parse_args()
    if os.path.isfile(args.output):
        ans = yes_no("Output file {} already exists. Overwrite?".format(args.output))
        if not ans:
            sys.exit()
    if os.path.isfile(args.server_tar_file) == False or os.path.isfile(args.client_tar_file) == False:
        print("Server or client file do not exist. Check your arguments.")
    main()
