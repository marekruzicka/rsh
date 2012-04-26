#!/bin/bash

# Author: Marek Ruzicka (based on the idea from Alfred Kuemmel)
# Current Version: 2.24
#
# Changelog:
# v2.24 - Minor update to help, 'changelog' removed (not needed)
# v2.23 - Fixed minor bug in 'rvi', updated help (typos)
# v2.22 - Updated help, check for ambiguos usage of --help, some info messages update
# v2.21 - Fixed access rights 'rvi', code cleanup
# v2.2  - 'rvi' added
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
        echo -e "\n\tThis script will run command on filer remotely."
        echo -e "\n\tUSAGE:\n\t\t$HOST <command>"
        echo -e "\t\tIf no <command> is specified, you will be connected to the filer"
        echo -e "\n\tLIST OF COMMANDS:\n\t\tAll Ontap cmds under 'admin' privilige level (with some enhancements/limitations)."
        echo -e "\t\tAmbiguos commands such as 'halt', 'reboot' etc. are not allowed. Additionaly all cmds\n\t\tlisted in System Administration Guide as not allowed to run remotly, are restricted\n\t\tas well. (ping, savecore, setup, wrfile, etc ...)"
        echo -e "\n\t\t ls\t - List directory"
        echo -e "\t\t spare\t - Return number of spare disks on the filer."
        echo -e "\t\t qq\t - Sums up quotas and LUNs usage within given (or all) volume."
        echo -e "\t\t log\t - Show /etc/messages since beginning of month\n\t\t logExt\t - Show /etc/messages for last 2 months\n\t\t logFull - Show /etc/messages for last 13 months"
        echo -e "\t\t mount\t - Mount /vol/ROOT/etc or ETC\$ to /mnt/filers/<hostname>\n\t\t\t   (automatically unmounts after 3min of inactivity)"
        echo -e "\t\t rvi\t - Edit remote file. File has to be located in /etc directory\n\t\t\t   directly (can not be in subdirectory e.g. /etc/software/<file>)\n\t\t\t   No need to write full path to the file, /etc is added automatically\n."
        echo -e "\n\tCommand completion (pressing TAB after partially written cmd) works for all above mentioned\n\tcmds (including Ontap cmds)."
        echo -e "\texample:\t$HOST <TAB><TAB> => list all available commands (Ontap and local included)"
        echo -e "\n\tCmds: 'vol' 'lun' 'cifs' 'snapmirror' 'snapvault' 'vfiler' extend command completion also to subcommands."
        echo -e "\texample:\n\t\t$HOST vol st<TAB> => $HOST vol status"
        echo -e "\t\t$HOST vol <TAB><TAB> => list all available 'vol' subcommands"
        echo -e "\n\tCmds: 'rlm' 'bmc' 'sp' 'disk' 'environment' support complettion for limited set of subcommands.\n\tUsually the most used ones like 'status' or 'show'"
        echo -e "\texample:\n\t\t$HOST rl<TAB><TAB> => $HOST rlm status"
        echo -e "\n\tEXAMPLES:\n\t\t$HOST version\n\t\t$HOST qq <vol> (if <vol> is not specified, runs on all volumes)\n\t\t$HOST mount\n\t\t$HOST rvi <file>\n"
}

for i in $@; do
        if [ "$i" == halt ] || [ "$i" == reboot ]; then
                echo "Think Again!!!"
                logger -- "--- WARNING .rsh $HOST $@ WARNING ---"
                exit 0
        elif
                [[ "$i" == "--help" ]]; then
                _default
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
        rvi)
                # general variables
                g="\033[1;32m"  # green
                n="\033[0m"     # no color
                # INPUT: fsyn98 rvi testfile
                HOST=`basename $0`
                L_HOSTNAME=`grep $HOST /etc/hosts | awk '{print tolower($2)}'`
                U_HOSTNAME=`grep $HOST /etc/hosts | awk '{print $2}'`
                #remote filename => testfile
                R_FILE_NAME=`basename $2`
                        _log "r_file_name: $R_FILE_NAME"
                #remote location => /mnt/filers/c4dee1syn98
                R_FILE_LOC="/mnt/filers/$L_HOSTNAME"
                        _log "r_file_loc: $R_FILE_LOC"
                #remote file => /mnt/filers/c4dee1syn98/testfile
                R_FILE="$R_FILE_LOC/$R_FILE_NAME"
                        _log "r_file: $R_FILE"

                # create dir /tmp/rvi/<user>
                USER=`whoami`
                mkdir -p -m 777 /tmp/rvi

                # cp <file> (r_file) /tmp/rvi/<user>/<filer>.<file> (l_file)
                # mount will be done automatically via autofs at copy
                #local filename => fsyn98.testfile
                L_FILE_NAME="$HOST.$R_FILE_NAME.$USER"
                        _log "l_file_name: $L_FILE_NAME"
                #local location => /tmp/rvi/
                L_FILE_LOC="/tmp/rvi"
                        _log "l_file_loc: $L_FILE_LOC"
                #local file => /tmp/rvi/<user>/fsyn98.testfile.<user>
                L_FILE="$L_FILE_LOC/$L_FILE_NAME"
                        _log "l_file: $L_FILE"

                cp /mnt/filers/$L_HOSTNAME/$R_FILE_NAME $L_FILE 2>/dev/null
                if [[ $? -ne "0" ]]; then
                        echo -e "\n\t$R_FILE ($HOST:/etc/$R_FILE_NAME) does not exist.\n\tIt is only possible to edit files within /etc directory!!!\n"
                        exit 1
                fi

                # backup remote file
                DATE=`date +%Y%m%d-%H%M`
                R_FILE_BKP="$R_FILE.$DATE.$USER"
                sudo cp $R_FILE $R_FILE_BKP

                # cp l_file l_file.edit
                cp $L_FILE $L_FILE.edit

                EYN="e"
                while [[ $EYN == "e" ]]; do
                        # edit l_file.edit
                        vim $L_FILE.edit

                        # diff l_file l_file.edit
                        colordiff $L_FILE $L_FILE.edit
                        if [[ $? -eq "0" ]]; then
                                echo -e "$g\nNo changes to $R_FILE ($HOST:/etc/$R_FILE_NAME) detected.$n"
                        fi

                        echo -e "\n  You may now re-edit $HOST:/etc/$R_FILE_NAME, save changes to filer, or discard changes and quit...\n\n\t'E' or 'e' => re-edit $HOST:/etc/$R_FILE_NAME\n\t'Y' or 'y' => save file to filer\n\t'N' or 'n' => discard all changes and quit\n"
                        read  -p "  Do you want to save changes (e/y/n) [e]: " EYN
                                _log "eyn after read: $EYN"
                        case $EYN in
                                n | N)
                                        echo -e "File Not Saved... cleaning up everything."

                                        # Delete temp files, bkp on the filer stays untouched (to avoid granting sudo rm), exit 0
                                        rm -f $L_FILE $L_FILE.edit
                                        exit 0;;
                                y | Y)
                                        echo -e "Proceeding with File Save...\n"

                                        # Check if r_file was not changed while editing by rvi
                                        R_FILE_MTIME=`stat -c %Y $R_FILE`
                                        _log "r_file.mtime: $R_FILE_MTIME"
                                        L_FILE_MTIME=`stat -c %Y $L_FILE`
                                        _log "l_file.mtime: $L_FILE_MTIME"

                                        if [[ "$L_FILE_MTIME" -lt "$R_FILE_MTIME" ]]; then
                                                # if yes, save to l_file.unsaved, rm temp files, exit3
                                                echo -e "\n\tRemote file ($HOST:/etc/$R_FILE_NAME) has changed since you started to edit it..."
                                                echo -e "\nYour changes will be saved to '$L_FILE.unsaved'. Please, check the $HOST:/etc/$R_FILE_NAME for changes and edit it again.\n"
                                                cp $L_FILE.edit $L_FILE.unsaved
                                                rm $L_FILE $L_FILE.edit
                                                exit 3
                                        else
                                                # if no, proceed with save to filer
                                                sudo cp $L_FILE.edit $R_FILE

                                                # if save was not successful, keep the changes in l_file.unsaved, rm temp files, exit2
                                                if [[ $? -ne "0" ]]; then
                                                        echo -e "\n\tUnable to save $R_FILE ($HOST:/etc/$R_FILE_NAME).\nYour changes will be saved to '$L_FILE.unsaved'. Check filer/mount and try again."
                                                        cp $L_FILE.edit $L_FILE.unsaved
                                                        rm $L_FILE $L_FILE.edit
                                                        exit 2
                                                else
                                                        echo -e "File $R_FILE ($HOST:/etc/$R_FILE_NAME) Successfully Saved."
                                                fi

                                                rm -f $L_FILE $L_FILE.edit
                                        fi
                                        exit 0;;
                                *)
                                        # Re-edit file again
                                        EYN="e"
                                        echo -e "Re-opening $R_FILE ($HOST:/etc/$R_FILE_NAME) for edit..."
                        esac
                done
                exit 0;;
esac

$CONNECT $@

