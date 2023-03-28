# !/bin/bash -lxe

help() {

    echo -e "Cloudflare WARP Client on ZPE"
    echo -e "deployCloudflareWARP.sh <Options>"
    echo
    echo -e "Options:"
    echo -e "-a, --all           build the images and instantiate the App"
    echo -e "-b, --build         build the images"
    echo -e "-d, --deploy        deploy the WARP App"
    echo -e "-c, --clean         clean the deployment"
    echo -e "-m, --bridge        LAN bridge"
    echo -e "-h, --help          display help"

    exit 1
}

check_root() {
if [[ $EUID -ne 0 ]]
then
   echo "deployCloudflareWARP.sh must be run as root..." 1>&2
   exit 1
fi
}

check_root

if [[ $# -eq 0 ]]
then
    echo "Try 'deployCloudflareWARP.sh --help' for more information"
    exit 0
fi

OPTIONS=`getopt -o abdchm: --long all,build,deploy,clean,help,bridge: -n 'parse-options' -- "$@"`

if [ $? != 0 ]
then
    echo "error while parsing options!" >&2
    exit 1
fi    

eval set --"$OPTIONS"

ALL=false
BUILD=false
DEPLOY=false
CLEAN=false

while true
do
    case "$1" in
        -a | --all ) ALL=true
        shift
	;;
        -b | --build ) BUILD=true
        shift
	;;
        -d | --deploy ) DEPLOY=true
        shift
	;;
        -m | --bridge ) BRIDGE="$2"
        shift; shift
	;;
        -c | --clean ) CLEAN=true
        shift
	;;
        -h | --help )shift; help
	;;
        -- ) shift; break
	;;
        * ) break
	;;
    esac
done


if [ "$ALL" == false ] && [ "$BUILD" == false ] && [ "$BUILD" == false ] && [ "$CLEAN" == false ]
then
    echo -e "\n NO option specified! \n"
    exit 1
fi

if [ "$ALL" == true ]
then
    BUILD=true
    DEPLOY=true
fi

WARP_NAME=warp
DHCPSERVER_NAME=dhcpserver

if [ "$CLEAN" == true ] || [ "$DEPLOY" == true ]
then
    if ip netns show "$WARP_NAME" >/dev/null 2>&1 ; then
      ip -n $WARP_NAME link del dev A-warp 2> /dev/null
      ip netns del "$WARP_NAME" 2> /dev/null
    fi
    if ip netns show "$DHCPSERVER_NAME" >/dev/null 2>&1 ; then
      ip -n $DHCPSERVER_NAME link del dev A-warp-peer 2> /dev/null
      ip -n $DHCPSERVER_NAME link del dev B-dhcp-peer 2> /dev/null
      ip netns del "$DHCPSERVER_NAME" 2> /dev/null
    fi
    
    echo "Deleting docker containers ..."
    docker rm -f $WARP_NAME $DHCPSERVER_NAME 2> /dev/null
fi

if [ "$CLEAN" == true ]
then
    echo "Deployment clean up process executed!"
    exit 1
fi

if [ "$BUILD" == true ]
then
    cd warp
    docker build --tag warp .
    cd ..

    cd dhcpserver
    docker build --tag dhcpserver .
    cd ..
fi

if [ "$DEPLOY" == true ]
then
    if [ -z "$BRIDGE" ]
    then
        echo -e "\n A LAN Bridge must be specified. This bridge connects with the LAN side\n\n"
        help
        exit 1
    fi
    
    if  [[ ! `ip -d link show ${BRIDGE}` ]]; then
        echo "Bridge interface ${BRIDGE} does not exists"
        exit -1;
    elif [[ ! `ip -d link show ${BRIDGE} | grep bridge` ]] ; then
        echo "Interface ${BRIDGE} exists but it is not bridge type"
        exit -1;
    fi

    #ip link add dev A type veth peer name Apeer
    ip link add dev A-warp type veth peer name A-warp-peer
    ip link add dev B-dhcp type veth peer name B-dhcp-peer
    
    docker run --name $WARP_NAME \
	    --cap-add=NET_ADMIN \
	    -v $PWD/$WARP_NAME/mdm.xml:/var/lib/cloudflare-warp/mdm.xml \
	    -v $PWD/$WARP_NAME/dnsmasq.conf:/etc/dnsmasq.conf \
	    -d --privileged warp
    
    docker run --name $DHCPSERVER_NAME \
	    --net=none \
	    --cap-add=NET_ADMIN \
	    --dns 192.168.99.1 \
	    -v $PWD/$DHCPSERVER_NAME/dnsmasq.conf:/etc/dnsmasq.conf \
	    -d dhcpserver 
    
    for name in $WARP_NAME $DHCPSERVER_NAME; do
      ip netns attach $name $(docker inspect --format '{{.State.Pid}}' $name)
    done
    
    ip link set dev A-warp netns $WARP_NAME
    ip link set dev A-warp-peer netns $DHCPSERVER_NAME
    ip link set dev B-dhcp-peer netns $DHCPSERVER_NAME
    ip link set dev B-dhcp master ${BRIDGE}
    ip link set dev B-dhcp up
    
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
 
    echo "Cloudflare WARP deployment executed!"
 fi

