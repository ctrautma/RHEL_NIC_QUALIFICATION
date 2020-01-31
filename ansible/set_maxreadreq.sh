#!/bin/bash

if [ -z ${1+x} ]; then exit 1; fi
PCIADDR1=$1

# Get current PCIe Max_Read_Request_Size
IN1=`setpci -s $PCIADDR1 CAP_EXP+8.w`

# Modify PCIe Max_Read_Request_Size
# 0x0000 = 128 bytes
# 0x1000 = 256 bytes
# 0x2000 = 512 bytes
# 0x3000 = 1024 bytes
# 0x4000 = 2048 bytes
# 0x5000 = 4096 bytes
OUT1=`printf "%x" $((((16#$IN1 & 0xFFF)) | 0x4000))`

# Set PCIe Max_Read_Request_Size
setpci -s $PCIADDR1 CAP_EXP+8.w=$OUT1