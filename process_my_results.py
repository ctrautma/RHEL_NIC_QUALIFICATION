import argparse
import csv
import glob
import os
import re
import sys
import tarfile
import xlsxwriter

DPDK_L3_PVP_PNGS = ['root/pvp_results_10_l3_dpdk/test_p2v2p_all_l3_ref.png',
                    'root/pvp_results_10_l3_dpdk/test_p2v2p_all_l3.png',
                    'root/pvp_results_10_l3_dpdk/test_p2v2p_1000000_l3.png',
                    'root/pvp_results_10_l3_dpdk/test_p2v2p_100000_l3.png',
                    'root/pvp_results_10_l3_dpdk/test_p2v2p_10000_l3.png',
                    'root/pvp_results_10_l3_dpdk/test_p2v2p_1000_l3.png',
                    'root/pvp_results_10_l3_dpdk/test_p2v2p_10_l3.png',]

DPDK_L2_PVP_PNGS = ['root/pvp_results_10_l2_dpdk/test_p2v2p_all_l2_ref.png',
                    'root/pvp_results_10_l2_dpdk/test_p2v2p_all_l2.png',
                    'root/pvp_results_10_l2_dpdk/test_p2v2p_1000000_l2.png',
                    'root/pvp_results_10_l2_dpdk/test_p2v2p_100000_l2.png',
                    'root/pvp_results_10_l2_dpdk/test_p2v2p_10000_l2.png',
                    'root/pvp_results_10_l2_dpdk/test_p2v2p_1000_l2.png',
                    'root/pvp_results_10_l2_dpdk/test_p2v2p_10_l2.png',]

KERNEL_L3_PVP_PNGS = ['root/pvp_results_10_l3_kernel/test_p2v2p_all_l3_ref.png',
                      'root/pvp_results_10_l3_kernel/test_p2v2p_all_l3.png',
                      'root/pvp_results_10_l3_kernel/test_p2v2p_1000000_l3.png',
                      'root/pvp_results_10_l3_kernel/test_p2v2p_100000_l3.png',
                      'root/pvp_results_10_l3_kernel/test_p2v2p_10000_l3.png',
                      'root/pvp_results_10_l3_kernel/test_p2v2p_1000_l3.png',
                      'root/pvp_results_10_l3_kernel/test_p2v2p_10_l3.png',]

KERNEL_L2_PVP_PNGS = ['root/pvp_results_10_l2_kernel/test_p2v2p_all_l2_ref.png',
                      'root/pvp_results_10_l2_kernel/test_p2v2p_all_l2.png',
                      'root/pvp_results_10_l2_kernel/test_p2v2p_1000000_l2.png',
                      'root/pvp_results_10_l2_kernel/test_p2v2p_100000_l2.png',
                      'root/pvp_results_10_l2_kernel/test_p2v2p_10000_l2.png',
                      'root/pvp_results_10_l2_kernel/test_p2v2p_1000_l2.png',
                      'root/pvp_results_10_l2_kernel/test_p2v2p_10_l2.png',]

class ResultsSheet(object):
    def __init__(self, args):
        self._args = args
        self._workbook = xlsxwriter.Workbook(self._args.output)
        self.client_file = args.client_tar_file
        self.server_file = args.server_tar_file
        self.pvp_dpdk_l2_ws = self._workbook.add_worksheet('pvp_dpdk_l2_results')
        self.pvp_dpdk_l3_ws = self._workbook.add_worksheet('pvp_dpdk_l3_results')
        self.pvp_kernel_l2_ws = self._workbook.add_worksheet('pvp_kernel_l2_results')
        self.pvp_kernel_l3_ws = self._workbook.add_worksheet('pvp_kernel_l3_results')
        self.vsperf_ws = self._workbook.add_worksheet('throughput results')
        self.functional_ws = self._workbook.add_worksheet('functional results')
        self.row = 0

    def process_functional_results(self):
        tar1 = tarfile.open(self.client_file, "r")
        tar2 = tarfile.open(self.server_file, "r")
        self.functional_ws.set_column(0, 4, 30)

        def process_log(tar, member, column):
            self.row = 1
            column = column
            fh1 = tar.extractfile(member)
            data = fh1.readlines()
            fail_test = False
            for line in data:
                if "RESULT" in line:
                    findresult = re.search('\[   (PASS|FAIL)   \] :: RESULT: (\S+)', line)
                    if findresult.group(1) == 'FAIL':
                        fail_test = True
                    if findresult:
                        self.functional_ws.write_string(self.row, column, findresult.group(2))
                        self.functional_ws.write_string(self.row, column + 1, findresult.group(1))
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

    def write_pvp_worksheet(self, tar_file, csv_file, worksheet, png_list):
        fh = tar_file.extractfile(csv_file)
        reader = csv.reader(fh, delimiter=',', quotechar='|')
        test_fail = False
        max_column = 0
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
        for png in png_list[0:1]:
            tar_file.extractall()
            worksheet.insert_image(self.row, 0, png)

        worksheet.set_column(0, max_column, 30)
        self.row = 0
        return test_fail

    def process_pvp_results(self):
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

    def process_throughput_results(self):
        self.vsperf_ws.set_column(0, 2, 30)
        tar = tarfile.open(self.client_file, "r")
        test_fail = False
        for member in tar.getnames():
            if 'vsperf_result' in member:
                fh1 = tar.extractfile(member)
                data = fh1.readlines()
                for line in data:
                    if "64   Byte 2PMD OVS/DPDK PVP test result" in line:
                        self.vsperf_ws.write_string(0, 0, '64 Byte 2PMD 1Q DPDK')
                        self.vsperf_ws.write_string(0, 1, str(int(float(line.split()[8]))))
                        if int(float(line.split()[8])) < 3000000:
                            test_fail = True
                    elif "1500 Byte 2PMD OVS/DPDK PVP test result" in line:
                        self.vsperf_ws.write_string(1, 0, '1500 Byte 2PMD 1Q DPDK')
                        self.vsperf_ws.write_string(1, 1, str(int(float(line.split()[8]))))
                        if int(float(line.split()[8])) < 1500000:
                            test_fail = True
                    elif "64   Byte 4PMD 2Q OVS/DPDK PVP test result" in line:
                        self.vsperf_ws.write_string(2, 0, '64 Byte 4PMD 2Q DPDK')
                        self.vsperf_ws.write_string(2, 1, str(int(float(line.split()[9]))))
                        if int(float(line.split()[9])) < 6000000:
                            test_fail = True
                    elif "1500 Byte 4PMD 2Q OVS/DPDK PVP test result" in line:
                        self.vsperf_ws.write_string(3, 0, '1500 Byte 4PMD 2Q DPDK')
                        self.vsperf_ws.write_string(3, 1, str(int(float(line.split()[9]))))
                        if int(float(line.split()[9])) < 1500000:
                            test_fail = True
                    elif ("2000 Byte 2PMD OVS/DPDK PVP test result" in line or
                                  "2000 Byte 2PMD OVS/DPDK Phy2Phy test result" in line):
                        self.vsperf_ws.write_string(4, 0, '2000 Byte 2PMD 1Q DPDK')
                        self.vsperf_ws.write_string(4, 1, str(int(float(line.split()[8]))))
                        if int(float(line.split()[8])) < 1100000:
                            test_fail = True
                    elif ("9000 Byte 2PMD OVS/DPDK PVP test result" in line or
                                  "9000 Byte 2PMD OVS/DPDK Phy2Phy test result" in line):
                        self.vsperf_ws.write_string(5, 0, '9000 Byte 2PMD 1Q DPDK')
                        self.vsperf_ws.write_string(5, 1, str(int(float(line.split()[8]))))
                        if int(float(line.split()[8])) < 250000:
                            test_fail = True
                    elif "64   Byte OVS Kernel PVP test result" in line:
                        self.vsperf_ws.write_string(6, 0, '64 Byte Kernel')
                        self.vsperf_ws.write_string(6, 1, str(int(float(line.split()[8]))))
                        if int(float(line.split()[8])) < 100000:
                            test_fail = True
                    elif "1500 Byte OVS Kernel PVP test result" in line:
                        self.vsperf_ws.write_string(7, 0, '1500 Byte Kernel')
                        self.vsperf_ws.write_string(7, 1, str(int(float(line.split()[8]))))
                        if int(float(line.split()[8])) < 100000:
                            test_fail = True
        if test_fail:
            self.vsperf_ws.name = self.vsperf_ws.name + ' (FAIL)'
        else:
            self.vsperf_ws.name = self.vsperf_ws.name + ' (FAIL)'

    def close_workbook(self):
        self._workbook.close()


def main():
    mysheet = ResultsSheet(args)
    mysheet.process_pvp_results()
    mysheet.process_throughput_results()
    mysheet.process_functional_results()
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
