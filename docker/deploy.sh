# !/bin/bash

WARP_NAME=warp
DHCPSERVER_NAME=dhcpserver

if ip netns show "$WARP_NAME" >/dev/null 2>&1 ; then
  ip -n $WARP_NAME link del dev A
  ip netns del "$WARP_NAME"
fi
if ip netns show "$DHCPSERVER_NAME" >/dev/null 2>&1 ; then
  ip -n $DHCPSERVER_NAME link del dev A-warp-peer 2>&1
  ip -n $DHCPSERVER_NAME link del dev B-dhcp-peer 2>&1
  ip netns del "$DHCPSERVER_NAME"
fi

docker rm -f $WARP_NAME $DHCPSERVER_NAME

#ip link add dev A type veth peer name Apeer
ip link add dev A-warp type veth peer name A-warp-peer
ip link add dev B-dhcp type veth peer name B-dhcp-peer

docker run --name $WARP_NAME --cap-add=NET_ADMIN -v $PWD/$WARP_NAME/mdm.xml:/var/lib/cloudflare-warp/mdm.xml -v $PWD/$WARP_NAME/dnsmasq.conf:/etc/dnsmasq.conf -d --privileged warp

docker run --name $DHCPSERVER_NAME --net=none --cap-add=NET_ADMIN --dns 192.168.99.1 -v $PWD/$DHCPSERVER_NAME/dnsmasq.conf:/etc/dnsmasq.conf -d dhcpserver tail -f /etc/passwd

for name in $WARP_NAME $DHCPSERVER_NAME; do
  ip netns attach $name $(docker inspect --format '{{.State.Pid}}' $name)
done

ip link set dev A-warp netns $WARP_NAME
ip link set dev A-warp-peer netns $DHCPSERVER_NAME
ip link set dev B-dhcp-peer netns $DHCPSERVER_NAME

ip -n $WARP_NAME link set up A-warp
ip -n $WARP_NAME addr add dev A-warp 192.168.99.1/24
docker exec -ti $WARP_NAME update-alternatives --set iptables /usr/sbin/iptables-legacy
docker exec -ti $WARP_NAME iptables -t nat -A POSTROUTING --src 192.168.99.0/24 -j MASQUERADE


ip -n $DHCPSERVER_NAME link set up A-warp-peer
ip -n $DHCPSERVER_NAME link set up B-dhcp-peer
ip -n $DHCPSERVER_NAME addr add dev A-warp-peer 192.168.99.2/24
ip -n $DHCPSERVER_NAME addr add dev B-dhcp-peer 192.168.100.1/24
ip -n $DHCPSERVER_NAME route add default via 192.168.99.1
docker exec -ti $DHCPSERVER_NAME iptables -t nat -A POSTROUTING -o A-warp-peer -j MASQUERADE

docker exec -ti $WARP_NAME dnsmasq -C /etc/dnsmasq.conf
docker exec -ti $DHCPSERVER_NAME /usr/sbin/dnsmasq -C /etc/dnsmasq.conf

docker exec -ti $WARP_NAME warp-cli --accept-tos connect
echo "Connecting to Cloudflare WARP ...."
sleep 10
docker exec -ti $WARP_NAME warp-cli --accept-tos status
