#!/usr/bin/env bash

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:

DIR=$(echo $0 | sed -r 's/vm2.sh//g')
if [[ ${DIR:0:2} == *./* ]];then
	DIR=$( echo "$DIR" | sed -r 's/\.\///g')
	PATH_TO="$PWD/$DIR"
else
	cd $(dirname $0)
	PATH_TO=$(echo "$PWD/")
	cd - >> /dev/null
fi

source "$PATH_TO"vm2.config

echo "---Config options---"
echo "Path to config:" $(echo "$PATH_TO"vm2.config)
echo "INTERNAL_IF:" $(echo $INTERNAL_IF)
echo "MANAGEMENT_IF:" $(echo $MANAGEMENT_IF)
echo "VLAN:" $(echo $VLAN)
echo "INT_IP:" $(echo $INT_IP)
echo "GW_IP:" $(echo $GW_IP)
echo "APACHE_VLAN_IP:" $(echo $APACHE_VLAN_IP)

#NETWORK CONFIG
echo "---Network setup---"
ip link set $INTERNAL_IF up
echo "$INTERNAL_IF up"
ip link set $MANAGEMENT_IF up
echo "$MANAGEMENT_IF up"

#INTERNAL SETUP
echo $INT_IP
echo $INTERNAL_IF
ip addr add $INT_IP dev $INTERNAL_IF
ip route add default via $GW_IP dev $INTERNAL_IF
echo "nameserver 8.8.8.8" > /etc/resolvconf/resolv.conf.d/base
resolvconf -u
echo "IP $INT_IP default gateway $GW_IP"

#VLAN
modprobe 8021q
vconfig add $INTERNAL_IF $VLAN
VLAN_IF=$(echo "$INTERNAL_IF"."$VLAN")
ip addr add $APACHE_VLAN_IP dev $VLAN_IF
ip link set $VLAN_IF up
echo "Apache vlan created: tag $VLAN ip $VLAN_IP interface $VLAN_IF"
VM2_IP=$(echo $APACHE_VLAN_IP | awk -F/ '{print $1}')
echo "$VM2_IP vm2" >> /etc/hosts
echo "vm2" > /etc/hostname

#INSTALL APACHE
apt install -y apache2
sed -i '/Listen/d' "/etc/apache2/ports.conf"
echo "Listen 10.10.10.20:80" >> "/etc/apache2/ports.conf"
systemctl restart apache2

