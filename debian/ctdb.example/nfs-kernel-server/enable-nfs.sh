#!/bin/bash -e

base="/usr/share/doc/ctdb/examples/nfs-kernel-server/"
logfile="/tmp/enable-ctdb-nfs.$$.log" ; touch $logfile ;
ghostname=""

# functions ---------

die() { echo error: $@; echo ; exit 1; };
getout() { echo exit: $@; echo ; exit 0; };
stopservice() { echo stopping $1... ; systemctl stop $1 2>&1 >> $logfile 2>&1; }
disableservice() { echo disabling $1... ; systemctl disable $1 2>&1 >> $logfile 2>&1; }
startservice() { echo starting $1... ; systemctl start $1 2>&1 >> $logfile 2>&1; }
sysctlrefresh() { echo refreshing sysctl... ; sysctl --system 2>&1 >> $logfile 2>&1; }

backupfile() {
    echo backing up $1
    [ -f $1.prvctdb ] && die "backup file $1 already exists!"
    [ -f $1 ] && cp $1 $1.prvctdb || true
}

renamefiles() {
    for f; do
        [ -f "$f" ] || continue
        echo "Renaming $f to $f.prvctdb"
        mv "$f" "$f".prvctdb
    done
}

checkservice() {
    (systemctl list-unit-files | grep -q $1.service) || die "service $1 not found"
}

replacefile() {

    origfile=$1
    replfile=$2


    [ ! -f $base/$origfile ] && die "coult not find $base/$origfile"

    echo replacing $replfile...
    cp $base/$origfile $replfile
}

appendfile() {

    origfile=$1
    replfile=$2

    [ ! -f $base/$origfile ] && die "coult not find $base/$origfile"

    echo appending $base/$origfile to $replfile...
    cat $base/$origfile >> $replfile
}

execnfsenv() {

    file=$1 ; [ -f $file ] || due "inexistent file $file";

    echo executing $file...

    $file 2>&1 >> $logfile 2>&1;
}

fixnfshostname() {

    type nfsconf > /dev/null 2>&1 || die "nfsconf(8) not found"

    if [ "$ghostname" == "" ]; then
        echo "What is the FQDN for the public IP address of this host ?"
        echo -n "> "
        read ghostname
    fi

    echo "Setting $ghostname in nfs.conf..."
    nfsconf --set statd name "$ghostname"
}

# end of functions --

[ $UID != 0 ] && die "you need root privileges"

echo """
This script will enable CTDB NFS HA by changing the following files:

(1) /etc/nfs.conf                             ( replace )
(2) /etc/nfs.conf.d/*.conf                    ( rename  )
(3) /etc/services                             ( append  )
(4) /etc/sysctl.d/98-nfs-static-ports.conf    ( create  )
(5) /etc/default/quota                        ( replace )

and disabling the following services, as they will be managed
by ctdb:

(1) rpcbind
(2) nfs-kernel-server
(3) rpc.rquotad

Obs:
  - replaced files keep previous versions as "file".prevctdb
  - dependant services will also be stopped
"""

while true; do
    echo -n "Do you agree with this change ? (N/y) => "
    read answer
    [ "$answer" == "n" ] && getout "exiting without any changes"
    [ "$answer" == "y" ] && break
done


echo "checking requirements..."

checkservice nfs-kernel-server
checkservice quota
checkservice rpcbind

echo "requirements okay!"
echo

backupfile /etc/nfs.conf
renamefiles /etc/nfs.conf.d/*.conf
backupfile /etc/services
backupfile /etc/default/quota
echo

set +e

stopservice ctdb.service
stopservice quota.service
stopservice nfs-kernel-server.service
stopservice rpcbind.service
stopservice rpcbind.socket
stopservice rpcbind.target
echo

disableservice ctdb.service
disableservice quota.service
disableservice nfs-kernel-server.service
disableservice rpcbind.service
disableservice rpcbind.socket
disableservice rpcbind.target
echo

set -e

replacefile nfs.conf /etc/nfs.conf
replacefile 98-nfs-static-ports.conf /etc/sysctl.d/98-nfs-static-ports.conf
replacefile quota /etc/default/quota
echo

appendfile services /etc/services
echo

fixnfshostname
echo

sysctlrefresh
echo

echo """Finished! Make sure to configure properly:

    - /etc/exports (containing the clustered fs to be exported)
    - /etc/ctdb/nodes (containing all your node private IPs)
    - /etc/ctdb/public_addressess (containing public addresses)

A log file can be found at:

    - /tmp/enable-ctdb-nfs.$$.log

Remember:

    - to place a cluster lock in /etc/ctdb/ctdb.conf:
        ...
        [cluster]
        cluster lock = /clustered.filesystem/.reclock
        ...

And, make sure you enable ctdb service again:

    - systemctl enable ctdb.service
    - systemctl start ctdb.service

Enjoy!
"""
