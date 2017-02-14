#!/bin/bash

# 6.1.1 Upgrade Prep script

# set -n #debug
# set -u #Check undeclared vars
# set -x

# Set colours and text mode variables
red=$(tput setaf 1)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)
magenta=$(tput setaf 5)
cyan=$(tput setaf 6)
white=$(tput setaf 7)
bold=$(tput bold)
ulon=$(tput smul)
uloff=$(tput rmul)
reset=$(tput sgr0)

################################################################
# Variables

base='/dumps/upgrade'
actconfig='/act/etc/actconfig'
cdspatchlog='/dumps/autoupdatepatch-CDS6.1.1.43975-update.log'
cdspatch='/dumps/patch-CDS6.1.1.43975.gpg'
udspatchlog='/dumps/uds-patch.log'
svcupgrade='/dumps/UPDATE_6.1.1.43706'
svcpreflight='/dumps/upgrade-preflight.txt'
adhdlog='/dumps/adhd.log'
adhd_init='/tmp/act_dedup_init'
hotfixprefix='hf-CDS6.1.1'
hotfixupload=' /home/admin/upload'


declare -a installfiles
installfiles[${#installfiles[*]}]='/dumps/UPDATE_6.1.1.43706'
installfiles[${#installfiles[*]}]='/dumps/upgrade-preflight.txt'
installfiles[${#installfiles[*]}]='/dumps/vmtest.sh'
installfiles[${#installfiles[*]}]='/dumps/patch-CDS6.1.1.43975.gpg'


#define svcfiles as array
declare -a svcfiles
svcfiles[${#svcfiles[*]}]='/tmp/ldflash.tgz'
svcfiles[${#svcfiles[*]}]='/tmp/flashbase.tgz'
svcfiles[${#svcfiles[*]}]='/tmp/initrd.tgz'


#define options as array
declare -a options
options[${#options[*]}]="Service Status"
options[${#options[*]}]="Show Version Info"
options[${#options[*]}]="CDS Pre Check"
options[${#options[*]}]="Scheduler Start"
options[${#options[*]}]="Scheduler Stop"
options[${#options[*]}]="Enable GC Service"
options[${#options[*]}]="Disable GC Service "
options[${#options[*]}]="Enable ADHD and services"
options[${#options[*]}]="Dissable ADHD and services"
options[${#options[*]}]="Start CDS upgrade"
options[${#options[*]}]="Start SVC Upgrade (this will eventually reboot the node)"
options[${#options[*]}]="Monitor ADHD Shutdown"
options[${#options[*]}]="Install HotFixes"
options[${#options[*]}]="Post Upgrade Check and Configuration"
options[${#options[*]}]="quit";



################################################################
# Menu Function

function menu() {
	select opt in "${options[@]}"
	do
		case ${opt} in
			${options[0]}) service_status ; ;;
			${options[1]}) show_version ; ;;
			${options[2]}) cds_pre_check ; ;;
			${options[3]}) scheduler_start; ;;
			${options[4]}) scheduler_stop; ;;
			${options[5]}) gc_enable; ;;
			${options[6]}) gc_disable; ;;
			${options[7]}) enable_adhd ; ;;
			${options[8]}) disable_adhd ; ;;
			${options[9]}) cds_upgrade ; ;; # cds_upgrade
			${options[10]}) svc_upgrade ; ;;
			${options[11]}) monitor_adhd_status ; ;;
			${options[12]}) hotfix ; ;;
			${options[13]}) post_upgrade ; ;;
			(quit) exit; ;;
			(*) echo "${opt}"; ;;
		esac;
	done
}



################################################################
# Service Status Function

function service_status() {
	#echo 'Current setting for scheduler'
	#udsinfo getparameter -param enablescheduler
	#echo 'Current setting for expirations'
	#udsinfo getparameter -param enableexpiration
	#echo "ADHD Runtime Setting"
	
	echo '----------------------------------------------'
	echo 'UDPPM Status'
	echo '----------------------------------------------'
	udsinfo getparameter -type udppm | grep "^enable"
	
	echo '----------------------------------------------'
	echo 'GC Status'
	echo '----------------------------------------------'
	udsinfo getgcschedule -type gc
	
	echo '----------------------------------------------'
	echo 'ADHD_NO_DEDUP Status'
	echo '----------------------------------------------'
	grep 'export ADHD_NO_DEDUP' ${actconfig}
	echo
}


################################################################
# Disable Service Function

function disable_services() {
	echo 'Disabling Scheduler and Expirations'
	udstask setparameter -param  enablescheduler -value false
	udstask setparameter -param  enableexpiration -value false
}


################################################################
# Enable Service Function

function enable_services() {
	echo 'Enabling Scheduler and Expirations'
	udstask setparameter -param  enablescheduler -value true
	udstask setparameter -param  enableexpiration -value true
}

################################################################
# Check existence of files Function
function files_check() {

	#Check files exist
	echo 'Check for required install files.....'
	for i in "${installfiles[@]}" ; do 
	[ -f "${i}" ] && { echo "Found ${i}"; } || { echo "File ${i} not found!" && confirm "continue"; }
	done
}

################################################################
# CDS Upgrade Pre Check Function

function cds_pre_check() {
	echo 'Starting pre-install checks.'
	
	#Check files exist
	files_check

	# Make the systeminfo into a function and add ifconfig tun0 output)
	echo ''
	echo 'Sysinfo....'
	udstask debug systeminfo

	echo ''
	echo 'Cluster Details'
	udsinfo lscluster

	echo ''
	echo 'udsinfo getparameter'
	udsinfo getparameter | grep ignore

	echo ''
	echo 'Network settings'
	ifconfig -a
	echo
	
	echo 'Routing Table'
	netstat -r
	echo

	echo ''
	echo 'ec_getend output'
	ec_getend

	echo ''
	echo 'Execute /act/etc/vfy script'
	/act/etc/vfy

	echo ''
	echo 'Check, dump and clear existing errors'
	cds_error_check

	echo ''
	echo 'List Node Status'
	lsnode

	echo 'Check for correct panel_name (ACTCDS, ACTCLU)'
	
	lsnode | grep -q ACTCDS 
	[ $? == 0 ] && { echo 'Panel_name = ACTCDS'; } \
	|| { echo 'Incorrect panel_name, exiting' && confirm "Continue"; }
	
	lsnode | grep -q ACTCLU  
	[ $? == 0 ] && { echo 'Panel_name ACTCLU'; } \
		|| { echo 'Incorrect panel_name, exiting' && confirm "Continue"; }
		
	
	####### Need to implement operative IP / cluster IP differential check

	
	echo ''
	echo 'Disk and mounted partitions'
	df -h

	echo ''
	echo 'Check no usb devices are connected'
	ls -l /dev/disk/by-id/usb* 
	[ $? == 2 ] && { echo 'Good, no usb devices found'; }\
	 	|| { echo 'USB Device Found, Exiting' && menu; }
	
	echo ''
	echo 'Current CDS Version'
	udsinfo lsversion

	echo ''
	echo 'Current SVC version (compass/vrmf)'
	cat /compass/vrmf

	echo ''
	echo 'Report Running Jobs'
	reportrunningjobs
	jobs="$(udsinfo lsjob | wc -l)"
	[ "${jobs}" == 0 ] && { echo 'No jobs are running, continuing.'; } \
	 	|| { echo 'Found executing jobs, please ensure no jobs are executing before proceeding, exiting' && menu; }
	
	#Check that udprestore and udpengine processes are not executing
	echo ''
	
	pgrep -f "udprestore"
	[ $? == 1 ] && { echo 'Good, no udprestore process found'; } \
		||  { echo 'udprestore process found, Exiting' && exit; }
	
	pgrep -f "udpengine"
	[ $? == 1 ] && { echo 'Good, no udpengine process found'; } \
		|| { echo 'udpengine process found, Exiting' && exit; }

	echo '/act/etc/msgtool.pl ps output....'
	perl /act/etc/msgtool.pl ps
	
	monit summary
	
	echo 'Checking for Global Mirroring'
	lsrcrelationship
	
	
	#######  Need to implement tar of /home/debug 
	
	confirm "disable ADHD"
	echo 'Disabling ADHD.....'
	disable_adhd
	
	echo 'If this is the first time that the pre checks have completed and ADHD is down'
	echo 'Proceed with manual rebooting of ClU Node once completed reboot config node use (satask stopnode -reboot)'
	exit
	
	
	confirm "Return to menu"
	#echo 'CDS Upgrade Started'
	#cds_upgrade
	
	menu
	
}


################################################################
# Show Version Info Function

function show_version() {

	echo 'Current CDS Version'
	udsinfo lsversion
	echo ''
	echo 'Current SVC version (compass/vrmf)'
	cat /compass/vrmf
	
}


################################################################
# Disable ADHD Function

function disable_adhd() {

	# Back up and edit in-place actconfig to disable adhd
	cp ${actconfig} ${actconfig}.bak
	sed "s/^#export ADHD_NO_DEDUP/export ADHD_NO_DEDUP/" ${actconfig}.bak > ${actconfig}

	grep '^export ADHD_NO_DEDUP' ${actconfig}
	echo 8 > ${adhd_init} 
	confirm 'ADHD Shutdown'
	echo 'Shutting down ADHD.....'
	perl /act/etc/msgtool.pl shutdown

	#Grab the the last adhd log entry time and convert to epoch.
	#This is so we do not match previous 'open for business' entries.
	#epoch=$(tail -1 adhd.log \
	#	| grep -oE "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}" \
	#	| read time ; date --date="${time}" +%s)
	
    # Call monitor_adhd_shutdown()
	monitor_adhd_shutdown
	echo 'Node status.....'
	lsnode
	
	confirm "continue"
	menu

}

################################################################
# Enable ADHD Upgrade Function

function enable_adhd() {

	# Back up and edit in-place actconfig to disable adhd
	cp ${actconfig} ${actconfig}.post
	sed "s/^export ADHD_NO_DEDUP/#export ADHD_NO_DEDUP/" ${actconfig}.post > ${actconfig}

	grep '^#export ADHD_NO_DEDUP' ${actconfig}
	confirm 'ADHD Shutdown'
	echo 'Shutting down ADHD.....'
	perl /act/etc/msgtool.pl shutdown

	#Grab the the last adhd log entry time and convert to epoch.
	#This is so we do not match previous 'open for business' entries.
	#epoch=$(tail -1 adhd.log \
	#	| grep -oE "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}" \
	#	| read time ; date --date="${time}" +%s)
	
    # Call monitor_adhd_startup()
	monitor_adhd_startup
	echo 'Node status.....'
	lsnode
	
	confirm "continue"
	

}

function monitor_adhd_startup() {
	#Grab the the last adhd log entry time.
	#This is so we do not match on previous 'open for business' entries.
	time=$(tail -1 ${adhdlog} | \
		grep -oE "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}.[0-9]{3}")
    echo "ADHD TIME = ${time}"
	# Wait for adhd to shutdown
	while true ; do
		grep --after-context=$(cat ${adhdlog} | wc -l) "${time}" "${adhdlog}" \
			|grep -i "open for business. dedup_disabled=0"
		[ $? == 0 ] && { echo 'ADHD, Open For Business'; break; } || { echo -n "."; }
		sleep 10
	done

}

function monitor_adhd_shutdown() {
	#Grab the the last adhd log entry time.
	#This is so we do not match on previous 'open for business' entries.
	time=$(tail -1 ${adhdlog} | \
		grep -oE "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}.[0-9]{3}")
    echo "ADHD TIME = ${time}"
	# Wait for adhd to shutdown
	while true ; do
		grep --after-context=$(cat ${adhdlog} | wc -l) "${time}" "${adhdlog}" \
			|grep -i "open for business. dedup_disabled=1"
		[ $? == 0 ] && { echo 'ADHD, Closed for Business'; break; } || { echo -n "."; }
		sleep 10
	done

}


function monitor_adhd_status() {
	#Grab the the last adhd log entry time.
	#This is so we do not match on previous 'open for business' entries.
	echo
	echo "ADHD monitor press [q] to exit"
	
	grep -i "open for" ${adhdlog}
	
	time=$(tail -1 ${adhdlog} | \
		grep -oE "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}.[0-9]{3}")
    echo "ADHD TIME = ${time}"
	
	
	stty -echo -icanon time 0 min 0 # Don't wait when read the input
	while true ; do
		grep --after-context=$(cat ${adhdlog} | wc -l) "${time}" "${adhdlog}" \
			|grep -i "open for business. dedup_disabled=1"
		[ $? == 0 ] && { echo 'ADHD Closed for Business'; break; } || { echo -n "."; }
		grep --after-context=$(cat ${adhdlog} | wc -l) "${time}" "${adhdlog}" \
			|grep -i "open for business. dedup_disabled=0"
		[ $? == 0 ] && { echo 'ADHD Open for Business'; break; } || { echo -n "."; }
		sleep 10
		read key
		if [ "$key" == "q" ]; then break; fi # If [q] is hit, get out of the loop
	done
	stty sane # Come back to the classic behaviour
	menu

}


################################################################
# CDS Error Check Function

function cds_error_check() {
		finderr
	    dumperrlog
	    clearerrlog
	    finderr
	    sainfo lsservicestatus | grep err
}


################################################################
# CDS Upgrade Function

function cds_upgrade() {
	echo
	echo 'Copying CDS patch to /home/admin/upload'
	cp -p ${cdspatch} /home/admin/upload
	echo 'upload update (udstask uploadupdate)'
	udstask uploadupdate ${cdspatch}
	echo 'lsupdate (udsinfo lsupdate)'
	udsinfo lsupdate
	confirm 'CDS Install Update'
	chmod 755 /var/run/screen
	echo 'Running installupdate in screen mode'
	echo 'Use screen -r udsinstall from another terminal window to attach to session'
	screen -dmS udsinstall bash -c 'udstask installupdate'
	screen -ls
	echo "Patch log location = ${cdspatchlog}"
	echo -n 'Installing'
	sleep 5
	while true; do
		grep '+ exit 0' ${cdspatchlog}
		[ $? == 0 ] && { echo 'CDS Update Successful'; break; } || { echo -n "."; }
		sleep 5
	done

	echo 'CDS Version.....'
	udsinfo lsversion
	echo 'SVC Version.....'
	cat /compass/vrmf
	
	echo 'Waiting on ADHD to start'
	monitor_adhd_status

}


################################################################
# SVC Upgrade Function

function svc_upgrade() {
    echo "Copying ${svcupgrade} to /upgrade"
	cp ${svcupgrade} /upgrade
	
	#Check filess exist
	echo
	echo 'Checking files exist.....'
	for i in "${svcfiles[@]}" ; do
	[ -f "${i}" ] && { echo "Found ${i}"; } || { echo "File ${i} not found!" && exit; }
	done

	echo
	echo 'Node Status....'
	lsnode
	
	echo
	echo 'CPU Info.....'
	grep 'proc' /proc/cpuinfo	
	grep 'physical id' /proc/cpuinfo

	echo
	echo 'Cluster Manufacturer Info.....'
	lsnodevpd 2 |grep Intel

	echo
	sainfo lsservicestatus ACTCLU| grep 'node_error_count 0'
	[ $? == 0 ] && { echo 'No Errors Found CLU node'; }|| { echo 'Found Error on CLU node' ; confirm "continue"; } 

	echo
	echo "Executing pre-flight 1 of 3 ${svcpreflight}"
	#chmod 755 "${svcpreflight}"
	sh /dumps/upgrade-preflight.txt
	#$("${svcpreflight}")
	confirm "continue"

	echo
	echo 'Scheduler shutdown and final checks'
    echo 'Executing pre-flight 2 of 3'
    sh /dumps/upgrade-preflight.txt -p
	#sh "$(svcpreflight) -p"

	echo 'SAVE THE ABOVE FILE LOCALY'

	confirm 'SVC upgrade propper'

	echo 'The upgrade will usually follow the following sequence of events:'
	echo '		* Clu node will go down for upgrade first (but not always)'
	echo ' 		* Clu node will come back on line (15 - 20 minutes)'
	echo ' 		* A period of what appears to be non activity will follow (40 min)'
	echo ' 		* Note: do not view logs since this may interfere with upgrade'
	echo ' 		* The config node will eventually go down (20 mins)'
	echo '		* This will destroy this session and this scripts execution'
	echo '		* Monitor manually until node returns (ssh <config_node> uptime)from CLU node.'
	echo ' 		* Allow for 15 - 20 minutes for services to start'
	echo '		* Once complete execute this script once more and select post upgrade option.'
	confirm 'SVC upgrade continue'
    
    echo 'Executing pre-flight 3 of 3'
    sh /dumps/upgrade-preflight.txt -u
	#sh "$(svcpreflight) -u"

	echo 'Monitoring Upgrade Progress.....'
	while true; do
		clear
		lssoftwareupgradestatus
		lsnode
		echo
		echo
		echo 'CHECK FOR INCOMING SALESFORCE SEV1 ALERT CASE AND DELETE IT!'
		sleep 10
	done
}


################################################################
# Scheduler Start / Stop Function's

function scheduler_start() {
	confirm "Start Scheduler Services"
	udstask setparameter -param enablescheduler -value true
	udstask setparameter -param enableexpiration -value true
	service_status
	menu
}


function scheduler_stop() {
	confirm "Stop Scheduler Services"
	udstask setparameter -param enablescheduler -value false
	udstask setparameter -param enableexpiration -value false
	service_status
	menu
}

################################################################
# GC Enable / Disable Function's

function gc_enable() {
	confirm "Enable GC Services"
	udstask setgcschedule -type gc -disable false
    #echo
    #echo "Show GC schedule"
    #udsinfo getgcschedule -type gc
	service_status
	menu
}


function gc_disable() {
	confirm "Disable GC Services"
	udstask setgcschedule -type gc -disable true
    #echo
    #echo "Show GC schedule"
    #udsinfo getgcschedule -type gc
	service_status
	menu
}


################################################################
# Confirm Y/N Function

function confirm() {
	
	read -r -p "Proceed to ${1}? [y/N] " response
	if [[ $response =~ ^([yY][eE][sS]|[yY])$ ]]
	then
    	echo 'Continuing.... '
	else
    	echo 'Back to menu'
    	menu
	fi
}

################################################################
# HotFix Install Function

function hotfix() {

echo 'Check that the correct HotFxes are available and manually remove those that are not'
echo "${base}/${hotfixprefix}* ${hotfixupload}"
ls ${base}/${hotfixprefix}*
udsinfo lsupdate
confirm "continue HotFix install"
cp ${base}/${hotfixprefix}* ${hotfixupload}

for hf in $(ls ${hotfixprefix}*); do
	echo "Adding ${hf} to uploadupdate"
	udstask uploadupdate ${hf}
done

echo 'List of HotFixes marked for update'
udsinfo lsupdate
confirm "Continue to install HotFix's Proper"
echo 'Please note sometime not all updates get installed by the Actifio installer.'
echo 'If this is the case please manually execute <udstask installupdate>'
udstask installupdate 

for i in {1..20}
do
	echo "Executing <udsinfo lsupdate> $i of 20 times with 10 second delay"
    udsinfo lsupdate
    sleep 10
done

#confirm "execute <udstask installupdate> once more"
echo 'If after this point you still see HotFixes from the <udsinfo lsupdate> above'
echo 'consider executing <udstask installupdate> manually'

confirm "continue to main menu"
menu
	
}
################################################################
# Post Upgrade Function

function post_upgrade() {
	
	echo
	echo 'Performing Post Upgrade Checks and Configuration'
	udsinfo lscluster
	echo
	udsinfo lsversion
	echo
	cat /compass/vrmf
	echo
	lsnode
	
	echo
	cds_error_check
	
	#echo
	#echo "Enabling ADHD....."
	#enable_adhd
	
	#udstask setparameter -param enablescheduler -value true
	#udstask setparameter -param enableexpiration -value true
	#echo
    service_status

	#echo
	#echo "Enable GC schedule"    
    #udstask setgcschedule -type gc -disable false
    #echo
    #echo "Show GC schedule"
    #udsinfo getgcschedule -type gc
    
    echo
    echo 'Fix any broken SARG links'
    cd /act/bin/
    ls report* | \
    while read report; do 
    	ln -s /act/bin/$report /home/admin/adminbin/$report
	done
	
	echo
	echo "Setup config mail server"
	id=`/act/postgresql/bin/psql actdb act -Atc "select propvalue from configdata where propname='email.emailuser'"`
	udstask configemailserver -emailfrom $id
	
	echo 'Upgrade Completed'
	echo 'Please take the time to review the cluster for correct functionality'
	echo 'Open up the Actifio Desktop and ensure all looks as though it should'
	echo 'Use (udstask debug getTOTP) to extract temporary password key for UI'
	confirm 'menu'
	menu
	
}


################################################################
# Main

menu




