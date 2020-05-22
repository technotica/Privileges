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
# and soundsnw (https://github.com/soundsnw/mac-sysadmin-resources/tree/master/scripts)
#
# Version: 0.1
# Date: 5/19/20 
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 


# Set date for the logs, this can be modified as dd.mm.yyyy or dd-mm-yyy
DATE=$(/bin/date +"%d.%m.%Y")

# Determine user allowed to use Privileges from configuration profile.
loggedInUser=$(python -c "from Foundation import CFPreferencesCopyAppValue; print CFPreferencesCopyAppValue('LimitToUser', 'corp.sap.privileges')")

# Indicate how long a user should have admin via Privileges.app, in minutes. Time Limit can set set via custom plist used in a configuration profile.
privilegesMinutes=$(python -c "from Foundation import CFPreferencesCopyAppValue; print CFPreferencesCopyAppValue('TimeLimit', 'edu.iastate.demote.privileges')")

# Determine if Local logging enabled from configuration profile
LocalLogging=$(python -c "from Foundation import CFPreferencesCopyAppValue; print CFPreferencesCopyAppValue('EnableLocalLog', 'edu.iastate.demote.privileges')")

# If time limit before admin is promoted isn't set, then use default time of 20 minutes
if [[ -z "$privilegesMinutes" ]]; then

    echo "Admin timeout not specified, using default of 20 minutes"
    privilegesMinutes=20

fi

# Set log file location
logFile="/private/var/privileges/${loggedInUser}_${DATE}/.lastAdminCheck.txt"
timeStamp=$(date +%s)

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

# If User is not specified from configuration profile and is set to blank, exit quietly
 if [[ -z "$loggedInUser" ]]; then
#   # Otherwise grab the currently logged in user instead
	loggedInUser=$(/usr/bin/python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");')
    echo "User $loggedInUser is logged in."
#    # User shouldn't be able to promote themselves using Privileges.app.  Something horrible happened.  Give the user a prompt to let them know admin has been removed.
#	 /usr/local/bin/jamf displayMessage -message "You shouldn't have been able to do this. Admin privileges have been revoked."
#    sudo -u $loggedInUser /Applications/Privileges.app/Contents/Resources/PrivilegesCLI --remove
   exit 0
fi

# If user is a standard user, exit quietly
if [[ $("/usr/sbin/dseditgroup" -o checkmember -m $loggedInUser admin / 2>&1) =~ "yes" ]]; then
#if dseditgroup -o checkmember -m "$LoggedInUser" admin; then
	echo "$loggedInUser is an admin."
else
	echo "$loggedInUser is a standard user."
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
echo "Unix time when admin was given: ""$setTimeStamp"

# Seconds since user was promoted
timeSinceAdmin="$((currentEpoch - setTimeStamp))"
echo "Seconds since admin was given: ""$timeSinceAdmin"

# Privileges timeout in seconds
privilegesSeconds="$((privilegesMinutes * 60))"

# If timestamp exists and the specified time has passed, remove admin
if [[ -e /usr/local/tatime ]] && [[ (( timeSinceAdmin -gt privilegesSeconds )) ]]; then

    echo ""$privilegesMinutes" minutes have passed, removing admin privileges for $loggedInUser"
    # Give the user a prompt to let them know admin has been removed.
	/usr/local/bin/jamf displayMessage -message "Over $privilegesMinutes minutes has passed. Admin privileges have been removed."
	# Demote the user using PrivilegesCLI  
	sudo -u $loggedInUser /Applications/Privileges.app/Contents/Resources/PrivilegesCLI --remove

	# Pull logs of what the user did. Change 20m (20 minutes) to desired time frame if specified.
	if [["$LocalLogging"=True]]; then

			log collect --last 20m --output /private/var/privileges/${loggedInUser}_${DATE}/$setTimeStamp.logarchive
			echo "Log files are collected in /private/var/privileges/${loggedInUser}_${DATE}/"
	
	fi
    # Make sure timestamp file is not present
    mv -vf /usr/local/tatime /usr/local/tatime.old
    rm $logFile

fi

exit 0