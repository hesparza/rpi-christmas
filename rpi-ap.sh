#!/bin/bash
#
# This script configures a raspberry pi as a wifi hotspot to establish a wifi LAN
#

#Global variables
_action=""
_dhcp_client_config_file="/etc/dhcpcd.conf"
_dhcp_server_config_file="/etc/dnsmasq.conf"
_access_point_config_file="/etc/hostapd/hostapd.conf"
_default_access_point_config_file="/etc/default/hostapd"
_sysctl_config_file="/etc/sysctl.conf"
_backup_file_suffix=".before-hotspot-setup.bu"
_broker_static_ip_address="192.168.1.1/24"
_dhcp_range="192.168.1.2,192.168.1.255"
_network_mask="255.255.255.0"

#Installs a dependency
#$1 - dependency name
function install_dependency() {
    apt install -y "$1"
    return $?
}

#Verifies whether dependencies are installed and installs them in case they are not
function verify_dependencies() {
  _dependencies="hostapd dnsmasq iptables-persistent"
  for _dependency_name in $_dependencies; do
    which "$_dependency_name" > /dev/null
    if [ $? -ne 0 ];then
        install_dependency "$_dependency_name"
        _return_code=$?
        [ $_return_code -ne 0 ] && echo "Unable to install dependency: $_dependency_name" && return $_return_code
    fi
  done
  return 0
}

#Verifies that the platform where the script is being executed is raspbian
function verify_platform() {
  _return_code=0
  _platform=$(cat /etc/*-release | grep '^ID=' | cut -d '=' -f 2)
  if [ "${_platform,,}" != "raspbian" ];then
    _return_code=1
  fi
  return $_return_code
}

#tells whether a backup file already exists
#$1 - absolute path to file
function backup_exists() {
  #if backup file exists, do not perform the change
  ls "$1$_backup_file_suffix" > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    return 0
  fi
  return 1
}

#Reverts file from its backup
#$1 - absolute path of the file
function revert_file() {
  mv "${1}$_backup_file_suffix" "$1" 2>/dev/null
  return $?
}

#Creates a backup up of a file
#$1 - absolute path of the file
function backup_file() {
  cp "$1" "${1}$_backup_file_suffix" 2>/dev/null
  return $?
}

#Appends content to a file
#$1 - string to append
#$2 - absolute path of file
function append_to_file() {
  echo -e "$1" >> $2
  return $?
}

#configures a static ip address
function configure_static_ip() {
  echo "Configuring static ip address as: $_broker_static_ip_address"

  #if backup file exists, do not perform the change
  if backup_exists $_dhcp_client_config_file; then
    echo "backup of file $_dhcp_client_config_file found, skipping changes"
    return 1
  fi

  #backup dhcp client config file
  backup_file "$_dhcp_client_config_file" || { echo "Error: unable to backup file $_dhcp_client_config_file" && return 2; }

  #write changes in dhcp client config file
  append_to_file "interface wlan0\nstatic ip_address=$_broker_static_ip_address\nnohook wpa_supplicant" "$_dhcp_client_config_file" || { echo "Error: unable to append to file $_dhcp_client_config_file" && return 3; }

  return 0
}

#reverts configuration for static ip address
function revert_configure_static_ip() {
  echo "Reverting static ip configuration address as: $_broker_static_ip_address"

  #if backup file does not exists, cannot perform revert
  if ! backup_exists $_dhcp_client_config_file; then
    echo "backup of file $_dhcp_client_config_file not found, unable to revert configuration"
    return 1
  fi

  #backup dhcp client config file
  revert_file "$_dhcp_client_config_file" || { echo "Error: unable to revert file $_dhcp_client_config_file" && return 2; }

  return 0
}

#configures DHCP server (dnsmasq)
function configure_dhcp_server() {
  echo "Configuring dhcp server.. "

  #if backup file exists, do not perform the change
  if backup_exists $_dhcp_server_config_file; then
    echo "backup of file $_dhcp_server_config_file found, skipping changes"
    return 1
  fi

  #backup dhcp server file
  backup_file "$_dhcp_server_config_file" || { echo "Error: unable to backup file $_dhcp_server_config_file" && return 2; }


  #write changes in dhcp file
  append_to_file "interface=wlan0\ndhcp-range=$_dhcp_range,$_network_mask,24h" "$_dhcp_server_config_file" || { echo "Error: unable to append to file $_dhcp_client_config_file" && return 3; }

  return 0
}

#configures DHCP server (dnsmasq)
function revert_configure_dhcp_server() {
  echo "Reverting dhcp server configuration.. "

  #if backup file does not exists, cannot perform revert
  if ! backup_exists $_dhcp_server_config_file; then
    echo "backup of file $_dhcp_server_config_file not found, unable to revert configuration"
    return 1
  fi

  #backup dhcp server file
  revert_file "$_dhcp_server_config_file" || { echo "Error: unable to revert file $_dhcp_server_config_file" && return 2; }

  return 0
}

#configure access point
function configure_access_point() {
  _file_content="interface=wlan0
driver=nl80211
ssid=scb-wifi1
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=password
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP"

  echo "Configuring access point.."

  #if backup file exists, do not perform the change
  if backup_exists $_access_point_config_file; then
    echo "backup of file $_access_point_config_file found, skipping changes"
    return 1
  fi

  backup_file $_access_point_config_file
  append_to_file "$_file_content" $_access_point_config_file || { echo "Error: unable to append to file $_access_point_config_file" && return 1; }

  return 0
}

#reverts access point configuration
function revert_configure_access_point() {
  echo "Reverting access point configuration.."

  #if backup file exists, do not perform the change
  if ! backup_exists $_access_point_config_file; then
    echo "backup of file $_access_point_config_file not found, unable to revert configuration"
    return 1
  fi

  revert_file $_access_point_config_file

  return 0
}

#configures access point to start at boot time
function configure_access_point_automatic_start() {
  echo "Configuring access point automatic start.."
  #if backup file exists, do not perform the change
  if backup_exists $_default_access_point_config_file; then
    echo "backup of file $_default_access_point_config_file found, skipping changes"
    return 1
  fi

  #start access point on boot
  backup_file $_default_access_point_config_file
  append_to_file "DAEMON_CONF=\"$_access_point_config_file\"" $_default_access_point_config_file || { echo "Error: unable to append to file $_default_access_point_config_file" && return 2; }

  return 0;
}

#reverts access point configuration to start at boot time
function revert_configure_access_point_automatic_start() {
  #if backup file exists, do not perform the change
  if ! backup_exists $_default_access_point_config_file; then
    echo "backup of file $_default_access_point_config_file not found, unable to revert configuration"
    return 1
  fi

  #start access point on boot
  revert_file $_default_access_point_config_file

  return 0;
}

#configure ip forwarding
function configure_ip_forwarding() {
  echo "Configuring ip forwarding.."

  #if backup file exists, do not perform the change
  if backup_exists $_sysctl_config_file; then
    echo "backup of file $_sysctl_config_file found, skipping changes"
    return 1
  fi
  backup_file $_sysctl_config_file
  append_to_file "net.ipv4.ip_forward=1" $_sysctl_config_file || { echo "Error: unable to append to file $_sysctl_config_file" && return 1; }
}

#reverts ip forwarding configuration
function revert_configure_ip_forwarding() {
  echo "Reverting ip forwarding configuration.. "

  #if backup file exists, do not perform the change
  if ! backup_exists $_sysctl_config_file; then
    echo "backup of file $_sysctl_config_file not found, unable to revert configuration"
    return 1
  fi
  revert_file $_sysctl_config_file
}

#configure network address translation (NAT)
function configure_nat() {
  echo "Configuring NAT.."
  iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE || { echo "Error: unable to configure ip tables" && return 1; }
  iptables-save | tee /etc/iptables/rules.v4 || { echo "Error: unable to configure ip tables" && return 2; }
  return 0
}

#reverts network address translation (NAT) configuration
function revert_configure_nat() {
  echo "Reverting NAT configuration.."
  iptables -t nat -F && iptables -t nat -X || { echo "Error: unable to revert ip tables configuration" && return 1; }
  iptables-save | tee /etc/iptables/rules.v4 > /dev/null || { echo "Error: unable to revert ip tables configuration" && return 2; }
  return 0
}

#start services and enable them on boot
function enable_services() {
  echo "Enabling services.."
  systemctl unmask hostapd && systemctl start hostapd || { echo "Error: unable to start services" && return 1; }
  systemctl unmask dnsmasq && systemctl start dnsmasq || { echo "Error: unable to start services" && return 1; }
  systemctl enable hostapd && systemctl enable dnsmasq || { echo "Error: unable to setup services to start on boot" && return 2; }
  return 0
}

#stop services and disable them on boot
function revert_enable_services() {
  echo "Disabling services.."
  systemctl stop hostapd && systemctl stop dnsmasq || { echo "Error: unable to stop services" && return 1; }
  systemctl disable hostapd && systemctl disable dnsmasq || { echo "Error: unable to disable services to start on boot" && return 1; }
  return 0
}

#prompts user whether he wants to reboot the system
function prompt_reboot() {
  while true; do
    read -p "This configuration requires a reboot at the end of the process, are you ok rebooting [y/N]?" yn
    case $yn in
        [Yy]* ) return 0; break;;
        [Nn]* ) return 1; break;;
        * ) return 1;;
    esac
  done
}

#Sets up the device as an access point
function setup() {
  if ! prompt_reboot;then
    return 1;
  fi

  #verify platform
  verify_platform || { echo "Error: Not running on a raspberry pi" && return 1; }

  #make sure dependencies are installed, otherwise install them
  verify_dependencies
  _return_code=$?
  if [ $_return_code -ne 0 ];then
    echo "Error while attempting to install dependencies"
    return $_return_code
  fi

  #setup static ip address
  configure_static_ip || return 3

  #configure DHCP server
  configure_dhcp_server || return 4

  #configure access point (hostapd)
  configure_access_point || return 5
  configure_access_point_automatic_start || return 6

  #enable ip forwarding
  configure_ip_forwarding || return 7

  #configure Network Address Translation (NAT)
  configure_nat || return 8

  #enable services on boot
  enable_services || return 9

  return 0
}

#Reverts the device setup
function revert() {
  if ! prompt_reboot;then
    return 1;
  fi

  #setup static ip address
  revert_configure_static_ip || return 1

  #configure DHCP server
  revert_configure_dhcp_server || return 2

  #configure access point (hostapd)
  revert_configure_access_point || return 3
  revert_configure_access_point_automatic_start || return 4

  #enable ip forwarding
  revert_configure_ip_forwarding || return 5

  #revert Network Address Translation (NAT)
  revert_configure_nat || return 6

  #disable services
  revert_enable_services || return 7

  return 0;
}

#Prints the help guide
function print_help() {
  echo -e "This script sets up the Raspberry device as an access point\n
  Usage: $0 [arguments]\n
  Arguments:\n
  s | setup  - Install dependencies and perform configuration to setup the device as an access point.\n
  r | revert - Reverts the setup steps so that the device is no longer configured as an access point.\n
  -h | --help   - Prints this help guide"
}

#Request elevated privileges as the script needs them
function require_elevated_privileges() {
  # Check if the script is running as root
  if [[ $EUID -ne 0 ]]; then
      echo "This script requires root access. Please enter your password."
      # Prompt for the root password and execute the script with sudo
      sudo bash "$0" "$@"
      exit $?
  fi
  echo "Root access granted. This script is running with elevated privileges."
}

#Parses the parameters received by the script
#$1 - all parameters
function parse_arguments() {
  while [ "$1" != "" ]; do
    case "$1" in
       "s" | "setup" )
          _action="setup"
       ;;
       "r" | "revert")
          _action="revert"
       ;;
       "-h" | "--help")
          _action="help"
       ;;
       *)
          echo "Error: Expecting at least one argument"
          error="true" && break
        ;;
    esac
    shift;
  done;

  [ -n "$error" ] && return 1;

  return 0;
}

function main() {
  parse_arguments $@
  require_elevated_privileges $@
  case "$_action" in
    "setup" ) setup && reboot;;
    "revert") revert && reboot;;
    *) print_help ;;
  esac

  return $?
}

main $@
exit $?
