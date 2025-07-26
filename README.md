# NordVPN-OpenWRT
Watchdog script to setup and use NordVPN in router with OpenWRT firmware.

###
### <ins>What is this?</ins>

This script is meant to run when the router boots.

It creates a VPN wireguard connection to NordVPN servers (if not yet created) and test connectivity every minute.

If VPN connectivity fails, it will try to connect to a different server or, if not possible, restarts network services.

For now the script can't select servers by country/city. It just gets 10 servers recommended by NordVPN API, usually they are the closest and less busy servers and it has worked very well for me.

###

### <ins>Before you start</ins>

- **BACKUP YOUR CURRENT CONFIGURATION!** Use a browser to log in to your router -> "System" -> "Backup / Flash Firmware" and click on "Generate archive". Mistakes happen but can easily be fixed just restoring a backup.

- Make sure your router has the needed packages to connect to a VPN using wireguard. Log in to the router with a browser -> "System" -> "Software": click in "Update lists..."; wait for the update to finish; write `wireguard` in the "Filter:" box; click the button "Install" on the right of the listed packages.

<p align="center" /><img width="1194" height="708" alt="wireguard" src="https://github.com/user-attachments/assets/b5d9e128-9163-47d5-8500-c4b9236982a8" /></p>


- You need to know how to log in to the router using SSH. You can use [putty](https://www.putty.org) or use ssh command from Linux or Windows Subsystem for Linux.

- You need to edit the script, so you need to know how to use `vi`, or maybe `nano`. Another way would be to edit the script in your PC but then you need to know how to upload it to the router (using scp, for example) and how to avoid the CR/LF problem when editing text files on Windows (using Notepad++, for example).

- The script uses the following commands: `awk`; `curl`; `grep`; `ifup`; `ip`; `jq`; `ping`; `service`; `uci`. Check that the commands are available by running them in a SSH terminal.

  + If some command is missing, try to install them by logging in to the router with a browser -> "System" -> "Software": click in "Update lists..."; wait for the update to finish; write the command name in the "Filter:" box; click the button "Install" on the right of the listed package.
 
  + Keep in mind that if you upgrade the firmware, you need to reinstall the packages (there are ways to get firmware with the desired packages included, for example: https://firmware-selector.openwrt.org -> select your router -> click on "Customize installed packages and/or first boot script").

- And finally, go to https://my.nordaccount.com/dashboard/nordvpn/access-tokens/ -> "Generate new token" and get a new one. Should be a string with 64 random numbers and letters.

###

### <ins>Install and setup</ins>

1. Log in to the router via SSH. 

2. Download the script running this command: `mkdir -p /opt && curl -sL -o /opt/nordvpn_watchdog.sh https://github.com/cjom/NordVPN-OpenWRT/raw/refs/heads/main/nordvpn_watchdog.sh && chmod 755 /opt/nordvpn_watchdog.sh`

3. To survive future firmware upgrades, add the script to the list in `/etc/sysupgrade.conf` with the command: `echo "/opt/nordvpn_watchdog.sh" >>/etc/sysupgrade.conf`

   - This can also be done by logging in to the router with some browser -> "System" -> "Backup / Flash Firmware" -> "Configuration" tab, and paste there the line `/opt/nordvpn_watchdog.sh` (or just `/opt` for the entire folder).

4. Now you need setup the access token:

   - Check if the router can use the access token with the command `curl --help`. There should be a line mentioning the `-u` option. If this option is supported, you can edit the script `/opt/nordvpn_watchdog.sh` and paste the token inside the quotes in `NORDVPN_TOKEN=''`.

   - If there is no `-u` option, you need to use the computer to run `curl` and get the "basic" authorization token. You can use Linux or Windows Subsystem for Linux.

     + Run the command `curl -vu token:REPLACE_THIS_WITH_YOUR_TOKEN https://api.nordvpn.com/v1/users/services/credentials` and look for the long string next to `authorization: Basic`. It's a 96 characters string ending with "==". Don't forget to replace `REPLACE_THIS_WITH_YOUR_TOKEN` with your actual token.

     + Edit the script `/opt/nordvpn_watchdog.sh` and paste this "basic" token inside the quotes in `NORDVPN_BASIC_TOKEN=''` (including the two ending equal characters).

5. Make the script run when the router boots, with the command: `echo "/opt/nordvpn_watchdog.sh &" >>/etc/rc.local`

   - Some routers have `exit 0` in the end of the file `/etc/rc.local`. Make sure that `/opt/nordvpn_watchdog.sh &` is before that, or just delete the `exit 0` line.

   - This can also be done by logging in to the router with some browser -> "System" -> "Startup" -> "Local Startup" tab, and paste there the command `/opt/nordvpn_watchdog.sh &`.

6. And finally, before rebooting, you might want to run the script from the SSH terminal with the command `/opt/nordvpn_watchdog.sh &` and check the output in the "System Log" of the menu "Status" (in the browser, after you log in to the router). All script messages start with '***' so it's easy to use the filter in the top of the page.

<p align="center" /><img width="550" height="277" alt="normal_boot" src="https://github.com/user-attachments/assets/a8c517c5-9b8c-48be-a508-14c614dcaef7" /></p>


###

### <ins>Final notes</ins>

- To avoid leaks, it is recommended that IPv6 is disabled in all interfaces.

- You migh want to use [PBR](https://docs.openwrt.melmac.ca/pbr) to configure what sites or devices you want to connect through the VPN. But... (read next point)

- After the VPN is connected, **EVERY* IPv4 connection is set to go through it. That means that if you set strict rules for connections to not go through wan, you might have no access to the internet until the VPN is connected, particularly if you have disabled IPv6 AND you use DNS servers other than a local IP (if you have your OpenWRT router connected to an ISP router and use his IP as DNS server, that's OK; if you use Google's DNS IP, because it would go through the VPN but the VPN is not connected, you can't connect).
