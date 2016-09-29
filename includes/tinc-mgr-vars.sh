# CONSTANTS
readonly project_name="tinc-mgr"
readonly project_version="0.1"

readonly config_dir="${home_dir}/configs"
readonly local_config_dir="${config_dir}/local"
readonly remote_config_dir="${config_dir}/remote"
readonly public_key_dir="${config_dir}/public_keys"

readonly client_list_file="${config_dir}/clients.txt"
readonly connect_to_nodes="${config_dir}/connect_to_hosts.txt"
readonly address_table="${config_dir}/address-table.txt"

readonly sync_timeout=5

readonly dependencies=( "ncat" "rsync" "tincd" )