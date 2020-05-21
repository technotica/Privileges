#!/bin/bash

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# This script is designed to be run in conjunction with a Privileges LaunchDaemon to demote 
# a specific user from using the Privileges.app to promote themselves
# - Queries a User attribute set as an extension attribute
# - Sets a timer (20 minutes)
# - Logs the actions taken by a user (to be used by future syslog server)
# - Removes the User from the admin group via the Privileges CLI
# #
# Written by: Jennifer Johnson
# Original concept drawn from:  TravelingTechGuy (https://github.com/TravellingTechGuy/privileges)
# and Krypted (https://github.com/jamf/MakeMeAnAdmin)
#
# Version: 0.1
# Date: 5/19/20 
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 


# Indicate how long a user should have admin via Privileges.app, in minutes
# Make this a plist so it can be selected?
privilegesMinutes=5

# Set date for the logs, this can be modified as dd.mm.yyyy or dd-mm-yyy
DATE=$(/bin/date +"%d.%m.%Y")

# Check for presence of a log file 
logFile="/private/var/privileges/${loggedInUser}_${DATE}/.lastAdminCheck.txt"
timeStamp=$(date +%s)

#Read the User associated with being allowed to use Privileges.app
#sudo defaults read "Path to configuration profile that sets LimitToUser"
#"Set this variable to $AllowedUser"

# Grab the logged in user
loggedInUser=$(/usr/bin/python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");')
ed logs

# Check if log file exists and set 

if [ -f $logFile ]; then
 
	  echo "File ${logFile} exists."
		
else
 	echo "File ${logFile} does NOT exist"
 	# Create a directory to drop collect logs
	mkdir -p "/private/var/privileges/${loggedInUser}_${DATE}/"
  	touch $logFile
 	echo $timeStamp > $logFile
  	# Setup an intial time stamp when app launched, will be used to determine how long a user has been promoted to admin
  	echo "Creating admin timestamp"
  	touch "/usr/local/tatime"
	chmod 600 "/usr/local/tatime"  
	
fi	

# If no current user is logged in, exit quietly
if [[ -z "$loggedInUser" ]]; then
    echo "No user logged in, exiting"
    exit 0
fi


# If timestamp file is not present, exit quietly 
if [[ ! -e /usr/local/tatime ]]; then
    echo "No timestamp, exiting."
    exit 0
fi

# Get current Unix time
currentEpoch="$(date +%s)"
echo "Current Unix time: ""$currentEpoch"

# Get user promotion timestamp
setTimeStamp="$(stat -f%c /usr/local/tatime)"
echo "Unix time when admin was given: ""setTimeStamp"

# Seconds since user was promoted
timeSinceAdmin="$((currentEpoch - setTimeStamp))"
echo "Seconds since admin was given: ""$timeSinceAdmin"

privilegeSeconds="$((privilegeMinutes * 60))"

# If timestamp exists and the specified time has passed, remove admin

if [[ -e /usr/local/tatime ]] && [[ (( timeSinceAdmin -gt privilegeSeconds )) ]]; then

    echo ""$privilegesMinutes" have passed, removing admin"
	echo "Removing $loggedInUser's admin privileges"
	# Demote the user using PrivilegesCLI  
	sudo -u $loggedInUser /Applications/Privileges.app/Contents/Resources/PrivilegesCLI --remove
	# Pull logs of what the user did. 
	log collect --last 30m --output /private/var/privileges/${loggedInUser}_${DATE}/$loggedInUser-$setTimeStamp.logarchive
    # Make sure timestamp file is not present and run recon
    mv -vf /usr/local/tatime /usr/local/tatime.old
    /usr/local/jamf/bin/jamf recon

fi


exit 0