#!/bin/bash

TMP_FOLDER=$(mktemp -d)
CONFIG_FILE="astrum.conf"
ASTRUM_DAEMON="/usr/local/bin/Astrumd"
ASTRUM_REPO="https://github.com/astrumcash/astrum"


RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'


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

if [ -n "$(pidof $ASTRUM_DAEMON)" ]; then
  echo -e "${GREEN}\c"
  read -e -p "AstrumCash is already running. Do you want to add another MN? [Y/N]" NEW_ASTRUM
  echo -e "{NC}"
  clear
else
  NEW_ASTRUM="new"
fi
}

function prepare_system() {

echo -e "Prepare the system to install Astrum master node."
apt-get update >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get update > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y -qq upgrade
apt install -y software-properties-common >/dev/null 2>&1
echo -e "${GREEN}Adding bitcoin PPA repository"
apt-add-repository -y ppa:bitcoin/bitcoin >/dev/null 2>&1
echo -e "Installing required packages, it may take some time to finish.${NC}"
apt-get update >/dev/null 2>&1
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" make software-properties-common \
build-essential libtool autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev libboost-program-options-dev \
libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git wget pwgen curl libdb4.8-dev bsdmainutils libdb4.8++-dev \
libminiupnpc-dev libgmp3-dev
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
bsdmainutils libdb4.8++-dev libminiupnpc-dev libgmp3-dev"
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

function compile_astrum() {
  echo -e "Clone git repo and compile it. This may take some time. Press a key to continue."
  read -n 1 -s -r -p ""

  #cd $TMP_FOLDER
  #git clone https://github.com/bitcoin-core/secp256k1
  #cd secp256k1
  #chmod +x ./autogen.sh
  #./autogen.sh
  #./configure
  #make
  #compile_error secp256k1
  #./tests
  #sudo make install
  #clear

  cd $TMP_FOLDER
  git clone $ASTRUM_REPO
  cd astrum/src
  make -f makefile.unix # Headless
  compile_error AstraumCash
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
  cat << EOF > /etc/systemd/system/$ASTRUMUSER.service
[Unit]
Description=Astrum service
After=network.target

[Service]
ExecStart=$ASTRUM_DAEMON -conf=$ASTRUMFOLDER/$CONFIG_FILE -datadir=$ASTRUMFOLDER
ExecStop=$ASTRUM_DAEMON -conf=$ASTRUMFOLDER/$CONFIG_FILE -datadir=$ASTRUMFOLDER stop
Restart=on-abord
User=$ASTRUMUSER
Group=$ASTRUMUSER

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  sleep 3
  systemctl start $ASTRUMUSER.service
  systemctl enable $ASTRUMUSER.service

  if [[ -z "$(ps axo user:15,cmd:100 | egrep ^$ASTRUMUSER | grep $ASTRUM_DAEMON)" ]]; then
    echo -e "${RED}Astrumd is not running${NC}, please investigate. You should start by running the following commands as root:"
    echo "systemctl start $ASTRUMUSER.service"
    echo "systemctl status $ASTRUMUSER.service"
    echo "less /var/log/syslog"
    exit 1
  fi
}

function ask_port() {
DEFAULTASTRUMPORT=17720
read -p "ASTRUM Port: " -i $DEFAULTASTRUMPORT -e ASTRUMPORT
: ${ASTRUMPORT:=$DEFAULTASTRUMPORT}
}

function ask_user() {
  DEFAULTASTRUMUSER="astrum"
  read -p "Astrum user: " -i $DEFAULTASTRUMUSER -e ASTRUMUSER
  : ${ASTRUMUSER:=$DEFAULTASTRUMUSER}

  if [ -z "$(getent passwd $ASTRUMUSER)" ]; then
    USERPASS=$(pwgen -s 12 1)
    useradd -m $ASTRUMUSER
    echo "$ASTRUMUSER:$USERPASS" | chpasswd

    ASTRUMHOME=$(sudo -H -u $ASTRUMUSER bash -c 'echo $HOME')
    DEFAULTASTRUMFOLDER="$ASTRUMHOME/.astrum"
    read -p "Configuration folder: " -i $DEFAULTASTRUMFOLDER -e ASTRUMFOLDER
    : ${ASTRUMFOLDER:=$DEFAULTASTRUMFOLDER}
    mkdir -p $ASTRUMFOLDER
    chown -R $ASTRUMUSER: $ASTRUMFOLDER >/dev/null
  else
    clear
    echo -e "${RED}User exits. Please enter another username: ${NC}"
    ask_user
  fi
}

function check_port() {
  declare -a PORTS
  PORTS=($(netstat -tnlp | awk '/LISTEN/ {print $4}' | awk -F":" '{print $NF}' | sort | uniq | tr '\r\n'  ' '))
  ask_port

  while [[ ${PORTS[@]} =~ $ASTRUMPORT ]] || [[ ${PORTS[@]} =~ $[ASTRUMPORT+1] ]]; do
    clear
    echo -e "${RED}Port in use, please choose another port:${NF}"
    ask_port
  done
}

function create_config() {
  RPCUSER=$(pwgen -s 8 1)
  RPCPASSWORD=$(pwgen -s 15 1)
  cat << EOF > $ASTRUMFOLDER/$CONFIG_FILE
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD
rpcallowip=127.0.0.1
rpcport=$[ASTRUMPORT+1]
listen=1
server=1
daemon=1
port=$ASTRUMPORT
EOF
}

function create_key() {
  echo -e "Enter your ${RED}Masternode Private Key${NC}. Leave it blank to generate a new ${RED}Masternode Private Key${NC} for you:"
  read -e ASTRUMKEY
  if [[ -z "$ASTRUMKEY" ]]; then
  sudo -u $ASTRUMUSER $ASTRUM_DAEMON -conf=$ASTRUMFOLDER/$CONFIG_FILE -datadir=$ASTRUMFOLDER
  sleep 5
  if [ -z "$(ps axo user:15,cmd:100 | egrep ^$ASTRUMUSER | grep $ASTRUM_DAEMON)" ]; then
   echo -e "${RED}Astrumd server couldn't start. Check /var/log/syslog for errors.{$NC}"
   exit 1
  fi
  ASTRUMKEY=$(sudo -u $ASTRUMUSER $ASTRUM_DAEMON -conf=$ASTRUMFOLDER/$CONFIG_FILE -datadir=$ASTRUMFOLDER masternode genkey)
  sudo -u $ASTRUMUSER $ASTRUM_DAEMON -conf=$ASTRUMFOLDER/$CONFIG_FILE -datadir=$ASTRUMFOLDER stop
fi
}

function update_config() {
  sed -i 's/daemon=1/daemon=0/' $ASTRUMFOLDER/$CONFIG_FILE
  NODEIP=$(curl -s4 icanhazip.com)
  cat << EOF >> $ASTRUMFOLDER/$CONFIG_FILE
logtimestamps=1
maxconnections=256
masternode=1
masternodeaddr=$NODEIP
masternodeprivkey=$ASTRUMKEY
EOF
  chown -R $ASTRUMUSER: $ASTRUMFOLDER >/dev/null
}

function important_information() {
 echo
 echo -e "================================================================================================================================"
 echo -e "Astrum Masternode is up and running as user ${GREEN}$ASTRUMUSER${NC} and it is listening on port ${GREEN}$ASTRUMPORT${NC}."
 echo -e "${GREEN}$ASTRUMUSER${NC} password is ${RED}$USERPASS${NC}"
 echo -e "Configuration file is: ${RED}$ASTRUMFOLDER/$CONFIG_FILE${NC}"
 echo -e "Start: ${RED}systemctl start $ASTRUMUSER.service${NC}"
 echo -e "Stop: ${RED}systemctl stop $ASTRUMUSER.service${NC}"
 echo -e "VPS_IP:PORT ${RED}$NODEIP:$ASTRUMPORT${NC}"
 echo -e "MASTERNODE PRIVATEKEY is: ${RED}$ASTRUMKEY${NC}"
 echo -e "================================================================================================================================"
}

function setup_node() {
  ask_user
  check_port
  create_config
  create_key
  update_config
  enable_firewall
  systemd_astrum
  important_information
}


##### Main #####
clear

checks
if [[ ("$NEW_ASTRUM" == "y" || "$NEW_ASTRUM" == "Y") ]]; then
  setup_node
  exit 0
elif [[ "$NEW_ASTRUM" == "new" ]]; then
  prepare_system
  compile_astrum
  setup_node
else
  echo -e "${GREEN}Astrumd already running.${NC}"
  exit 0
fi

