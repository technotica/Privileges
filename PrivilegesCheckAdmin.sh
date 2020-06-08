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
# Original concept drawn from: TravelingTechGuy (https://github.com/TravellingTechGuy/privileges)
# and Krypted (https://github.com/jamf/MakeMeAnAdmin) 
# and soundsnw (https://github.com/soundsnw/mac-sysadmin-resources/tree/master/scripts)
#
# Version: 1.1
# Date: 6/8/20 
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 


# Set date for the logs, this can be modified as dd.mm.yyyy or dd-mm-yyy
DATE=$(/bin/date +"%d.%m.%Y")

# Determine user allowed to use Privileges from configuration profile. IF nothing found, returns "None"
loggedInUser=$(python -c "from Foundation import CFPreferencesCopyAppValue; print CFPreferencesCopyAppValue('LimitToUser', 'corp.sap.privileges')")

# Determine how long a user should have admin via Privileges.app, in minutes from configuration profile. If nothing found, returns "None"
privilegesMinutes=$(python -c "from Foundation import CFPreferencesCopyAppValue; print CFPreferencesCopyAppValue('TimeLimit', 'edu.iastate.demote.privileges')")

# Determine if local logging is enabled from configuration profile. If nothing found, returns "None"
LocalLogging=$(python -c "from Foundation import CFPreferencesCopyAppValue; print CFPreferencesCopyAppValue('EnableLocalLog', 'edu.iastate.demote.privileges')")

# Determine if Jamf custom trigger is set from configuration profile.  If nothing found, returns "None"
CustomTrigger=$(python -c "from Foundation import CFPreferencesCopyAppValue; print CFPreferencesCopyAppValue('CustomTrigger', 'edu.iastate.demote.privileges')")

# Set location of script logs for debugging
DebugLogs="/private/var/logs/privilegesout.log"


# If time limit before admin is promoted isn't set, then use default time of 20 minutes.  If this is not set, it will grep as None
#if [[ -z "$privilegesMinutes" ]]; then
if [[ $privilegesMinutes = "None" ]]; then

    #echo "Admin timeout not specified, using default of 20 minutes"
    privilegesMinutes=20

fi

# If user is not specified in configuration profile (e.g. it is blank), then we don't care what user is logged in. 
# We don't want to use the currently logged in user, in case it doesn't match what was set in the configuration profile because it may set user account that is admin to a standard account

# If user is not specified from configuration profile (e.g. it is blank) use the logged in user instead.
#if [[ -z "$loggedInUser" ]]; then
if [[ $loggedInUser = "None" ]]; then

#   echo "User not specified from configuration profile. $loggedInUser is logged in."
	exit 0

fi
# Otherwise grab the currently logged in user instead
# loggedInUser=$(/usr/bin/python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");')


# If no current user is logged in, exit quietly
#	if [[ -z "$loggedInUser" ]]; then
#	echo "No user is logged in."	
#   exit 0
#	fi

#fi

# If user an admin or standard.  If standard user, exit quietly
if [[ $("/usr/sbin/dseditgroup" -o checkmember -m $loggedInUser admin / 2>&1) =~ "yes" ]]; then

	echo "$loggedInUser is an admin."
	userType="Admin"

else
	
	#echo "$loggedInUser is a standard user."
	userType="Standard"
	exit 0

fi

# Set log file location
logFile="/private/var/privileges/${loggedInUser}_${DATE}/.lastAdminCheck.txt"
timeStamp=$(date +%s)

# If log file is NOT present and user is promoted to admin, then create a log file and our time stamps for time calculations
if [[ ! -e "$logFile" ]] && [[ $userType = "Admin" ]]; then
	
	# Cleanup any old script logs left behind from last run, if still there.
	if  [[ -e "$DebugLogs" ]]; then
		
		rm $DebugLogs

	fi

 	echo "File ${logFile} does NOT exist"
 	# Create a directory to drop collect logs
	mkdir -p "/private/var/privileges/${loggedInUser}_${DATE}/"
  	touch $logFile
 	echo $timeStamp > $logFile
  	# Setup an initial time stamp when privileges was launched. It will be used to determine how long a user has been promoted to admin.
  	echo "Creating admin timestamp"
  	touch "/usr/local/tatime"
	chmod 600 "/usr/local/tatime"  

fi	

# Check if our logfile exists, e.g. it got created when a user was admin and if the user used Privileges to demote themselves manually.
# This will clear any of our timestamps and logs for better user experience next time the user launches Privileges.

if [[ -f "$logFile" ]] && [[ $userType = "Standard" ]]; then
 
 	echo "File ${logFile} does exist"
	# Make sure timestamp file is not present
    mv -vf /usr/local/tatime /usr/local/tatime.old
    rm $logFile
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

	# Use JamfHelper to let user know admin has been removed via dialog box.
	/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType hud -icon /Applications/Privileges.app/Contents/Resources/AppIcon.icns -title "Privileges" -heading "Administrator Access" -description "Over $privilegesMinutes minutes has passed. Admin privileges have been removed." -button1 "OK" 

	# Demote the user using PrivilegesCLI  
	sudo -u $loggedInUser /Applications/Privileges.app/Contents/Resources/PrivilegesCLI --remove

	# Pull logs of what the user did during the time they were allowed admin rights.
	if [[ $LocalLogging = "true" ]]; then

			log collect --last "$privilegesMinutes"m --output /private/var/privileges/${loggedInUser}_${DATE}/$setTimeStamp.logarchive
			echo "Log files are collected in /private/var/privileges/"
			# Give it some time to archive the logs before moving on
			sleep 30
	
	fi
	
	# Send a custom Jamf trigger to a policy so we know someone used Privileges successfully, if configured.
	if [[ $CustomTrigger !="None" ]]; then
	#if [[ ! -e "$CustomTrigger" ]]; then

		/usr/local/jamf/bin/jamf policy -event "$CustomTrigger"

	fi

    # Make sure timestamp file is not present
    mv -vf /usr/local/tatime /usr/local/tatime.old
    rm $logFile

fi

exit 0