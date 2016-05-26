#!/bin/sh
#
# The MIT License (MIT)
# Copyright © 2015 Toni Van de Voorde <toni.vdv@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the “Software”), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#

set -o errexit

# BEGIN _functions

# @info:    Prints the ascii logo
asciiLogo ()
{
  printf "%s\n" ''
  printf "%s\n" ''
  printf "%s\n" '                      ##         .'
  printf "%s\n" '                ## ## ##        ==               _   _ _____ ____'
  printf "%s\n" '             ## ## ## ## ##    ===              | \ | |  ___/ ___|'
  printf "%s\n" '         /"""""""""""""""""\___/ ===            |  \| | |_  \___ \'
  printf "%s\n" '    ~~~ {~~ ~~~~ ~~~ ~~~~ ~~~ ~ /  ===- ~~~     | |\  |  _|  ___) |'
  printf "%s\n" '         \______ o           __/                |_| \_|_|   |____/'
  printf "%s\n" '           \    \         __/'
  printf "%s\n" '            \____\_______/'
  printf "%s\n" ''
  printf "%s\n" ''
}

# @info:    Prints the usage
usage ()
{

  asciiLogo

  cat <<EOF
Usage: $0 <machine-name> [options]

Options:

  -f, --force               Force reconfiguration of nfs
  -n, --nfs-config          NFS configuration to use in /etc/exports (default to '-alldirs -mapall=\$(id -u):\$(id -g)')
  -s, --shared-folder,...   Folder to share. Use local:mount form to specify a different name for the docker machine mount (default to /Users)
  -m, --mount-opts          NFS mount options (default to 'noacl,async[,nolock on Cygwin]')

Examples:

  $ docker-machine-nfs test

    > Configure the /Users folder with NFS

  $ docker-machine-nfs test --shared-folder=/Users --shared-folder=/var/www

    > Configures the /Users and /var/www folder with NFS

  $ docker-machine-nfs test --shared-folder=/Users:/home

    > Configures the /Users folder with NFS as /home in the docker machine

  $ docker-machine-nfs test --shared-folder=/var/www --nfs-config="-alldirs -maproot=0"

    > Configure the /var/www folder with NFS and the options '-alldirs -maproot=0'

  $ docker-machine-nfs test --mount-opts="noacl,async,nolock,vers=3,udp,noatime,actimeo=1"

    > Configure the /User folder with NFS and specific mount options.

EOF
  exit 0
}

# @info:    Prints error messages
# @args:    error-message
echoError ()
{
  printf "\033[0;31mFAIL\n\n%s \033[0m\n" "$1"
}

# @info:    Prints warning messages
# @args:    warning-message
echoWarn ()
{
  printf "\033[0;33m%s \033[0m\n" "$1"
}

# @info:    Prints success messages
# @args:    success-message
echoSuccess ()
{
  printf "\033[0;32m%s \033[0m\n" "$1"
}

# @info:    Prints check messages
# @args:    success-message
echoInfo ()
{
  printf "\033[1;34m[INFO] \033[0m$1"
}

# @info:    Prints property messages
# @args:    property-message
echoProperties ()
{
  printf "\t\033[0;35m- %s \033[0m\n" "$1"
}

# @info:    Checks if a given property is set
# @return:  true, if variable is not set; else false
isPropertyNotSet()
{
  if [ -z ${1+x} ]; then return 0; else return 1; fi
}

case $(uname) in
  CYGWIN*)
    sudo()
    {
      $@;
    }
    ;;
  *) ;;
esac

# @info:    Sets the default properties
setPropDefaults()
{
  prop_machine_name=
  prop_shared_folders=()
  case $(uname) in
    CYGWIN*) prop_nfs_config="(rw,map_static=/etc/nfs/server.map)";;
    *) prop_nfs_config="-alldirs -mapall="$(id -u):$(id -g);;
  esac
  case $(uname) in
    CYGWIN*) prop_mount_options="noacl,async,nolock";;
    *) prop_mount_options="noacl,async";;
  esac
  prop_force_configuration_nfs=false
}

# @info:    Parses and validates the CLI arguments
parseCli()
{

  [ "$#" -ge 1 ] || usage

  prop_machine_name=$1

  for i in "${@:2}"
  do
    case $i in
      -s=*|--shared-folder=*)
        local shared_folder="${i#*=}"
        shared_folder=${shared_folder%:*}:${shared_folder#*:}
        shift

        if [ ! -d "${shared_folder%:*}" ]; then
          echoError "Given shared folder '${shared_folder%:*}' does not exist!"
          exit 1
        fi

        prop_shared_folders+=($shared_folder)
      ;;

      -n=*|--nfs-config=*)
        prop_nfs_config="${i#*=}"
      ;;

      -m=*|--mount-opts=*)
        prop_mount_options="${i#*=}"
      ;;

      -f|--force)
        prop_force_configuration_nfs=true
        shift
      ;;

      *)
        echoError "Unknown argument '$i' given"
        printf "\n"
        usage
      ;;
    esac
  done

  if [ ${#prop_shared_folders[@]} -eq 0 ]; then
    prop_shared_folders+=("/Users:/Users")
  fi;

  echoInfo "Configuration:"

  printf "\n"
  printf "\n"

  echoProperties "Machine Name: $prop_machine_name"
  for shared_folder in "${prop_shared_folders[@]}"
  do
    echoProperties "Shared Folder: $shared_folder"
  done

  echoProperties "Mount Options: $prop_mount_options"
  echoProperties "Force: $prop_force_configuration_nfs"

  printf "\n"
}

# @info:    Checks if the machine is present
# @args:    machine-name
# @return:  (none)
checkMachinePresence ()
{
  echoInfo "Machine presence ... \t\t\t"

  if [ -z "$(docker-machine ls | sed 1d | grep -w "$1")" ]; then
    echoError "Could not find the machine '$1'!"; exit 1;
  fi

  echoSuccess "OK"
}

# @info:    Checks if the machine is running
# @args:    machine-name
# @return:  (none)
checkMachineRunning ()
{
  echoInfo "Machine running ... \t\t\t"

  machine_state=$(docker-machine ls | sed 1d | grep "^$1\s" | awk '{print $4}')

  if [ "Running" != "${machine_state}" ]; then
    echoError "The machine '$1' is not running but '${machine_state}'!";
    exit 1;
  fi

  echoSuccess "OK"
}

# @info:    Returns the driver used to create the machine
# @args:    machine-name
# @return:  The driver used to create the machine
getMachineDriver ()
{
  docker-machine ls | sed 1d | grep "^$1\s" | awk '{print $3}'
}

# @info:    Loads mandatory properties from the docker machine
lookupMandatoryProperties ()
{
  echoInfo "Lookup mandatory properties ... \t\t"

  prop_machine_ip=$(docker-machine ip $1)

  prop_machine_driver=$(getMachineDriver $1)

  if [ "$prop_machine_driver" = "vmwarefusion" ]; then
    prop_network_id="Shared"
    prop_nfshost_ip=$(ifconfig -m `route get 8.8.8.8 | awk '{if ($1 ~ /interface:/){print $2}}'` | awk 'sub(/inet /,""){print $1}')
    prop_machine_ip=$prop_nfshost_ip
    if [ -z "${prop_nfshost_ip}" ]; then
      echoError "Could not find the vmware fusion net IP!"; exit 1
    fi
    local nfsd_line="nfs.server.mount.require_resv_port = 0"
    echoSuccess "\t\tOK"

    echoInfo "Check NFS config settings ... \n"
    if [ "$(grep -Fxq "$nfsd_line" /etc/nfs.conf)" = "0" ]; then
      echoInfo "/etc/nfs.conf is setup correctly!"
    else
      echoWarn "\n !!! Sudo will be necessary for editing /etc/nfs.conf !!!"
      # Backup /etc/nfs.conf file
      sudo cp /etc/nfs.conf /etc/nfs.conf.bak && \
      echo "nfs.server.mount.require_resv_port = 0" | \
        sudo tee /etc/nfs.conf > /dev/null
      echoWarn "\n !!! Backed up /etc/nfs.conf to /nfs.conf.bak !!!"
      echoWarn "\n !!! Added 'nfs.server.mount.require_resv_port = 0' to /etc/nfs.conf !!!"
    fi
    echoSuccess "\n\t\t\t\t\t\tOK"
    return
  fi

  if [ "$prop_machine_driver" = "xhyve" ]; then
    prop_network_id="Shared"
    prop_nfshost_ip=$(ifconfig -m `route get $prop_machine_ip | awk '{if ($1 ~ /interface:/){print $2}}'` | awk 'sub(/inet /,""){print $1}')
    if [ -z "${prop_nfshost_ip}" ]; then
      echoError "Could not find the xhyve net IP!"; exit 1
    fi
    echoSuccess "OK"
    return
  fi

  if [ "$prop_machine_driver" = "parallels" ]; then
    prop_network_id="Shared"
    prop_nfshost_ip=$(prlsrvctl net info \
      "${prop_network_id}" | grep 'IPv4 address' | sed 's/.*: //')

    if [ -z "${prop_nfshost_ip}" ]; then
      echoError "Could not find the parallels net IP!"; exit 1
    fi

    echoSuccess "OK"
    return
  fi

  if [ "$prop_machine_driver" != "virtualbox" ]; then
    echoError "Unsupported docker-machine driver: $prop_machine_driver"; exit 1
  fi

  prop_network_id=$(VBoxManage showvminfo $1 --machinereadable |
    grep hostonlyadapter | cut -d'"' -f2)
  if [ -z "${prop_network_id}" ]; then
    echoError "Could not find the virtualbox net name!"; exit 1
  fi

  prop_nfshost_ip=$(VBoxManage list hostonlyifs |
    grep "${prop_network_id}" -A 3 | grep IPAddress |
    cut -d ':' -f2 | xargs);
  if [ -z "${prop_nfshost_ip}" ]; then
    echoError "Could not find the virtualbox net IP!"; exit 1
  fi

  echoSuccess "OK"
}

# @info:    Configures the NFS
configureNFS()
{
  echoInfo "Configure NFS ... \n"
  if isPropertyNotSet $prop_machine_ip; then
    echoError "'prop_machine_ip' not set!"; exit 1;
  fi

  case $(uname) in
    CYGWIN*)
      local server_map_file=/etc/nfs/server.map

      awk '!a[$0]++' $server_map_file | tee $server_map_file > /dev/null
      local checksum=$(cksum $server_map_file)

      echoInfo "  Updating /etc/nfs/server.map ... \t"
      (
        printf "\nuid\t1000\t%s\t# user id for %s\n" $(id -u) "$USER" | tee -a $server_map_file &&
        printf "\ngid\t50\t%s\t# group id for %s\n" $(id -g) "$USER" | tee -a $server_map_file &&
        awk '!a[$0]++' $server_map_file | tee $server_map_file
      ) > /dev/null

      if [ "$(cksum $server_map_file)" = "$checksum" ]; then
        echoSuccess "No changes"
      else
        echoSuccess "OK"
      fi

      local exports_file=/etc/exports
      ;;
    *)
      echoWarn "\n !!! Sudo will be necessary for editing /etc/exports !!!"
      local exports_file=/etc/exports
      ;;
  esac

  local checksum=$(cksum $exports_file)

  echoInfo "  Updating /etc/exports ... \t\t"
  for shared_folder in "${prop_shared_folders[@]}"
  do
    local host_folder=${shared_folder%:*}
    # Update the /etc/exports file
    (
      printf "\n%s %s %s\n" "$host_folder" "$prop_machine_ip" "$prop_nfs_config" |
        sudo tee -a $exports_file &&
        awk '!a[$0]++' $exports_file | sudo tee $exports_file
    ) > /dev/null
  done

  case $(uname) in
    CYGWIN*)
      if [ "$(cksum $exports_file)" = "$checksum" ]; then
        echoSuccess "No changes"
      else
        # It seems a system restart is necessary :(
        echoSuccess "System restart required for nfsd changes to take effect"
      fi
      ;;
    *)
      # Restart nfsd
      sudo nfsd restart ; sleep 2 && sudo nfsd checkexports
      echoSuccess "OK"
      ;;
  esac

}

# @info:    Configures the VirtualBox Docker Machine to mount nfs
configureBoot2Docker()
{
  echoInfo "Configure Docker Machine ... \t\t"

  if isPropertyNotSet $prop_machine_name; then
    echoError "'prop_machine_name' not set!"; exit 1;
  fi
  if isPropertyNotSet $prop_nfshost_ip; then
    echoError "'prop_nfshost_ip' not set!"; exit 1;
  fi

  # render bootlocal.sh and copy bootlocal.sh over to Docker Machine
  # (this will override an existing /var/lib/boot2docker/bootlocal.sh)

  local bootlocalsh='#!/bin/sh
  sudo umount /Users'

  local host_folder mount_folder

  for shared_folder in "${prop_shared_folders[@]}"
  do
    mount_folder=${shared_folder#*:}
    bootlocalsh="${bootlocalsh}
    sudo mkdir -p "$mount_folder
  done

  bootlocalsh="${bootlocalsh}
  sudo /usr/local/etc/init.d/nfs-client start"

  for shared_folder in "${prop_shared_folders[@]}"
  do
    host_folder=${shared_folder%:*}
    mount_folder=${shared_folder#*:}
    bootlocalsh="${bootlocalsh}
    sudo mount -t nfs -o "$prop_mount_options" "$prop_nfshost_ip":"$host_folder" "$mount_folder
  done

  local file="/var/lib/boot2docker/bootlocal.sh"

  docker-machine ssh $prop_machine_name \
    "echo '$bootlocalsh' | sudo tee $file && sudo chmod +x $file && sync" > /dev/null

  sleep 2

  echoSuccess "OK"
}

# @info:    Restarts Docker Machine
restartDockerMachine()
{
  echoInfo "Restart Docker Machine ... \t\t"

  if isPropertyNotSet $prop_machine_name; then
    echoError "'prop_machine_name' not set!"; exit 1;
  fi

  docker-machine restart $prop_machine_name > /dev/null

  echoSuccess "OK"
}

# @return:  'true', if NFS is mounted; else 'false'
isNFSMounted()
{
  for shared_folder in "${prop_shared_folders[@]}"
  do
    local host_folder=${shared_folder%:*}
    local nfs_mount=$(docker-machine ssh $prop_machine_name "sudo df" |
      grep "$prop_nfshost_ip:$host_folder")
    if [ -z "$nfs_mount" ]; then
      echo "false";
      return;
    fi
  done

  echo "true"
}

# @info:    Verifies that NFS is successfully mounted
verifyNFSMount()
{
  echoInfo "Verify NFS mount ... \t\t\t"

  local attempts=10

  while [ ! $attempts -eq 0 ]; do
    sleep 1
    [ "$(isNFSMounted)" = "true" ] && break
    attempts=$(($attempts-1))
  done

  if [ $attempts -eq 0 ]; then
    echoError "Cannot detect the NFS mount :("; exit 1
  fi

  echoSuccess "OK"
}

# @info:    Displays the finish message
showFinish()
{
  printf "\n\033[0;36m"
  printf "%s\n" "--------------------------------------------"
  printf "%s\n" ""
  printf "%s\n" " The docker-machine '$prop_machine_name'"
  printf "%s\n" " is now mounted with NFS!"
  printf "%s\n" ""
  printf "%s\n" " ENJOY high speed mounts :D"
  printf "%s\n" ""
  printf "%s\n" "--------------------------------------------"
  printf "\033[0m"
}

# END _functions

setPropDefaults

parseCli "$@"

checkMachinePresence $prop_machine_name
checkMachineRunning $prop_machine_name

lookupMandatoryProperties $prop_machine_name

configureNFS

printf "\n"
echoProperties "Machine IP: $prop_machine_ip"
echoProperties "Network ID: $prop_network_id"
echoProperties "NFSHost IP: $prop_nfshost_ip"
printf "\n"

if [ "$(isNFSMounted)" = "true" ] && [ "$prop_force_configuration_nfs" = false ]; then
    echoInfo "NFS already mounted" ; showFinish ; exit 0
fi

configureBoot2Docker
restartDockerMachine

verifyNFSMount

showFinish
