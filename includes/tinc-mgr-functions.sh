# Test sufficient number of args are sent
req_args() {
  
  local req_args=$1
  local supplied_args=$2
  
  [ ${supplied_args} -ne $req_args ] && return 1 || return 0
}

# Checks that required dependencies are available
check_dependencies() {
  
  for dep in "${dependencies[@]}" ; do
    if ! which "${dep}" >/dev/null 2>&1 ; then
      abrt "Dependency ${t_bold}${dep}${t_normal} is required before using "
    fi
  done
}

# Sets up tinc directories and files
new_setup() {
  
  [ ! -d "${config_dir}" ] && mkdir "${config_dir}"
  [ ! -f "${client_list_file}" ] && touch "${client_list_file}"
  [ ! -f "${connect_to_nodes}" ] && touch "${connect_to_nodes}"
  [ ! -f "${address_table}" ] && generate_address_table
  [ ! -d "${public_key_dir}" ] && mkdir "${public_key_dir}"
  [ ! -d "${local_config_dir}" ] && mkdir "${local_config_dir}"
  [ ! -d "${remote_config_dir}" ] && mkdir "${remote_config_dir}"
}

# Verify that our main config is OK
verify_config() {
  
  # Basic network verification. Mostly assumes the user knows what they're doing.
  local network_start_oct1="$( echo "${network_start}" | cut -d. -f1 )"
  local network_start_oct2="$( echo "${network_start}" | cut -d. -f2 )"
  local network_start_oct3="$( echo "${network_start}" | cut -d. -f3 )"
  local network_start_oct4="$( echo "${network_start}" | cut -d. -f4 )"
  
  local network_end_oct1="$( echo "${network_end}" | cut -d. -f1 )"
  local network_end_oct2="$( echo "${network_end}" | cut -d. -f2 )"
  local network_end_oct3="$( echo "${network_end}" | cut -d. -f3 )"
  local network_end_oct4="$( echo "${network_end}" | cut -d. -f4 )"
  
  # Test if start and end subnets are in the same subnet
  if { [ ${network_start_oct1} -ne ${network_end_oct1} ] || [ ${network_start_oct2} -ne ${network_end_oct2} ] || [ ${network_start_oct3} -ne ${network_end_oct3} ]; }; then
    abrt "Start and end range must be within the same subnet!"
  fi
  
  # Test that start and end networks are not starting with 0 (network address) or 254 (broadcast address)
  if { [ ${network_start_oct4} -eq 0 ] || [ ${network_start_oct4} -eq 254 ] || [ ${network_end_oct4} -eq 0 ] || [ ${network_start_oct4} -eq 254 ]; }; then
    abrt "Network start and end boundaries should not be 0 or 254."
  fi 
  
  # We only support IPv4 for now. Check that this isn't set to anything else.
  if [ "${tinc_protocol}" != "ipv4" ]; then
    abrt "Only ipv4 protocol is supported. You have set: ${protocol}."
  fi

  echo
}

# Generates an address table from network_start and network_end in the tinc-mgr.conf file
generate_address_table() {

  echo "Generating address table..."
  [ -f "${address_table}" ] && abrt "Address table already exists."
  
  touch "${address_table}"
  
  local network_start_oct1="$( echo "${network_start}" | cut -d. -f1 )"
  local network_start_oct2="$( echo "${network_start}" | cut -d. -f2 )"
  local network_start_oct3="$( echo "${network_start}" | cut -d. -f3 )"
  local network_start_oct4="$( echo "${network_start}" | cut -d. -f4 )"
  
  local network_end_oct4="$( echo "${network_end}" | cut -d. -f4 )"
    
  echo '# DO NOT MODIFY THIS FILE DIRECTLY. IT WILL BE OVERWRITTEN!' > "${address_table}"
  
  for i in $( seq ${network_start_oct4} ${network_end_oct4} ); do
    echo "${network_start_oct1}.${network_start_oct2}.${network_start_oct3}.$i," >> "${address_table}"
  done
  
  echo
}
  
# Assigns the next available VPN IP to a client
assign_vpn_ip() {

  local address_array=( $( cat "${address_table}" ) )
  next_free_address=""
  
  for address in "${address_array[@]}" ; do
    _is_free="$( echo "${address}" | cut -d, -f2 2>/dev/null )"
    if { [ $? -ne 0 ] || [ -z "${_is_free}" ]; }; then
      next_free_address="$( echo "${address}" | sed 's/,//g' )"
      break
    fi 
   done
  
  [ -z "${next_free_address}" ] && return 1
  echo "${next_free_address}"
}

# Adds a client, assigns IP, generates a local and remote config
add_client() {

  if req_args 2 $# ; then
    local shortname="$1"
    local address="$2"
    

    # Test that client doesn't already exist.'
    local clientlist="$( cut -d, -f1 "${client_list_file}"  )"
    local does_client_exist="$( echo "${clientlist}"|  grep "^${shortname}$" )"
    [ -n "${does_client_exist}" ] && abrt "Client with shortname ${shortname} already exists"
    
    local iplist="$( cut -d, -f2 "${client_list_file}"  )"
    local does_ip_exist="$( echo "${iplist}" | grep "^${address}$" )"
    [ -n "${does_ip_exist}" ] && abrt "Client with address ${address} already exists."

    local this_client_local_config_dir="${local_config_dir}/${shortname}"
    [ -d "${this_client_local_config_dir}" ] && abrt "Client shortname directory ${this_client_local_config_dir} already exists"


    msg "Generating local config for ${shortname} with address ${address}..."
    mkdir "${this_client_local_config_dir}" || abrt "Unable to create client directory, ${this_client_local_config_dir}"
    touch "${this_client_local_config_dir}"/{ip,connectto,vpn_ip,sync}
    echo "${address}" > "${this_client_local_config_dir}/ip"
    echo "1" > "${this_client_local_config_dir}/connectto"
    
    echo "${shortname},${address}" >> "${client_list_file}"
    echo
    
    local vpn_ip="$( assign_vpn_ip )"
    [ -z "${vpn_ip}" ] && abrt "Unable to generate Tinc config. No more free IPs in address table"
    
    echo "${vpn_ip}" > "${this_client_local_config_dir}/vpn_ip"
    sed -i "s/"${vpn_ip},"/${vpn_ip},${shortname}/g" "${address_table}"  2>/dev/null || sed -i '' "s/"${vpn_ip},"/${vpn_ip},${shortname}/g" "${address_table}" || abrt "Unable to write to address table"
    
    msg "Assigned VPN IP ${vpn_ip} to ${shortname}..."
    
    local this_client_remote_config_dir="${remote_config_dir}/${shortname}/${tinc_network_name}"
    msg ""
    msg "Generating remote (Tinc) config for ${shortname}..."
    mkdir -p "${this_client_remote_config_dir}" || abrt "Unable to create remote config directory"
    touch "${this_client_remote_config_dir}/tinc.conf"
    touch "${this_client_remote_config_dir}/tinc-up"
    touch "${this_client_remote_config_dir}/tinc-down"
    mkdir "${this_client_remote_config_dir}/hosts"
    touch "${this_client_remote_config_dir}/hosts/${shortname}"
    touch "${this_client_remote_config_dir}/rsa_key.priv"
    
    chmod +x "${this_client_remote_config_dir}/tinc-up" "${this_client_remote_config_dir}/tinc-down"
    
    echo "Name = ${shortname}
AddressFamily = ${tinc_protocol}
Interface = ${tinc_interface}" > "${this_client_remote_config_dir}/tinc.conf"

  build_list_of_ct_nodes
  local list_of_ct_nodes=( $( grep -v ^# "${connect_to_nodes}" ) )
  if [ "${#list_of_ct_nodes[@]}" -gt 0 ]; then
    for ct_node in "${list_of_ct_nodes[@]}" ; do
      echo "ConnectTo = ${ct_node}" >> "${this_client_remote_config_dir}/tinc.conf"
    done
  fi

  openssl genrsa -out "${this_client_remote_config_dir}/rsa_key.priv" 4096 >/dev/null 2>&1 || abrt "Unable to generate private key for ${shortname}"
  
  echo "Address = ${address}" > "${this_client_remote_config_dir}/hosts/${shortname}"
  echo "Subnet = ${vpn_ip}/32" >> "${this_client_remote_config_dir}/hosts/${shortname}"
  echo "Port = ${tinc_port}" >> "${this_client_remote_config_dir}/hosts/${shortname}"
  echo >> "${this_client_remote_config_dir}/hosts/${shortname}"
  
  openssl rsa -in "${this_client_remote_config_dir}/rsa_key.priv" -pubout >> "${this_client_remote_config_dir}/hosts/${shortname}" 2>/dev/null
  cp -f "${this_client_remote_config_dir}/hosts/${shortname}" "${public_key_dir}"

  echo "#!/bin/sh
ifconfig \$INTERFACE ${vpn_ip} netmask 255.255.255.0" >> "${this_client_remote_config_dir}/tinc-up"

  echo "#!/bin/sh
ifconfig \$INTERFACE down" >> "${this_client_remote_config_dir}/tinc-down"
        
    msg "${t_yellow}WARNING: ${t_normal}Please sync configurations after adding or deleting clients."
    
  else
    msg ""
    msg "${t_red}Invalid arguments for add operation!${t_normal}"
    usage
  fi
}

# Deletes a VPN client
delete_client() {

  if req_args 1 $# ; then
    local shortname="$1"
    [ ! -d "${local_config_dir}/${shortname}" ] && abrt "Client ${shortname} not found"

    echo -n "Are you sure you want to remove client ${shortname}? <y/n> "
    read del_answer < /dev/tty
    del_answer="$( echo "${del_answer}" | head -c 1 | tr '[A-Z]' '[a-z]' )"
    [ "${del_answer}" != "y" ] && msg "Deletion of client ${shortname} cancelled." 
    
    msg "Removing client ${shortname}..."
   
    # Force unset mode becase we're dealing with rm operations
    set -u
    local this_client_local_config_dir="${local_config_dir}/${shortname}"
    local this_client_remote_config_dir="${remote_config_dir}/${shortname}"
        
    local is_connectto_node=$( cat "${this_client_local_config_dir}/connectto" )
    [ ${is_connectto_node} -eq 0 ] && abrt "Client is a a ConnectTo node. Please demote to a standard client first (see: help)"
    
    local this_client_vpn_ip="$( cat "${this_client_local_config_dir}/vpn_ip" )"
    
    sed -i "s/^${this_client_vpn_ip},.*/${this_client_vpn_ip},/g" "${address_table}" 2>/dev/null || sed -i '' "s/^${this_client_vpn_ip},.*/${this_client_vpn_ip},/g" "${address_table}"

    sed -i "s/^${shortname},.*//g" "${client_list_file}" 2>/dev/null || sed -i '' "s/^${shortname},.*//g" "${client_list_file}"
    
    sed -i '/^$/d' "${client_list_file}" 2>/dev/null || sed -i '' '/^$/d' "${client_list_file}"
    
    rm -rf "${this_client_local_config_dir}"
    rm -rf "${this_client_remote_config_dir}"
    
    rm -f "${public_key_dir}/${shortname}"
    
    
     msg ""
     msg "${t_yellow}WARNING: ${t_normal}Please sync configurations after adding or deleting clients."
  else
     msg "${t_red}Invalid arguments for delete operation!${t_normal}" && usage && exit 1
  fi
  :
}

# Sync configurations to all clients
sync_clients(){

  sync_errors=0

  # Test that we have ConnectTo nodes defined.
  local list_of_ct_nodes=( $( grep -v ^# "${connect_to_nodes}" ) )
  [ ! ${#list_of_ct_nodes[@]} -gt 0 ] && abrt "Please specify at least one 'ConnectTo' node - see help for more info"

  msg "Syncing configurations" >&2
  
  local sync_clients=( $( ls "${local_config_dir}" ) )
  
  for client in "${sync_clients[@]}" ; do
    local this_client_local_config_dir="${local_config_dir}/${client}"
    local this_client_remote_config_dir="${remote_config_dir}/${client}"
    local this_client_ip="$( cat "${this_client_local_config_dir}/ip" )"
        
    msg "Syncing config to client ${client}..."
    
    if ! nc -w "${sync_timeout}" -z "${this_client_ip}" 22 >/dev/null 2>&1 ; then
      msg "${t_red}ERROR: ${t_normal}Unable to connect to ${client} on address ${this_client_ip}. Skipping."
      ((sync_errors++))
      continue
    fi
    
    if ! ssh root@${this_client_ip} "[ -d "${tinc_config_dir}" ]" >/dev/null 2>&1 ; then
       msg "${t_red}ERROR: ${t_normal}Tinc config dir ${tinc_config_dir} does not exist on client ${client}. Skipping."
       ((sync_errors++))
       continue
    fi
    
    if ! ssh root@${this_client_ip} "[ -w "${tinc_config_dir}" ]" >/dev/null 2>&1 ; then
       msg "${t_red}ERROR: ${t_normal}Tinc config dir ${tinc_config_dir} is not writeable on client ${client}. Skipping."
       ((sync_errors++))
       continue
    fi
    
    
    if rsync -az -e ssh --delete "${this_client_remote_config_dir}/" root@${this_client_ip}:${tinc_config_dir} >/dev/null 2>&1 ; then
      if rsync -az -e ssh --delete "${public_key_dir}/" root@${this_client_ip}:${tinc_config_dir}/${tinc_network_name}/hosts >/dev/null 2>&1 ; then
        msg "${t_bold}${client}: ${t_normal}${t_green}OK${t_normal}"
        local date_now="$( date +%s )"
        [ ! -f "${this_client_local_config_dir}/sync" ] && touch "${this_client_local_config_dir}/sync"
        echo "${date_now}" > "${this_client_local_config_dir}/sync"
      fi  
      
    else
      msg "${t_strong}${client}: ${t_normal}${t_red}ERROR${t_normal}"
      ((sync_errors++))
    fi
    
  done
  
  [ ${sync_errors} -gt 0 ] && msg && msg "${t_red}IMPORTANT: ${t_normal}There were some errors reported. Configs for failed clients will be out of sync!"
  
}

# Builds a list of ConnectTo nodes.
build_list_of_ct_nodes() {
  
  local client_configs=( $( ls "${local_config_dir}" ) )
  local total_ct_nodes=0

  echo "# DO NOT MODIFY THIS FILE DIRECTLY. IT WILL BE OVERWRITTEN!" > "${connect_to_nodes}"  
  for client in "${client_configs[@]}" ; do
    local this_client_local_config_dir="${local_config_dir}/${client}"
    if grep 0 "${this_client_local_config_dir}/connectto" >/dev/null 2>&1 ; then
      echo "${client}" >> "${connect_to_nodes}"      
      ((total_ct_nodes++))
    fi
  done
 
  msg ""
  [ ${total_ct_nodes} -eq 0 ] && msg "${t_yellow}WARNING: ${t_normal}No ConnectTo nodes found. See help command for specifying a ConnectTo node."
      
}

# Updates client ConnectTo parameters
update_client_ct_nodes() {
  
  local client_configs=( $( ls "${remote_config_dir}" ) )
  
  for client in "${client_configs[@]}" ; do
    local this_client_remote_config_dir="${remote_config_dir}/${client}/${tinc_network_name}"
    
    # Remove last ConnectTo nodes list
    sed -i "s/^ConnectTo.*//g" "${this_client_remote_config_dir}/tinc.conf" 2>/dev/null || sed -i '' "s/^ConnectTo.*//g" "${this_client_remote_config_dir}/tinc.conf"
    sed -i '/^$/d' "${this_client_remote_config_dir}/tinc.conf" 2>/dev/null || sed -i '' '/^$/d' "${this_client_remote_config_dir}/tinc.conf"
    
    local list_of_ct_nodes=( $( grep -v ^# "${connect_to_nodes}" ) )
    
    if [ ${#list_of_ct_nodes[@]} -ne 0 ]; then
    # Adds latest list to client configs
      for ct_node in "${list_of_ct_nodes[@]}" ; do
        echo "ConnectTo = ${ct_node}" >> "${this_client_remote_config_dir}/tinc.conf"
      done
    fi

  done
}

# Sets a client as a 'ConnectTo' node
set_ct_node() {
  local shortname="$1"
  [ ! -d "${local_config_dir}/${shortname}" ] && abrt "Unable to find client named ${shortname} to promote to 'ConnectTo'' node"
  
  msg "Setting ${shortname} as a 'ConnectTo' node..."
  echo "0" > "${local_config_dir}/${shortname}/connectto"
  
  msg "Refreshing list of ConnectTo nodes..."
  build_list_of_ct_nodes
  
  update_client_ct_nodes

  msg "${t_yellow}WARNING: ${t_normal}ConnectTo nodes have changed - sync required"
}

# Sets a client back to a standard config
unset_ct_node() {
  local shortname="$1"
  [ ! -d "${local_config_dir}/${shortname}" ] && abrt "Unable to find client named ${shortname} to promote to 'ConnectTo'' node"
  
  msg "Setting ${shortname} as a standard client..."
  echo "1" > "${local_config_dir}/${shortname}/connectto"
  
  msg "Refreshing list of ConnectTo nodes..."
  build_list_of_ct_nodes
  
  update_client_ct_nodes
  
  msg "${t_yellow}WARNING: ${t_normal}ConnectTo nodes have changed - sync required"
}

# Lists VPN clients
list_clients() {

  local client_count=$( ls "${local_config_dir}" | wc -l )
  local list_clients=( $( ls "${local_config_dir}" ) )
  [ "${client_count}" -eq 0 ] && abrt "No VPN clients found"
  
 client_data="$( for client in "${list_clients[@]}" ; do
    local this_client_local_config_dir="${local_config_dir}/${client}"
    local this_client_ip="$( cat "${this_client_local_config_dir}/ip" )"
    local this_client_vpn_ip="$( cat "${this_client_local_config_dir}/vpn_ip" )"
    local this_client_connectto="$( cat "${this_client_local_config_dir}/connectto" )"
    local this_client_last_sync="$( cat "${this_client_local_config_dir}/sync" 2>/dev/null )" ; [ -z "${this_client_last_sync}" ] && this_client_last_sync=0
    echo "${client} ${this_client_ip} ${this_client_connectto} ${this_client_vpn_ip} ${this_client_last_sync}" | column -t
  done )"
  
   echo "CLIENT IP CONNECTTO_NODE VPN_IP LAST_SYNC
   ${client_data}" | column -t
   
}

# Prints script usage
usage() {
  progname="$( basename $0 )"
  msg ""
  msg "${t_bold}Usage:${t_normal} ${progname} <options>"
  msg ""
  msg "${t_bold}OPTIONS${t_normal}"
  msg " add                 Adds a new client"
  msg " delete              Deletes a client"
  msg " set_connectto_node  Promotes a client to a 'ConnectTo' host [Example: ${progname} connectto_node <existing shortname>]"
  msg " set_std_client      Demotes a client back to a standard, non-ConnectTo client"
  msg " sync                Syncs Tinc config to clients"
  msg " list                Lists VPN client shortname, IP address and Tinc address"
  msg " help                Prints this help message"
  msg ""
  msg "${t_bold}EXAMPLES${t_normal}"
  msg " * Add a client:"
  msg "   ${progname} add clientname ipaddress"
  msg
  msg " * Delete a client:"
  msg "   ${progname} delete clientname"
  msg
  msg " * Make a client a ConnectTo node:"
  msg "   ${progname} set_connectto_node clientname"
  msg
  msg " * Demotes a client back to a standard (non-ConnectTo) node:"
  msg "   ${progname} set_std_client clientname"
  msg
  msg "Note: only one option must be used at a time."
}
