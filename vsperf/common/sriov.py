#!/usr/bin/env python
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   sriov.py of /kernel/networking/fd_nic_partition/common/sriov.py
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


import abc
from abc import ABCMeta
import time
import sys
import ethtool
import shutil
import shlex
import plumbum
from plumbum import local


def get_local_command_object(cmd_string):
    if not cmd_string:
        return None
    cmd_list = shlex.split(cmd_string)
    cmd_obj = local[cmd_list[0]]
    return cmd_obj.__getitem__(cmd_list[1:])


class SRIOV():
    __metaclass__ = ABCMeta
    """
    This is abstract class , can not be init 
    Customer must derive it and implement below method
    """
    def __init__(self):
        pass
    
    @staticmethod
    @abc.abstractmethod
    def get_pf_name_from_pf_bus(pf_bus):
        pass
        
    @staticmethod
    @abc.abstractmethod
    def get_pf_bus_from_pf_name(pf_name):
        pass

    @staticmethod
    @abc.abstractmethod
    def get_all_vf_list_from_pf_bus( pf_bus):
        pass

    @staticmethod
    @abc.abstractmethod
    def create_vfs( pf_bus, num):
        pass

    @staticmethod
    @abc.abstractmethod
    def remove_vf_from_pf_bus( pf_bus):
        pass

    @staticmethod
    @abc.abstractmethod
    def get_pf_name_from_vf_name( vf_name):
        pass

    @staticmethod
    @abc.abstractmethod
    def get_pf_bus_from_vf_name( vf_name):
        pass

    @staticmethod
    @abc.abstractmethod
    def attach_vf_to_vm( vf_name, vm, mac=None, vlan=None):
        pass

    @staticmethod
    @abc.abstractmethod
    def detach_vf_from_vm( vm, xml_file):
        pass


