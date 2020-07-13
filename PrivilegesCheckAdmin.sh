#!/bin/bash

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# This script is designed to be run in conjunction with a Privileges LaunchDaemon to allow 
# a specific user from using the Privileges.app to promote themselves
#
# - Relies on a configuration profile that uses an extension attribute to LimitToUser
# - Queries the user allowed from an extension attribute set
# - Sets a timer (default 20 minutes) to automatically demote a user back to standard
# - Removes the User from the admin group via the Privileges CLI
# - Optional: Jamf administrator can change the default time limit
# - Optional: Logs the actions taken by a user to local folder
# - Optional: Jamf administrator can use a custom trigger to kick off another policy, potentially for log collection
# 
# #
# Written by: Jennifer Johnson
# Original concept drawn from: TravelingTechGuy (https://github.com/TravellingTechGuy/privileges)
# and Krypted (https://github.com/jamf/MakeMeAnAdmin) 
# and soundsnw (https://github.com/soundsnw/mac-sysadmin-resources/tree/master/scripts)
#
# Privileges.app was originally developed by SAP - 
# Privileges.app Project Page:  https://github.com/SAP/macOS-enterprise-privileges
#
# Version: 1.3
# Date: 6/16/20 
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
DebugLogs="/private/var/log/privilegesout.log"


# If time limit before admin is promoted isn't set, then use default time of 20 minutes.  If this is not set, it will grep as None
if [[ $privilegesMinutes = "None" ]]; then

    #echo "Admin timeout not specified, using default of 20 minutes"
    privilegesMinutes=20

fi

# If user is not specified in configuration profile (e.g. it is blank), then we don't care what user is logged in. 
# We don't want to use the currently logged in user, in case it doesn't match what was set in the configuration profile because it may set user account that is admin to a standard account
if [[ $loggedInUser = "None" ]]; then

#   echo "User not specified from configuration profile."
	exit 0

fi

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
	
 	echo "File ${logFile} does NOT exist"
 	# Create a directory to drop collect logs
	mkdir -p "/private/var/privileges/${loggedInUser}_${DATE}/"
  	touch $logFile
 	echo $timeStamp > $logFile
  	# Setup an initial time stamp when Privileges was launched. It will be used to determine how long a user has been promoted to admin.
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
    rm $DebugLogs
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

    # Demote the user using PrivilegesCLI  
	sudo -u $loggedInUser /Applications/Privileges.app/Contents/Resources/PrivilegesCLI --remove

	# Use JamfHelper to let user know admin has been removed via dialog box.
	/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType hud -icon /Applications/Privileges.app/Contents/Resources/AppIcon.icns -title "Privileges" -heading "Administrator Access" -description "Over $privilegesMinutes minutes has passed. Admin privileges have been removed." -button1 "OK" 

    # Make sure timestamp file is not present
    mv -vf /usr/local/tatime /usr/local/tatime.old
    rm $logFile

	# Pull logs of what the user did during the time they were allowed admin rights.
	if [[ $LocalLogging = "true" ]]; then

		log collect --last "$privilegesMinutes"m --output /private/var/privileges/${loggedInUser}_${DATE}/$setTimeStamp.logarchive
		echo "Log files are collected in /private/var/privileges/"
		# Give it some time to archive the logs before moving on
		sleep 30
	
	fi
	
	# Send a custom Jamf trigger to a policy so we know someone used Privileges successfully, if configured.
	if [[ $CustomTrigger != "None" ]]; then

		/usr/local/jamf/bin/jamf policy -event "$CustomTrigger"

	fi

   	# Cleanup any old logs left over from running this script, if they're still there.
	if  [[ -e "$DebugLogs" ]]; then
		
		rm $DebugLogs

	fi

fi

exit 0