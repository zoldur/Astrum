#!/bin/bash

DEFAULTASTRUMUSER="astrum"
DEFAULTASTRUMPORT=25117

function compile_error() {
if [ "$?" -gt "0" ];
 then
  echo -e "${RED}Failed to compile $@. Please investigate.${NC}"
  exit 1
fi
}


function checks() {
if [[ $(lsb_release -d) != *16.04* ]]; then
  echo -e "${RED}You are not running Ubuntu 16.04. Installation is cancelled.${NC}"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}$0 must be run as root.${NC}" 
   exit 1
fi

if [ -n "$(pidof astrumcoind)" ]; then
  echo -e "${GREEN}AstrumCash already running.${NC}"
  exit 1
fi
}

function prepare_system() {

echo -e "Prepare the system to install AstrumCash Master Node."
apt-get update >/dev/null 2>&1
apt install -y software-properties-common >/dev/null 2>&1
echo -e "${GREEN}Adding bitcoin PPA repository"
apt-add-repository -y ppa:bitcoin/bitcoin >/dev/null 2>&1
echo -e "Installing required packages, it may take some time to finish.${NC}"
apt-get update >/dev/null 2>&1
apt-get install -y make software-properties-common build-essential libtool autoconf libssl-dev libboost-dev libboost-chrono-dev \
libboost-filesystem-dev libboost-program-options-dev libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git \
wget pwgen curl libdb4.8-dev bsdmainutils libdb4.8++-dev libminiupnpc-dev libgmp-dev
clear
if [ "$?" -gt "0" ];
  then
    echo -e "${RED}Not all required packages were installed properly. Try to install them manually by running the following commands:${NC}\n"
        echo "apt-get update"
    echo "apt -y install software-properties-common"
    echo "apt-add-repository -y ppa:bitcoin/bitcoin"
    echo "apt-get update"
    echo "apt install -y make build-essential libtool software-properties-common autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev \
libboost-program-options-dev libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git pwgen curl libdb4.8-dev \
bsdmainutils libdb4.8++-dev libminiupnpc-dev libgmp-dev" 
 exit 1
fi

clear
echo -e "Checking if swap space is needed."
PHYMEM=$(free -g|awk '/^Mem:/{print $2}')
if [ "$PHYMEM" -lt "2" ];
  then
    echo -e "${GREEN}Server is running with less than 2G of RAM, creating 2G swap file.${NC}"
    dd if=/dev/zero of=/swapfile bs=1024 count=2M
    chmod 600 /swapfile
    mkswap /swapfile
    swapon -a /swapfile
else
  echo -e "${GREEN}Server running with at least 2G of RAM, no swap needed.${NC}"
fi
clear
}


function compile_astrumcoin() {
echo -e "Clone git repo and compile it. This may take some time. Press a key to continue."
read -n 1 -s -r -p ""

  git clone https://github.com/bitcoin-core/secp256k1
  cd ~/secp256k1
  chmod +x ./autogen.sh
  ./autogen.sh
  ./configure
  make
  compile_error secp256k1
  ./tests
  sudo make install
  cd ~
  git clone https://github.com/astrumcash/astrum
  cd ~/astrum/src
  make -f makefile.unix # Headless
  compile_error Astraumcash
  cp -a Astrumd /usr/local/bin
  clear
}

function enable_firewall() {
FWSTATUS=$(ufw status 2>/dev/null|awk '/^Status:/{print $NF}')
if [ "$FWSTATUS" = "active" ]; then
  echo -e "Setting up firewall to allow ingress on port ${GREEN}$ASTRUMPORT${NC}"
  ufw allow $ASTRUMPORT/tcp comment "Astrum MN port" >/dev/null
fi
}

function systemd_astrum() {

cat << EOF > /etc/systemd/system/Astrumd.service
[Unit]
Description=AstrumD service
After=network.target
[Service]
ExecStart=/usr/local/bin/Astrumd -conf=$ASTRUMFOLDER/Astrum.conf -datadir=$ASTRUMFOLDER
ExecStop=/usr/local/bin/Astrumd -conf=$ASTRUMFOLDER/Astrum.conf -datadir=$ASTRUMFOLDER stop
Restart=on-abort
User=$ASTRUMUSER
Group=$ASTRUMUSER
[Install]
WantedBy=multi-user.target
EOF
}

##### Main #####
clear

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

checks
prepare_system
compile_astrumcoin


echo -e "${GREEN}Prepare to configure and start AstrumCash Masternode.${NC}"

read -p "AstrumCash user: " -i $DEFAULTASTRUMUSER -e ASTRUMUSER
: ${ASTRUMUSER:=$DEFAULTASTRUMUSER}
useradd -m $ASTRUMUSER >/dev/null
ASTRUMHOME=$(sudo -H -u $ASTRUMUSER bash -c 'echo $HOME')

DEFAULTASTRUMFOLDER="$ASTRUMHOME/.Astrum"
read -p "Configuration folder: " -i $DEFAULTASTRUMFOLDER -e ASTRUMFOLDER
: ${ASTRUMFOLDER:=$DEFAULTASTRUMFOLDER}
mkdir -p $ASTRUMFOLDER

RPCUSER=$(pwgen -s 8 1)
RPCPASSWORD=$(pwgen -s 15 1)
cat << EOF > $ASTRUMFOLDER/Astrum.conf
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD
rpcallowip=127.0.0.1
listen=1
server=1
daemon=1
EOF
chown -R $ASTRUMUSER $ASTRUMFOLDER >/dev/null


read -p "ASTRUM Port: " -i $DEFAULTASTRUMPORT -e ASTRUMPORT
: ${ASTRUMPORT:=$DEFAULTASTRUMPORT}
:wq
echo -e "Enter your ${RED}Masternode Private Key${NC}. Leave it blank to generate a new ${RED}Masternode Private Key${NC} for you:"
read -e ASTRUMKEY
if [[ -z "$ASTRUMKEY" ]]; then
 sudo -u $ASTRUMUSER /usr/local/bin/Astrumd -conf=$ASTRUMFOLDER/Astrum.conf -datadir=$ASTRUMFOLDER
 sleep 5
 if [ -z "$(pidof Astrumd)" ]; then
   echo -e "${RED}AstrumCash server couldn't start. Check /var/log/syslog for errors.{$NC}"
   exit 1
 fi
 ASTRUMKEY=$(sudo -u $ASTRUMUSER /usr/local/bin/Astrumd -conf=$ASTRUMFOLDER/Astrum.conf -datadir=$ASTRUMFOLDER masternode genkey)
 kill $(pidof Astrumd)
fi

sed -i 's/daemon=1/daemon=0/' $ASTRUMFOLDER/Astrum.conf
NODEIP=$(curl -s4 icanhazip.com)
cat << EOF >> $ASTRUMFOLDER/Astrum.conf
maxconnections=256
masternode=1
masternodeprivkey=$ASTRUMKEY
masternodeaddr=$NODEIP:$ASTRUMPORT
EOF
chown -R $ASTRUMUSER: $ASTRUMFOLDER >/dev/null


systemd_astrum
enable_firewall


systemctl daemon-reload
sleep 3
systemctl start Astrumd.service
systemctl enable Astrumd.service


if [[ -z $(pidof Astrumd) ]]; then
  echo -e "${RED}AstrumCash is not running${NC}, please investigate. You should start by running the following commands as root:"
  echo "systemctl start Astrumd.service"
  echo "systemctl status Astrumd.service"
  echo "less /var/log/syslog"
  exit 1 
fi

echo
echo -e "======================================================================================================================="
echo -e "AstrumCashh Masternode is up and running as user ${GREEN}$ASTRUMUSER${NC} and it is listening on port ${GREEN}$ASTRUMPORT${NC}." 
echo -e "Configuration file is: ${RED}$ASTRUMFOLDER/astrumcoin.conf${NC}"
echo -e "VPS_IP:PORT ${RED}$NODEIP:$ASTRUMPORT${NC}"
echo -e "MASTERNODE PRIVATEKEY is: ${RED}$ASTRUMKEY${NC}"
echo -e "========================================================================================================================"

