# MasterNodeScript

Shell script to install a [NodeBase](https://bitcointalk.org/index.php?topic=4903449.new#new) masternode on a Linux server running Ubuntu 16.04.
Use it on your own risk.
***

## VPS installation
```
wget -q https://raw.githubusercontent.com/NodeBaseCore/MasterNodeScript/master/setup.sh && bash setup.sh
```
***

## Desktop wallet setup

After the Masternode is up and running, you need to configure the desktop wallet accordingly. Here are the steps:
1. Open the NodeBase Desktop Wallet.
2. Go to RECEIVE and create a New Address: **MN1**
3. Send **1000** NDB to **MN1**. You need to send all 1000 coins in one single transaction.
4. Wait for 15 confirmations.
5. Go to **Help -> "Debug Window - Console"**
6. Type the following command: **masternode outputs**
7. Go to  **Tools -> "Open Masternode Configuration File"**
8. Add the following entry:
```
Alias Address Privkey TxHash TxIndex
```
* Alias: **MN1**
* Address: **VPS_IP:PORT**
* Privkey: **Masternode Private Key**
* TxHash: **First value from Step 6**
* TxIndex:  **Second value from Step 6**
9. Save and close the file.
10. Go to **Masternode Tab**. If you tab is not shown, please enable it from: **Settings - Options - Wallet - Show Masternodes Tab**
11. Click **Update status** to see your node. If it is not shown, close the wallet and start it again. Make sure the wallet is unlocked.
12. Select your MN and click **Start Alias** to start it.
13. Alternatively, open **Debug Console** and type:
```
startmasternode alias MN1
```
14. Login to your VPS and check your masternode status by running the following command to confirm your MN is running:
```
nodebase-cli masternode status
```
***

## Usage:
```
nodebase-cli masternode status #To check your MN status
nodebase-cli getinfo #To get general info such as nodebase version and current block numnber
nodebase-cli mnsync status #To check if your MN is synced.
```
Also, if you want to check/start/stop **nodebase**, run one of the following commands as **root**:

```
systemctl status nodebase #To check if nodebase service is running
systemctl start nodebase #To start nodebase service
systemctl stop nodebase #To stop nodebase service
systemctl is-enabled nodebase #To check if nodebase service is enabled on boot
```
***

## Source
Based on:
https://github.com/zoldur/Masternode-setup-guide/blob/master/README.md