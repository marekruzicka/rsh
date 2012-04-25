#!/bin/bash

# Author: Marek Ruzicka (based on the idea from Alfred Kuemmel)
# Current Version: 2.12
#
# Changelog:
# v2.12 - Minor bug fix
# v2.11 - Added 'changelog' command to track updates to script
# v2.1  - CIFS support for 'mount' added
# v2.0  - Simple debugger, 'mount' for supported filers (nfs only atm), major update to help,
#         extended 'log' (logExt, logFull) added. Command completion added.
# v1.91 - updated help
# v1.9  - Added 'log' command to display /etc/messages localy
# v1.8  - Added 'qq' option, real quota usage (A. Kuemmel)
# v1.7  - Added additional tests for usage of ambiguos commands. (halt, restart)
# v1.6  - Added logging
# v1.5  - Added 'spare' option - spare disk counter
# v1.4  - Disabled auth agent forwarding, and X11 forwarding which were generating errors in /etc/messages on the filers
# v1.3  - RSH changed to SSH
# v1.2  - Added tests for reboot & halt
# V1.1  - Added support for 'ls' cmd
# v1.0  - Added simple help, and test for several forbidden cmds
# v0.9  - initial release, simply passing the arguments to filer
#
# TODO:
# rvi
# 
# Dependencies:
# - All filers need to send syslog messages to local syslog server. These should be populated in 1 common file:
# /var/log/netapp/messages
# - autofs (automounter) pointing to /mnt/filers

SSH=/usr/bin/ssh
BASENAME=/usr/bin/basename
HOST=`$BASENAME $0`
L_HOSTNAME=`grep $HOST /etc/hosts | awk '{print tolower($2)}'`
U_HOSTNAME=`grep $HOST /etc/hosts | awk '{print $2}'`
CONNECT="$SSH -x -a root@$HOST"
NETAPP_LOGS=/var/log/netapp

#_DEBUG=true
_log() {
if [[ "$_DEBUG" == "true" ]]; then
        echo -e 1>&2 ">> $@"
fi
}

_default () {
        echo -e "\n\tThis script will run command on filer remotly."
        echo -e "\n\tUSAGE:\n\t\t$HOST <command>"
        echo -e "\n\tLIST OF COMMANDS:\n\t\tAll Ontap cmds under 'admin' privilige level (with some enhancements/limitations)."
        echo -e "\t\tAmbiguos commands such as 'halt', 'reboot' etc. are not allowed. Additionaly all cmds\n\t\tlisted in System Administration Guide as not allowed to run remotly, are restricted\n\t\tas well. (ping, savecore, setup, wrfile, etc ...)"
        echo -e "\n\t\t ls\t - List directory"
        echo -e "\t\t spare\t - Return number of spare disks on the filer."
        echo -e "\t\t qq\t - Sums up quotas and LUNs usage within given (or all) volume."
        echo -e "\t\t log\t - Show /etc/messages since beginning of month\n\t\t logExt\t - Show /etc/messages for last 2 months\n\t\t logFull - Show /etc/messages for last 13 months"
        echo -e "\t\t mount\t - Mount /vol/ROOT/etc or ETC\$ to /mnt/filers/<hostname>\n\t\t\t  (automatically unmounts after 3min of inactivity)"
        echo -e "\n\tCommand completion (pressing TAB after partially written cmd) works for all above mentioned\n\tcmds (including Ontap cmds)."
        echo -e "\texample:\t$HOST <TAB><TAB> => list all available commands (Ontap and local included)"
        echo -e "\n\tCmds: 'vol' 'lun' 'cifs' 'snapmirror' 'snapvault' 'vfiler' extend command completion also to subcommands."
        echo -e "\texample:\n\t\t$HOST vol st<TAB> => $HOST vol status"
        echo -e "\t\t$HOST vol <TAB><TAB> => list all available 'vol' subcommands"
        echo -e "\n\tCmds: 'rlm' 'bmc' 'sp' 'disk' 'environment' support complettion for limited set of subcommands.\n\tUsually the most used ones like 'status' or 'show'"
        echo -e "\texample:\n\t\t$HOST rl<TAB><TAB> => $HOST rlm status"
        echo -e "\n\tEXAMPLES:\n\t\t$HOST version\n\t\t$HOST qq <vol> (if <vol> is not specified, runs on all volumes)\n\t\t$HOST mount\n"
}

_changelog () {
        echo -e "
\t$HOST Changelog...\n
[12/04/20 v2.12] - minor bug fix
\n[12/04/19 v2.11] - 'changelog' command added to show recent changes.
Minor update to help. Minor fixes. Code cleanup.
\n[12/04/18 v2.10] - mount extended for CIFS support. Filers without NFS
license are mounted via CIFS. Same rules apply.
\n[12/04/16 v2.00] - 'mount' command added for easy mounting /etc to
/mnt/filers/<hostname>. Unmounts automatically after 180s of inactivity.
Supports NFS only. (CIFS support will be added in later versions)
Extended log added 'logExt' and 'logFull' for showing last 2 months
and last year of logs (keep in mind logrotate). Help completely rewritten.
Command completion support added for all Ontap and local commands. Read help
for more info. $HOST --help
\n[12/04/12 v1.91] - only minor update to help. $HOST --help
\n[12/04/11 v1.90] - 'log' command added. Reads /etc/messages from local copy
(/var/log/netapp/messages) and displays up to 1 month of logs. Logrotate runs
once a month, so running this command first days in month will provide very
limited output. (will be addressed in later version)
\n[12/04/10 v1.80] - 'qq' integrated into the script. $HOST qq <vol>
Sums up quotas and LUNs usage within given volume. If no volume is specified,
runs on all volumes on the filer. (original code by A.Kuemmel)
"
}

for i in $@; do
        if [ "$i" == halt ] || [ "$i" == reboot ]; then
                echo "Think Again!!!"
                logger -- "--- WARNING .rsh $HOST $@ WARNING ---"
                exit 0
        fi
done

logger -- ".rsh $HOST $@"

case $1 in
        -h | --help)
                _default
                exit 0;;
        ping | traceroute | arp | orouted | routed | savecore | setup | halt | reboot | wrfile)
                echo -e "Command not allowed. Refer to the NetApp System Administration Guide for more info.\nConnect to the filer directly, and run the command locally."
                exit 0;;
        ls)
                PRIV="priv set -q advanced;"
                $CONNECT $PRIV $1 $2
                exit 0;;
        spare)
                $CONNECT vol status -s | grep spare | grep -v " spare " | wc -l
                exit 0;;
        qq)
                if [ -z "$2" ]; then
                        echo -e "\nChecking filer $HOST for all its volumes usage"
                        for i in `$HOST df -g | grep -v snap | grep -v capacity | cut -d'/' -f 3`; do
                                echo -e "\n----checking vol $i:"
                                $HOST df -g $i | grep -v snap
                                $HOST quota report | grep tree | grep "/$i/" | awk '{u=u+$5;l=l+$6} END {printf("    Quota LIMIT/USAGE:%6dGB,  %6dGB\n",l/1024/1024,u/1024/1024)}'
                                $HOST lun show | grep "/vol/$i/" | awk -F"(" '{print $2}' | awk -F")" '{print $1}' | awk '{u=u+$1} END {printf("      Lun       USAGE:           %6dGB\n",u/1024/1024/1024)}'
                        done
                else
                        echo -e "\nChecking filer $HOST for Volume $2 Quota usage"
                        $HOST df -g $2 | grep -v snap
                        $HOST quota report | grep tree | grep "/$2/"  | awk '{u=u+$5;l=l+$6} END {printf("    Quota LIMIT/USAGE:%6dGB,  %6dGB\n",l/1024/1024,u/1024/1024)}'
                        $HOST lun show | grep "/vol/$2/" | awk -F"(" '{print $2}' | awk -F")" '{print $1}' | awk '{u=u+$1} END {printf("      Lun       USAGE:           %6dGB\n",u/1024/1024/1024)}'
                fi
                exit 0;;
        log)
                grep " $L_HOSTNAME " $NETAPP_LOGS/messages
                exit 0;;
        logExt)
                if [ -e /var/log/netapp/messages.1 ]; then
                                _log "messages.1 exist (exit status: $?)"
                        grep " $L_HOSTNAME " $NETAPP_LOGS/messages.1 $NETAPP_LOGS/messages
                else
                                _log "messages.1 does not exist (exit status: $?)"
                        echo -e "\n\tNo older logs are available...\n\trunning '$HOST log'\n"
                        $HOST log
                fi
                exit 0;;
        logFull)
                array=(`ls -tr $NETAPP_LOGS`)
                                _log "${array[@]}"
                        for i in ${array[@]}; do
                                        _log "$i"
                                if [[ $i =~ messages* ]]; then
                                                _log "Does filename contain 'messages'? (exit status: $?)"
                                                _log "$L_HOSTNAME"
                                                _log "$NETAPP_LOGS/$i"
                                        zgrep " $L_HOSTNAME " $NETAPP_LOGS/$i
                                else
                                        exit 0
                                                _log "No messages file found. Exiting..."
                                fi
                        done
               exit 0;;
        mount)
                HOSTNAME=`grep $HOST /etc/auto.filer | awk '{print $1}'`
                if [ -z "$HOSTNAME" ]; then
                        echo -e "\n\tNot possible to automount $HOST. Most likely NFS/CIFS is not licensed, or /etc is not exported/shared properly.\n\tTry to mount it manually...\n\n\tIf manual mounting works, please inform M.Ruzicka.\n"
                                _log "hostname is $HOSTNAME (NULL)."
                else
                                _log "hostname is $HOSTNAME"
                        MOUNT="/mnt/filers/$HOSTNAME"
                                _log "mount is $MOUNT"
                        ls $MOUNT > /dev/null
                        mount | grep $HOST
                fi
                exit 0;;
        changelog)
                _changelog
                exit 0;;
esac

$CONNECT $@

