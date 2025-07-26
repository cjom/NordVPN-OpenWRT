#!/bin/sh
{

# Use NORDVPN_TOKEN with the token you get from https://my.nordaccount.com/dashboard/nordvpn/access-tokens/
# Use NORDVPN_BASIC_TOKEN if OpenWrt not built with 'CONFIG_LIBCURL_HTTP_AUTH=y'
# See https://github.com/cjom/NordVPN-OpenWRT for instructions to get the basic token

# Configuration parameters
NORDVPN_BASIC_TOKEN=''
NORDVPN_TOKEN=''
WAN_IF='wan'
VPN_IF='wg0'
VPN_PORT='51820'            # DO NOT CHANGE THIS
VPN_ADDR='10.5.0.2/32'      # DO NOT CHANGE THIS
VPN_DNS1='103.86.99.99'     # optional: these are the Threat Protection Lite DNS servers
VPN_DNS2='103.86.96.96'     # optional: these are the Threat Protection Lite DNS servers

# List of IPs to randomly ping
IP0='8.8.8.8'
IP1='8.8.4.4'
IP2='1.1.1.1'
IP3='1.0.0.1'
IP4='208.67.222.222'
IP5='208.67.220.220'
IP6='9.9.9.9'
IP7='149.112.112.112'
IP8='195.46.39.39'
IP9='195.46.39.40'
IP10='45.90.28.165'
IP11='45.90.30.165'
IP12='156.154.70.1'
IP13='156.154.71.1'
IP14='8.26.56.26'
IP15='8.20.247.20'
IP16='64.6.64.6'
IP17='64.6.65.6'
IP18='209.244.0.3'
IP19='209.244.0.4'

get_private_key () {
  if [ -n "$NORDVPN_BASIC_TOKEN" ]; then
    PRIVATE_KEY=$(curl -H "authorization: Basic $NORDVPN_BASIC_TOKEN" -s https://api.nordvpn.com/v1/users/services/credentials | jq -r .nordlynx_private_key)
  elif [ -n "$NORDVPN_TOKEN" ]; then
    PRIVATE_KEY=$(curl -s -u "token:$NORDVPN_TOKEN" https://api.nordvpn.com/v1/users/services/credentials | jq -r .nordlynx_private_key)
  else
    echo '*** ERROR: TOKEN IS NOT DEFINED ***'; exit 1;
  fi
}

get_servers_list () {
  curl -o /tmp/nordvpn.json -s 'https://api.nordvpn.com/v1/servers/recommendations?&filters\[servers_technologies\]\[identifier\]=wireguard_udp&limit=10'
}

for cmd in awk curl grep ifup ip jq ping service uci ; do
  command -v $cmd >/dev/null 2>&1 || { echo "*** $cmd IS MISSING, PLEASE INSTALL ***"; exit 1; }
done

if ! ip link | grep -m 1 -q "$VPN_IF" ; then
  echo "*** $VPN_IF NOT FOUND - IT WILL BE CREATED ***"
  get_private_key
  [ -z "$PRIVATE_KEY" ] && { echo '*** ERROR: COULD NOT RETRIEVE PRIVATE_KEY ***'; exit 1; }

  if get_servers_list && jq -er '.[0].station' /tmp/nordvpn.json >/dev/null 2>&1 ; then
    # Assign VPN interface to WAN zone to minimize firewall setup
    VPN_ZONE=$(uci show firewall | grep zone | grep -m 1 "$VPN_IF")
    WAN_ZONE=$(uci show firewall | grep zone | grep -m 1 "$WAN_IF")
    [ -n "$VPN_ZONE" ] && uci -q del_list "${VPN_ZONE%.name*}.network"="$VPN_IF"
    uci add_list "${WAN_ZONE%.name*}.network"="$VPN_IF"
    uci commit firewall
    service firewall restart

    # Configure wireguard network interface
    uci -q delete "network.${VPN_IF}"
    uci set "network.${VPN_IF}"='interface'
    uci set "network.${VPN_IF}.proto"='wireguard'
    uci add_list "network.${VPN_IF}.addresses"="$VPN_ADDR"
    uci set "network.${VPN_IF}.private_key"="$PRIVATE_KEY"
    if [ -n "$VPN_DNS1" ] || [ -n "$VPN_DNS2" ]; then
      uci set "network.${VPN_IF}.peerdns"='0'
      [ -n "$VPN_DNS1" ] && uci add_list "network.${VPN_IF}.dns"="$VPN_DNS1"
      [ -n "$VPN_DNS2" ] && uci add_list "network.${VPN_IF}.dns"="$VPN_DNS2"
    else
      uci set "network.${VPN_IF}.peerdns"='1'
    fi
    uci set "network.${VPN_IF}.delegate"='0'
    uci set "network.${VPN_IF}.force_link"='1'
    # Add VPN peers
    uci -q delete "network.${VPN_IF}server"
    uci set "network.${VPN_IF}server"="wireguard_${VPN_IF}"
    uci set "network.${VPN_IF}server.endpoint_port"="$VPN_PORT"
    uci set "network.${VPN_IF}server.persistent_keepalive"='25'
    uci set "network.${VPN_IF}server.route_allowed_ips"='1'
    uci add_list "network.${VPN_IF}server.allowed_ips"='0.0.0.0/0'
    jq -r '.[0] | .hostname, .station, (.technologies.[].metadata.[] | select(.name=="public_key") | .value)' /tmp/nordvpn.json | while read -r HOST_NAME && read -r SERVER_IP && read -r PUBLIC_KEY; do
      uci set "network.${VPN_IF}server.description"="$HOST_NAME"
      uci set "network.${VPN_IF}server.endpoint_host"="$SERVER_IP"
      uci set "network.${VPN_IF}server.public_key"="$PUBLIC_KEY"
    done
    uci set "network.${WAN_IF}.metric"='1024'
    uci commit network
    service network restart
    echo "*** $VPN_IF CREATED ***"
  else
    echo '*** ERROR: COULD NOT RETRIEVE VPN SERVERS ***'; exit 1;
  fi
fi

echo '*** NordVPN watchdog started ***'
sleep 120
eval ping -q -c 1 -W 5 "\$IP$(awk 'BEGIN { srand(); print int((rand()*10000000))%20 }')" -I "$VPN_IF" >/dev/null 2>&1 || ifup "$VPN_IF"

while :; do
  sleep 60
  failedpings=0
  [ -f /tmp/nordvpn.json ] || get_servers_list
  while ! eval ping -q -c 1 -W 5 "\$IP$(awk 'BEGIN { srand(); print int((rand()*10000000))%20 }')" -I "$VPN_IF" >/dev/null 2>&1 && eval ping -q -c 1 -W 5 "\$IP$(awk 'BEGIN { srand(); print int((rand()*10000000))%20 }')" -I eth1 >/dev/null 2>&1; do
    if [ "$failedpings" -gt 9 ]; then
      echo "*** PING FAILED $failedpings TIMES - RESTARTING $VPN_IF ***"
      ifdown "$VPN_IF"
      sleep 10
      ifup "$VPN_IF"
      sleep 60
    elif [ "$failedpings" -ge 5 ]; then
      echo "*** PING FAILED $failedpings TIMES ******"
      if jq -e '.[].station' /tmp/nordvpn.json >/dev/null 2>&1 ; then
        echo '*** Changing VPN server ***'
        jq -r '.[] | .hostname, .station, (.technologies.[].metadata.[] | select(.name=="public_key") | .value)' /tmp/nordvpn.json | while read -r HOST_NAME && read -r SERVER_IP && read -r PUBLIC_KEY; do
          if [ "$(uci get network.${VPN_IF}server.endpoint_host)" != "$SERVER_IP" ]; then
            uci set "network.${VPN_IF}server.public_key"="$PUBLIC_KEY"
            uci set "network.${VPN_IF}server.endpoint_host"="$SERVER_IP"
            uci set "network.${VPN_IF}server.description"="$HOST_NAME"
            uci commit network
            echo "*** VPN server changed to $HOST_NAME ( $SERVER_IP ) ***"
            echo '*** Restarting network ***'
            /etc/init.d/network restart
            sleep 60
            eval ping -q -c 1 -W 5 "\$IP$(awk 'BEGIN { srand(); print int(rand()*10000000)%20 }')" -I "$VPN_IF" >/dev/null 2>&1 && echo '*** VPN connection restored ***' && break
          fi
        done
      else
        echo '*** Restarting network ***'
        /etc/init.d/network restart
        sleep 60
      fi
    fi
    sleep 6
    failedpings=$((failedpings+1))
  done
done
} 2>&1 | logger $([ ${DEBUG+x} ] && echo '-p user.debug') -t "$(basename "$0" | grep -Eo '^.{0,23}')"[$$]
