# Color config
BLUE='\033[1;34m'
CLEAR='\033[0m'
DARK='\033[2m'
GREEN='\033[1;32m'
GREY='\033[36m'
NC='\033[0m'
RED='\033[1;31m'
WHITE='\033[1;39m'

# Configure
TMP_FOLDER=$(mktemp -d)
NODEIP=$(curl -s4 api.ipify.org)




function download_node() {
  echo -e ":: Downloading coin ${GREEN}nodebase${NC}..."
  cd $TMP_FOLDER >/dev/null 2>&1
  wget -q https://github.com/NodeBaseCore/NodeBaseCoin/releases/download/v1.0/linux.tar.gz
  compile_error
  echo -e ":: Extracting coin..."
  tar xvfz linux.tar.gz -C /usr/local/bin/
  cd - >/dev/null 2>&1
  rm -rf $TMP_FOLDER >/dev/null 2>&1
}


function configure_systemd() {
  cat << EOF > /etc/systemd/system/nodebase.service
[Unit]
Description=nodebase service
After=network.target

[Service]
User=root
Group=root

Type=forking
#PIDFile=/root/.nodebase/nodebase.pid

ExecStart=/usr/local/bin/nodebased -daemon -conf=/root/.nodebase/nodebase.conf -datadir=/root/.nodebase
ExecStop=-/usr/local/bin/nodebase-cli -conf=/root/.nodebase/nodebase.conf -datadir=/root/.nodebase stop

Restart=always
PrivateTmp=true
TimeoutStopSec=60s
TimeoutStartSec=10s
StartLimitInterval=120s
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  sleep 3
  systemctl start nodebase.service
  systemctl enable nodebase.service >/dev/null 2>&1

  if [[ -z "$(ps axo cmd:100 | egrep nodebased)" ]]; then
    echo -e "${RED}nodebase is not running${NC}, please investigate. You should start by running the following commands as root:"
    echo -e "${GREEN}systemctl start nodebase.service"
    echo -e "systemctl status nodebase.service"
    echo -e "less /var/log/syslog${NC}"
    exit 1
  fi
}


function create_config() {
  mkdir /root/.nodebase >/dev/null 2>&1
  RPCUSER=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n1)
  RPCPASSWORD=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w22 | head -n1)
  cat << EOF > /root/.nodebase/nodebase.conf
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD
#rpcport=22002
rpcallowip=127.0.0.1
listen=1
server=1
daemon=1
port=22001
EOF
}

function create_key() {
  echo -e "${WHITE}:: Enter your nodebase Masternode Private Key${CLEAR}:"
  echo -e "${GREY}   Leave it blank to generate a new Masternode Private Key for you.${CLEAR}"
  echo -n "  "
  read -t 5 -e COINKEY
  if [[ -z "$COINKEY" ]]; then
  /usr/local/bin/nodebased -daemon
  sleep 30
  if [ -z "$(ps axo cmd:100 | grep nodebased)" ]; then
   echo -e "${RED}:: nodebase service failed to start. Review journalctl for errors.{$NC}"
   exit 1
  fi
  COINKEY=$(/usr/local/bin/nodebase-cli masternode genkey)
  if [ "$?" -gt "0" ];
    then
    echo -e "${RED}:: Wallet yet to fully load. Waiting 30s before trying again...${NC}"
    sleep 30
    COINKEY=$(/usr/local/bin/nodebase-cli masternode genkey)
  fi
  /usr/local/bin/nodebase-cli stop
fi
}

function update_config() {
  sed -i 's/daemon=1/daemon=0/' /root/.nodebase/nodebase.conf
  cat << EOF >> /root/.nodebase/nodebase.conf
logintimestamps=1
maxconnections=256
#bind=$NODEIP
masternode=1
externalip=$NODEIP:22001
masternodeprivkey=$COINKEY
addnode=206.189.166.205:22001
addnode=206.189.208.80:22001
EOF
}


function enable_firewall() {
  echo -e ":: Configuring firewall to allow access via port ${GREEN}22001${NC}"
  ufw allow 22001/tcp comment "nodebase MN port" >/dev/null
  ufw allow ssh comment "SSH" >/dev/null 2>&1
  ufw limit ssh/tcp >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1
  echo "y" | ufw enable >/dev/null 2>&1
}


function get_ip() {
  declare -a NODE_IPS
  for ips in $(netstat -i | awk '!/Kernel|Iface|lo/ {print $1," "}')
  do
    NODE_IPS+=($(curl --interface $ips --connect-timeout 2 -s4 api.ipify.org))
  done

  if [ ${#NODE_IPS[@]} -gt 1 ]
    then
      echo -e "${GREEN}:: This machine has more than one IP address. Please type 0 to use the first IP, 1 for the second and so on...${NC}"
      INDEX=0
      for ip in "${NODE_IPS[@]}"
      do
        echo ${INDEX} 
        let INDEX=${INDEX}+1
      done
      read -e choose_ip
      NODEIP=${NODE_IPS[$choose_ip]}
  else
    NODEIP=${NODE_IPS[0]}
  fi
}


function compile_error() {
if [ "$?" -gt "0" ];
 then
  echo -e "${RED}:: Unable to retrieve binaries for nodebase - URL invalid${NC}"
  exit 1
fi
}


function checks() {
if [[ $(lsb_release -d) != *16.04* ]]; then
  echo -e "${RED}:: This server is not running Ubuntu 16.04 - aborting setup${NC}"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}:: Must run as root user - aborting setup${NC}"
   exit 1
fi

if [ -n "$(pidof nodebased)" ] || [ -e "" ] ; then
  echo -e "${RED}:: nodebase is already installed - aborting setup${NC}"
  exit 1
fi
}

function prepare_system() {
echo -e ":: Preparing to install ${GREEN}nodebase${NC} master node..."
echo -e ":: Updating system..."
apt-get update >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get update > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y -qq upgrade >/dev/null 2>&1
apt install -y software-properties-common >/dev/null 2>&1
echo -e ":: Adding bitcoin repository..."
apt-add-repository -y ppa:bitcoin/bitcoin >/dev/null 2>&1
echo -e ":: Installing build packages (this could take some time)..."
apt-get update >/dev/null 2>&1
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" make software-properties-common build-essential libtool autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev libboost-program-options-dev libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git wget curl libdb4.8-dev bsdmainutils libdb4.8++-dev libminiupnpc-dev libgmp3-dev ufw pkg-config libevent-dev  unzip libzmq5 >/dev/null 2>&1
if [ "$?" -gt "0" ];
  then
    echo -e "${RED}:: Not all required packages were installed properly. Try installing these manually using the following command:${NC}\n"
    echo "apt-get update"
    echo "apt -y install software-properties-common"
    echo "apt-add-repository -y ppa:bitcoin/bitcoin"
    echo "apt-get update"
    echo "apt install -y make build-essential libtool software-properties-common autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev libboost-program-options-dev libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git curl libdb4.8-dev bsdmainutils libdb4.8++-dev libminiupnpc-dev libgmp3-dev ufw pkg-config libevent-dev unzip libzmq5"
 exit 1
fi
}

function important_information() {
  clear
  echo -e "nodebase Masternode Successfully Set up!"
  echo -e "${GREY}--------${CLEAR}"
  echo -e "Service running on: ${GREEN}$NODEIP:22001${NC}."
  echo -e "Configuration file path: ${GREEN}/root/.nodebase/nodebase.conf${NC}"
  echo -e "Private key: ${GREEN}$COINKEY${NC}"
  echo -e "To start, run: ${GREEN}systemctl start nodebase.service${NC}"
  echo -e "To stop, run: ${GREEN}systemctl stop nodebase.service${NC}"
  echo
  echo -e "Run ${GREEN}systemctl status nodebase${CLEAR} to check service status"
  echo -e "Run ${GREEN}nodebase-cli masternode status${NC} to check your masternode"
  if [[ -n $SENTINEL_REPO  ]]; then
   echo -e "${RED}Sentinel${NC} is installed in ${RED}/root/.nodebase/sentinel${NC}"
   echo -e "Sentinel logs is: ${RED}/root/.nodebase/sentinel.log${NC}"
  fi
  echo
  echo -e "YourNodePro\n \ ${GREEN}discord.gg/7v5qzJu${CLEAR}\n \ ${GREEN}facebook.com/yournodepro${CLEAR}\n \ ${GREEN}twitter.com/YourNodePro${CLEAR}"
}



function setup_node() {
  get_ip
  create_config
  create_key
  update_config
  enable_firewall
  important_information
  configure_systemd
}


##### Main #####
clear

checks
prepare_system
download_node
setup_node

# Color config
BLUE='\033[1;34m'
CLEAR='\033[0m'
DARK='\033[2m'
GREEN='\033[1;32m'
GREY='\033[36m'
NC='\033[0m'
RED='\033[1;31m'
WHITE='\033[1;39m'

# Configure
TMP_FOLDER=$(mktemp -d)
NODEIP=$(curl -s4 api.ipify.org)




function download_node() {
  echo -e ":: Downloading coin ${GREEN}nodebase${NC}..."
  cd $TMP_FOLDER >/dev/null 2>&1
  wget -q 
  compile_error
  echo -e ":: Extracting coin..."
  tar xvfz  -C /usr/local/bin/
  cd - >/dev/null 2>&1
  rm -rf $TMP_FOLDER >/dev/null 2>&1
}


function configure_systemd() {
  cat << EOF > /etc/systemd/system/nodebase.service
[Unit]
Description=nodebase service
After=network.target

[Service]
User=root
Group=root

Type=forking
#PIDFile=/root/.nodebase/nodebase.pid

ExecStart=/usr/local/bin/nodebased -daemon -conf=/root/.nodebase/nodebase.conf -datadir=/root/.nodebase
ExecStop=-/usr/local/bin/nodebase-cli -conf=/root/.nodebase/nodebase.conf -datadir=/root/.nodebase stop

Restart=always
PrivateTmp=true
TimeoutStopSec=60s
TimeoutStartSec=10s
StartLimitInterval=120s
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  sleep 3
  systemctl start nodebase.service
  systemctl enable nodebase.service >/dev/null 2>&1

  if [[ -z "$(ps axo cmd:100 | egrep nodebased)" ]]; then
    echo -e "${RED}nodebase is not running${NC}, please investigate. You should start by running the following commands as root:"
    echo -e "${GREEN}systemctl start nodebase.service"
    echo -e "systemctl status nodebase.service"
    echo -e "less /var/log/syslog${NC}"
    exit 1
  fi
}


function create_config() {
  mkdir /root/.nodebase >/dev/null 2>&1
  RPCUSER=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n1)
  RPCPASSWORD=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w22 | head -n1)
  cat << EOF > /root/.nodebase/nodebase.conf
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD
#rpcport=22002
rpcallowip=127.0.0.1
listen=1
server=1
daemon=1
port=https://github.com/NodeBaseCore/NodeBaseCoin/releases/download/v1.0/linux.tar.gz22001
EOF
}

function create_key() {
  echo -e "${WHITE}:: Enter your nodebase Masternode Private Key${CLEAR}:"
  echo -e "${GREY}   Leave it blank to generate a new Masternode Private Key for you.${CLEAR}"
  echo -n "  "
  read -t 5 -e COINKEY
  if [[ -z "$COINKEY" ]]; then
  /usr/local/bin/nodebased -daemon
  sleep 30
  if [ -z "$(ps axo cmd:100 | grep nodebased)" ]; then
   echo -e "${RED}:: nodebase service failed to start. Review journalctl for errors.{$NC}"
   exit 1
  fi
  COINKEY=$(/usr/local/bin/nodebase-cli masternode genkey)
  if [ "$?" -gt "0" ];
    then
    echo -e "${RED}:: Wallet yet to fully load. Waiting 30s before trying again...${NC}"
    sleep 30
    COINKEY=$(/usr/local/bin/nodebase-cli masternode genkey)
  fi
  /usr/local/bin/nodebase-cli stop
fi
}

function update_config() {
  sed -i 's/daemon=1/daemon=0/' /root/.nodebase/nodebase.conf
  cat << EOF >> /root/.nodebase/nodebase.conf
logintimestamps=1
maxconnections=256
#bind=$NODEIP
masternode=1
externalip=$NODEIP:https://github.com/NodeBaseCore/NodeBaseCoin/releases/download/v1.0/linux.tar.gz22001
masternodeprivkey=$COINKEY
addnode=206.189.166.205:22001
addnode=206.189.208.80:22001
EOF
}


function enable_firewall() {
  echo -e ":: Configuring firewall to allow access via port ${GREEN}https://github.com/NodeBaseCore/NodeBaseCoin/releases/download/v1.0/linux.tar.gz22001${NC}"
  ufw allow https://github.com/NodeBaseCore/NodeBaseCoin/releases/download/v1.0/linux.tar.gz22001/tcp comment "nodebase MN port" >/dev/null
  ufw allow ssh comment "SSH" >/dev/null 2>&1
  ufw limit ssh/tcp >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1
  echo "y" | ufw enable >/dev/null 2>&1
}


function get_ip() {
  declare -a NODE_IPS
  for ips in $(netstat -i | awk '!/Kernel|Iface|lo/ {print $1," "}')
  do
    NODE_IPS+=($(curl --interface $ips --connect-timeout 2 -s4 api.ipify.org))
  done

  if [ ${#NODE_IPS[@]} -gt 1 ]
    then
      echo -e "${GREEN}:: This machine has more than one IP address. Please type 0 to use the first IP, 1 for the second and so on...${NC}"
      INDEX=0
      for ip in "${NODE_IPS[@]}"
      do
        echo ${INDEX} 
        let INDEX=${INDEX}+1
      done
      read -e choose_ip
      NODEIP=${NODE_IPS[$choose_ip]}
  else
    NODEIP=${NODE_IPS[0]}
  fi
}


function compile_error() {
if [ "$?" -gt "0" ];
 then
  echo -e "${RED}:: Unable to retrieve binaries for nodebase - URL invalid${NC}"
  exit 1
fi
}


function checks() {
if [[ $(lsb_release -d) != *16.04* ]]; then
  echo -e "${RED}:: This server is not running Ubuntu 16.04 - aborting setup${NC}"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}:: Must run as root user - aborting setup${NC}"
   exit 1
fi

if [ -n "$(pidof nodebased)" ] || [ -e "" ] ; then
  echo -e "${RED}:: nodebase is already installed - aborting setup${NC}"
  exit 1
fi
}

function prepare_system() {
echo -e ":: Preparing to install ${GREEN}nodebase${NC} master node..."
echo -e ":: Updating system..."
apt-get update >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get update > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y -qq upgrade >/dev/null 2>&1
apt install -y software-properties-common >/dev/null 2>&1
echo -e ":: Adding bitcoin repository..."
apt-add-repository -y ppa:bitcoin/bitcoin >/dev/null 2>&1
echo -e ":: Installing build packages (this could take some time)..."
apt-get update >/dev/null 2>&1
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" make software-properties-common build-essential libtool autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev libboost-program-options-dev libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git wget curl libdb4.8-dev bsdmainutils libdb4.8++-dev libminiupnpc-dev libgmp3-dev ufw pkg-config libevent-dev  unzip libzmq5 >/dev/null 2>&1
if [ "$?" -gt "0" ];
  then
    echo -e "${RED}:: Not all required packages were installed properly. Try installing these manually using the following command:${NC}\n"
    echo "apt-get update"
    echo "apt -y install software-properties-common"
    echo "apt-add-repository -y ppa:bitcoin/bitcoin"
    echo "apt-get update"
    echo "apt install -y make build-essential libtool software-properties-common autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev libboost-program-options-dev libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git curl libdb4.8-dev bsdmainutils libdb4.8++-dev libminiupnpc-dev libgmp3-dev ufw pkg-config libevent-dev unzip libzmq5"
 exit 1
fi
}

function important_information() {
  clear
  echo -e "nodebase Masternode Successfully Set up!"
  echo -e "${GREY}--------${CLEAR}"
  echo -e "Service running on: ${GREEN}$NODEIP:https://github.com/NodeBaseCore/NodeBaseCoin/releases/download/v1.0/linux.tar.gz22001${NC}."
  echo -e "Configuration file path: ${GREEN}/root/.nodebase/nodebase.conf${NC}"
  echo -e "Private key: ${GREEN}$COINKEY${NC}"
  echo -e "To start, run: ${GREEN}systemctl start nodebase.service${NC}"
  echo -e "To stop, run: ${GREEN}systemctl stop nodebase.service${NC}"
  echo
  echo -e "Run ${GREEN}systemctl status nodebase${CLEAR} to check service status"
  echo -e "Run ${GREEN}nodebase-cli masternode status${NC} to check your masternode"
  if [[ -n $SENTINEL_REPO  ]]; then
   echo -e "${RED}Sentinel${NC} is installed in ${RED}/root/.nodebase/sentinel${NC}"
   echo -e "Sentinel logs is: ${RED}/root/.nodebase/sentinel.log${NC}"
  fi
  echo
  echo -e "YourNodePro\n \ ${GREEN}discord.gg/7v5qzJu${CLEAR}\n \ ${GREEN}facebook.com/yournodepro${CLEAR}\n \ ${GREEN}twitter.com/YourNodePro${CLEAR}"
}



function setup_node() {
  get_ip
  create_config
  create_key
  update_config
  enable_firewall
  important_information
  configure_systemd
}


##### Main #####
clear

checks
prepare_system
download_node
setup_node

