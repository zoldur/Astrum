# AstrumCash
Shell script to install a [AatrumCash Masternode](https://astrum.cash) on a Linux server running Ubuntu 16.04. Use it on your own risk.  

***
## Installation:  

wget -q https://raw.githubusercontent.com/zoldur/Astrum/master/astrum_install.sh  
bash astrum_install.sh
***

## Desktop wallet setup  

After the MN is up and running, you need to configure the desktop wallet accordingly. Here are the steps:  
1. Open the Astrum Desktop Wallet.  
2. Go to RECEIVE and create a New Address: **MN1**  
3. Send **3000** ASTR to **MN1**.  
4. Wait for 20 confirmations.  
5. Go to **Help -> "Debug window - Console"**  
6. Type the following command: **masternode outputs**  
7. Go to **Masternodes** tab  
8. Click **Create** and fill the details:  
* Alias: **MN1**  
* Address: **VPS_IP:PORT**  
* Privkey: **Masternode Private Key**  
* TxHash: **First value from Step 6**  
* Output index:  **Second value from Step 6**  
* Reward address: leave blank  
* Reward %: leave blank  
9. Click **OK** to add the masternode  
10. Click **Start All**  

***

## Usage:  

For security reasons **Astrum** is installed under **astrum** user, hence you need to **su - astrum** before checking:    

```
su - astrum
Astrumd masternode status
Astrumd getinfo
```  
Also, if you want to check/start/stop **Astrumd** , run one of the following commands as **root**:
```
systemctl status Astrumd #To check the service is running  
systemctl start Astrumd #To start mambocoind service  
systemctl stop Astrumd #To stop cropcpoind service  
```


***

  
Any donation is highly appreciated  

**ASTR**: AaionTTRj6j7gm8TT9UBj4xfVks2Vrorvj
**BTC**: 1BzeQ12m4zYaQKqysGNVbQv1taN7qgS8gY  
**ETH**: 0x39d10fe57611c564abc255ffd7e984dc97e9bd6d  
