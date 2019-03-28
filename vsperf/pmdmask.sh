#!/usr/bin/env bash

# create PMD mask from CPUs entered

echo "This will create a PMD mask from the CPUs desired for DPDK"
read -p "Please enter each CPU number you want to add to the PMD mask (ex: 2 28 4 30):" cpus
read -a arr <<<$cpus
foo="'p/x "
for i in "${arr[@]}"
do
    foo="$foo 1ULL<<$i |"
done
foo=`echo $foo | rev | cut -c 2- | rev`

foo="echo $foo ' | gdb"
eval "${foo}" >mask.txt
cat mask.txt | awk /=/ | awk '{print $4}'
rm mask.txt