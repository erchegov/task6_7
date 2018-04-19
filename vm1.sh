#!/usr/bin/env bash

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:

DIR=$(echo $0 | sed -r 's/vm1.sh//g')
if [[ ${DIR:0:2} == *./* ]];then
	DIR=$( echo "$DIR" | sed -r 's/\.\///g')
	PATH_TO="$PWD/$DIR"
else
	cd $(dirname $0)
	PATH_TO=$(echo "$PWD/")
	cd - >> /dev/null
fi

source "$PATH_TO"vm1.config

echo "---Config options---"
echo "Path to config:"$(echo "$PATH_TO"vm1.config)

echo "EXTERNAL_IF:" $(echo $EXTERNAL_IF)
echo "INTERNAL_IF:" $(echo $INTERNAL_IF)
echo "MANAGEMENT_IF:" $(echo $MANAGEMENT_IF)
echo "VLAN:" $(echo $VLAN)
if [[ $EXT_IP != "DHCP" ]];then
		EXT_IP=$( echo  $EXT_IP | sed -r 's/,//g')
		EXT_GW=$EXT_GW
        else
                EXT_IP=$EXT_IP
fi
echo "EXT_IP:" $(echo $EXT_IP)
echo "EXT_GW:" $(echo ${EXT_GW:-You use DHCP})
echo "INT_IP:" $(echo $INT_IP)
echo "VLAN_IP:" $(echo $VLAN_IP)
echo "NGINX_PORT:" $(echo $NGINX_PORT)
echo "APACHE_VLAN_IP:" $(echo $APACHE_VLAN_IP)

#NETWORK CONFIG
echo "---Network setup---"
ip link set $EXTERNAL_IF up
echo "$EXTERNAL_IF up"
ip link set $INTERNAL_IF up
echo "$INTERNAL_IF up"
ip link set $MANAGEMENT_IF up
echo "$MANAGEMENT_IF up"

#EXTERNAL SETUP
if [[ $EXT_IP == "DHCP" ]]
  then
    echo "External interface use DHCP configuration"
  else
    ip addr add $EXT_IP dev $EXTERNAL_IF
    ip route add default via $EXT_GW dev $EXTERNAL_IF
    echo "nameserver 8.8.8.8" > /etc/resolvconf/resolv.conf.d/base
    resolvconf -u
    echo "External interface use static configuration:"
    echo "IP $EXT_IP default gateway $EXT_GW"
fi

#INTERNAL SETUP
ip addr add $INT_IP dev $INTERNAL_IF
echo "Internal interface: IP $INT_IP"

#VLAN
modprobe 8021q
vconfig add $INTERNAL_IF $VLAN
VLAN_IF=$(echo "$INTERNAL_IF"."$VLAN")
ip addr add $VLAN_IP dev $VLAN_IF
ip link set $VLAN_IF up
echo "Apache vlan created: tag $VLAN ip $VLAN_IP interface $VLAN_IF"

#SSL
mkdir -p /etc/ssl/private  /etc/ssl/certs
IP_CA=$(ip a show $EXTERNAL_IF | grep inet | awk '{ print $2; }' | sed 's/\/.*$//' | awk 'FNR==1{print $1}')
openssl genrsa -out /etc/ssl/private/root-ca.key 4096
openssl req -x509 -newkey rsa:4096 -passout pass:1234 -keyout /etc/ssl/private/root-ca.key -out /etc/ssl/certs/root-ca.crt -subj "/C=UA/O=MIRANTIS/CN=vm1ca" 
openssl genrsa -out /etc/ssl/private/web.key 4096
openssl req -new -key /etc/ssl/private/web.key -out /etc/ssl/web.csr -subj "/C=UA/O=VM/CN=vm1" -reqexts SAN -config <(cat /etc/ssl/openssl.cnf <(printf "[SAN]\nsubjectAltName=DNS:vm1,DNS:$IP_CA"))
openssl x509 -req -in /etc/ssl/web.csr -CA /etc/ssl/certs/root-ca.crt -passin pass:1234 -CAkey /etc/ssl/private/root-ca.key -CAcreateserial -out /etc/ssl/certs/web.crt -days 365 -extfile <(printf "subjectAltName=DNS:vm1,DNS:$IP_CA")
cat /etc/ssl/certs/root-ca.crt >> /etc/ssl/certs/web.crt
echo "$IP_CA vm1" >> /etc/hosts
echo "vm1" > /etc/hostname
cp /etc/ssl/certs/root-ca.crt /usr/local/share/ca-certificates/
update-ca-certificates

#INSTALL NGINX
apt install -y nginx

echo "server {" > /etc/nginx/sites-available/default
echo "listen $NGINX_PORT ssl;" >> /etc/nginx/sites-available/default 
echo "server_name vm1;" >> /etc/nginx/sites-available/default
echo "location / {"  >> /etc/nginx/sites-available/default
echo "proxy_pass http://$APACHE_VLAN_IP/;" >> /etc/nginx/sites-available/default
echo "proxy_set_header   X-Real-IP "'$remote_addr'";" >> /etc/nginx/sites-available/default
echo "proxy_set_header   Host "'$http_host'";" >> /etc/nginx/sites-available/default
echo "proxy_set_header   X-Forwarded-For "'$proxy_add_x_forwarded_for'";" >> /etc/nginx/sites-available/default
echo "}" >> /etc/nginx/sites-available/default
echo "error_page 497 =444 @close;" >> /etc/nginx/sites-available/default
echo "location @close {" >> /etc/nginx/sites-available/default
echo "return 0;" >> /etc/nginx/sites-available/default
echo "}" >> /etc/nginx/sites-available/default
echo "ssl on;" >> /etc/nginx/sites-available/default
echo "ssl_certificate /etc/ssl/certs/web.crt;" >> /etc/nginx/sites-available/default
echo "ssl_certificate_key /etc/ssl/private/web.key;" >> /etc/nginx/sites-available/default
echo "server_name vm1;" >> /etc/nginx/sites-available/default
echo "}" >> /etc/nginx/sites-available/default
cat /etc/nginx/sites-available/default
systemctl restart nginx

#IPTABLES
echo "1" > /proc/sys/net/ipv4/ip_forward
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -A FORWARD -i $INTERNAL_IF -o $EXTERNAL_IF -j ACCEPT
iptables -A FORWARD -i $EXTERNAL_IF -o $INTERNAL_IF -j ACCEPT
NAT_NET=$(ip route | grep $INTERNAL_IF | awk 'FNR==2{print $1}')
iptables -t nat -A POSTROUTING -s $NAT_NET -o $EXTERNAL_IF -j MASQUERADE

