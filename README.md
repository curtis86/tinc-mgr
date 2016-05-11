# TINC-MGR

## A. Summary

tinc-mgr makes managing Tinc VPN clients and configurations easier.

It can...
 * Generate profiles and assign them VPN IP addresses automatically
 * Distribute/sync configurations to clients
 * Distribute/sync client public keys to all clients
 * Promote/demote clients to/from `ConnectoTo` nodes
 * Present a list of Tinc clients that have been configured
 * Delete clients

tinc-mgr pushes to clients over SSH (see: Assumptions)

## B. Dependencies

The following binaries are required:

 * tincd
 * rsync
 * nc

The above are easily installed on most BSD/Linux distributions (eg: yum install nc, apt-get install nc, brew install nc, etc)

## C. Supported Systems

Tested on CentOS 6.7 and OS X. Should work on any system with BASH 4 or later.

### Installation

1. Clone this repo to your preferred directory (eg: `/opt/tinc-mgr`)

  `cd /opt && git clone https://github.com/curtis86/tinc-mgr`


### Usage

Before running `tinc-mgr` see `tinc-mgr.conf` to define the VPN name, IP pool, etc.

```
Usage: tinc-mgr <options>

OPTIONS
 add                 Adds a new client
 delete              Deletes a client
 set_connectto_node  Promotes a client to a 'ConnectTo' node
 set_std_client      Demotes a client back to a standard, non-ConnectTo client
 sync                Syncs Tinc config to clients
 list                Lists VPN client shortname, IP address and Tinc address
 help                Prints this help message

Note: only one option must be used at a time.
```

### Examples

* Add a client:
  `tinc-mgr add clientname ipaddress`

* Delete a client:
  `tinc-mgr delete clientname`

* Make a client a ConnectTo node:
  `tinc-mgr set_connectto_node clientname`

* Demotes a client back to a standard, non-ConnectTo node:
  `tinc-mgr set_std_client clientname`

## Assumptions

 * SSH access to each client is configured for the distribution of configs. Currently root-only (see: TODO)
 * Client addresses are correct
 * VPN IP pool subnets are valid subnets (/24)
 * Firewalls are configured to allow traffic on the defined Tinc port over TCP and UDP between clients
 * Each client has the same Tinc "parent" configuration directory (ie. `/etc/tinc`)
 * Each client has init control for Tinc (systemd, sysVinit, etc)
 * This will be used for a *new* Tinc VPN deployment.
 * The user will not modify client state files (ie. local & remote configs)

## TODO

 * Post-sync action: run X after a sync operation (ie: `/etc/init.d/tinc restart`)
 * Manage multiple VPN networks
 * Better SSH options, ie. SSH user, port and/or sudo user for synching configs.
 * Re-key feature
 * Don't store private keys for clients
 * Cater for manual/static VPN IP assignment
 * Larger subnet support

## Thanks

Thanks to the developers of Tinc! It's an awesome piece of software.

## Disclaimer

I'm not a programmer, but I do like to make things! Please use this at your own risk.

## License

The MIT License (MIT)

Copyright (c) 2016 Curtis K

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
