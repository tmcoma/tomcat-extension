function Publish-WAR {
	<#
	.SYNOPSIS
	Deploys a WAR file to remote linux-based Tomcat instance using SSH/SCP.

	.DESCRIPTION
	Shuts down the remote tomcat server, copies $file to remote server,
	then starts the server, searching for $SuccessString in $CatalinaHome/log/catalina.out 
	for $Timeout seconds.  If $SuccessString is not found, function will exit with a nonzero value.

	SSH Keys: You should use some kind of SSH agent to avoid having to re-type passwords, as
	there are multiple SSH/SCP connections that must be made throughtout this script.

	Start-SshAgent with Posh-Git works well, or Pageant with -ForcePutty.
	We cannot capture passwords and replay them in this script.  
    In VSTS, you can do this with the "Install SSH Keys" agent task.  In Jenkins Pipelines, you can use
	an sshagent block.

	This script will fail with an exception if:
	1. $SshUrl is invalid
	2. $File doesn't exist
	3. $Catalinahome isn't found on the remote server
	4. The WAR file fails to SCP
	5. We cannot write the target war file (presumably in webapps)

	A non-terminating error will be written if our start script fails or if an abnormal startup is
	detected (for example, if we don't find the SuccessString before Timeout.).

	A "succeeded with issues" status will be used if this script detects that tomcat is
	reporting a shutdown, but did not actually shut down.

	.PARAMETER File
	WAR file to be deployed.
	.PARAMETER SshUrl
	SSH target, as "username@hostname"
	.PARAMETER CatalinaHome
	CATALINA_HOME directory on remote server, e.g. "/usr/local/appservers/myorg/myapp"	
	.PARAMETER Timeout
	Number of seconds to watch $CatalinaHome/log/catalina.out for presence of $SuccessString.  Default is 60 seconds.
	.PARAMETER SuccessString
	SuccessString string to check catalina.out for to indicate success
	.PARAMETER ForceRestart
	Start the given instance even if it was initially shut down	
	.PARAMETER ForcePutty
	Use this if you are on Windows and have ssh/scp installed (for example, via git-bash or cygwin)
	and want this script to explicitly use pscp and putty (which must be on the path).
	.PARAMETER TargetFilename
	The name you want to use on the remote server.  For example, we may be installing 
	"my-app-SNAPSHOT-3.0.0.war" to "myapp.war". If not given, the original filename will be used. 
	.EXAMPLE
	Install-War -File inquiry.war -SshUrl tomcat@10.200.11.21 -CatalinaHome "/usr/local/appservers/my-app"

	.EXAMPLE
	Install-War -File inquiry.war -SshUrl tomcat@10.200.11.21 -CatalinaHome "/usr/local/appservers/my-app" -ForcePutty

	Use PLINK.EXE and PSCP.EXE on command line instead of ssh/scp.  If you have Pageant running with the
	keys for $(SshUrl), this will use the keys installed therein.

	#>
	[CmdletBinding(SupportsShouldProcess=$true)]
	param(
		[Parameter(Mandatory=$true)][System.IO.FileInfo]$File,
		[Parameter(Mandatory=$true)][string]$SshUrl,
		[Parameter(Mandatory=$true)][string]$CatalinaHome,
		[string]$TargetFilename=$File.Name,
		[string]$SuccessString,
		[int]$Timeout=60,
		[switch]$ForceRestart,
		[switch]$ForcePutty
	)

	$hasIssues=$false

	# Allow user to force use of PuTTY, which is useful when running locally if you have
	# ssh/scp installed but can't get ssh-add to work because you're in powershell here
	if( $ForcePutty ){
		Write-Verbose "Forcing use of PuTTY..."
		$scp = Get-Command pscp
		$ssh = Get-Command plink 
	 } else {
		# Find SSH and SCP Commands, preferring "ssh" and "scp" over "plink" and "pscp"
		foreach ($cmd in @("pscp", "scp") ) {
			if( Get-Command $cmd -ErrorAction SilentlyContinue) {
				$scp=$cmd
			}
		}
	 
		foreach ($cmd in @("plink", "ssh")) {
			if( Get-Command $cmd -ErrorAction SilentlyContinue) {
				$ssh=$cmd
			}
		}
	}

	# verify that our ssh url is valid looking (specifically, make sure there's a username)
	if ( ! ($SshUrl -match "\w+@\w+") ){
		throw "'$SshUrl' does not appear to be a valid SSH url.  We were expecting user@hostname."
	}

	# verify that $file exists
	if(($File -eq $null) -Or !($File.exists)){
		throw "File '$File' not found!"
	}

	# if no target specified, use the original filename
	if ([string]::IsNullOrEmpty($TargetFilename)){
		$TargetFilename = $File.Name
	}

	# if we forget the ".war" extension, things get messy
	if ( !($TargetFilename.endsWith('war', 1)) ){
		Write-Error "TargetFilename '$TargetFilename' should end with .war"
	}

	# explicitly verify that $CatalinaHome exists and fail immediately if it doesn't
	# do this regardless of whether or not this is a dry run, since it doesn't
	# change the output on the other side
	Write-Verbose "Verifying CATALINA_HOME ${sshUrl}:$CatalinaHome ..."
	& $ssh $sshUrl "[ -d $CatalinaHome/webapps ] || exit 200"
	if($LASTEXITCODE -eq 200){
		throw "($LASTEXITCODE) '$CatalinaHome' does not appear to be a valid CATALINA_HOME"
	} elseif ($LASTEXITCODE -ne 0) {
		throw "($LASTEXITCODE) ssh to ${SshUrl} failed"
	}	

	# "mv" is POSIX atomic, but scp is not, so we copy the file to a temp place first
	# copy the war file to the remote server; fail hard here if this doesn't work
	$tmp="/tmp/$(Get-Random).war"
	if($PSCmdlet.ShouldProcess("${SshUrl}:$CatalinaHome/webapps", "copy $file")){
		& $scp $File.FullName "${SshUrl}:$tmp"
		if($LASTEXITCODE -ne 0){
			throw "($LASTEXITCODE) scp to ${SshUrl} failed"
		}
	}

	# shut down this tomcat if it's running, rely on the exit code of the
	# shutdown script to tell us if tomcat was previously running
	$shutdownCmd="$CatalinaHome/bin/shutdown.sh 2>&1"
	[boolean]$shutdownSuccess=$null
	if($PSCmdlet.ShouldProcess("${SshUrl}:$CatalinaHome", "shutdown")){
		Write-Output "Shutting down tomcat..."
		$output = & $ssh $SshUrl $shutdownCmd
		Write-Output $output
		Write-Output "Shutdown script complete."

		if($LASTEXITCODE -ne 0){
			# apps which weren't running will fail to shut down, which shouldn't fail the deploy,
			# but it's something we want to know about because it might not be what's expected
			$shutdownSuccess = $false
			Write-Warning "$output"
			Write-Output "($LASTEXITCODE) ${SshUrl}: $shutdownCmd failed with code $LASTEXITCODE"
		} else {
			$shutdownSuccess = $true
			Write-Output "$shutdownCmd completed with exit code $LASTEXITCODE..."
		}

		# make sure tomcat actually shut down.
		# if it didn't, write an error back and change status so we "succeed with issues"
		# the trailing newline entries are required for this script to run
		$statusScript=@"
if  ps aux | grep -v grep | grep 'catalina.base=$CatalinaHome.*Bootstrap start'; then`n
	echo '##vso[task.logissue type=error]After shutdown, tomcat still running from $CatalinaHome';`n
	exit 55;`n
fi`n
"@
		& $ssh $SshUrl ($statusScript -replace '\r','')
		if($LASTEXITCODE -eq 55){
			$hasIssues=$true
		}
	}

	# do the (atomic) move from the tmp file we placed here before shutdown
	$TargetLocation="$CatalinaHome/webapps/$TargetFilename"
	if($PSCmdlet.ShouldProcess("${SshUrl}:$TargetLocation", "move $($File.Name)")){
		# it is very confusing if the target location is a directory because this will just
		# move the file into that dir!  we don't want to ever do that, so fail if $TargetLocation 
		# is a directory
		& $ssh $SshUrl "if [ ! -d '$TargetLocation' ]; then mv '$tmp' '$TargetLocation'; else echo '$TargetLocation is a directory!' >&2; exit 100; fi"
		if($LASTEXITCODE -ne 0){
			throw "($LASTEXITCODE) Remote move command failed with code $LASTEXITCODE"
		}
	}

	# restart tomcat if it was running before, otherwise just leave it shutdown
	# if -ForceRestart was used, then start regardless of whether or not
	# shutdown was clean
	if($PSCmdlet.ShouldProcess("${SshUrl}:$TargetLocation", "startup.sh")){
		if ($shutdownSuccess -or $ForceRestart) {
			# start tomcat, monitor log file, and look for "Success String"
			$startScript = New-TomcatDeployScript -CatalinaHome $CatalinaHome -Timeout $Timeout -SuccessString $SuccessString
			Publish-SshScript -SshUrl $SshUrl -Script $startScript -ForcePutty:$ForcePutty
		} else {
			Write-Output "Tomcat was not shut down cleanly and will not be restarted."
		}

		if ($hasIssues){
			Write-Output "##vso[task.complete result=SucceededWithIssues]"
		}
	}
}

function New-TomcatStatusScript {
	<#
	.SYNOPSIS 
	Performs a heavy-handed check to see if tomcat is running
	.PARAMETER CatalinaHome
	#>
	[CmdletBinding()]
	param(
		[Parameter(Position=1,Mandatory=$true)][string]$CatalinaHome
	)

	return $script
}

function New-TomcatDeployScript {
	<#
	.SYNOPSIS
	Makes a bash script which will start a tomcat instance and check its output for success. 
	.PARAMETER CatalinaHome
	CATALINA_HOME on remote linux server that will be started and monitored.
	.PARAMETER SuccessString
	String to check for in $CatalinaHome/log/catalina.out.  Presence of this string
	indicates success.  Otherwise, function will return nonzero value.

	If no $SuccessString is passed, log file will be tailed but success will be assumed.
	.PARAMETER Timeout
	Number of seconds to check for $SuccessString in $Catalinahome/log/catalina.out.
	Passing 0 will bypass any checking of catalina.out.  Defaults to 60.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Position=1,Mandatory=$true)][string]$CatalinaHome,
		[string]$SuccessString,
		[int]$Timeout=60
	)

	$startupAndTail = "#!/bin/bash"	
	$startupAndTail = "################# Built $(date) #####################`n"
	$startupAndTail += "TIMEOUT=$Timeout`n"
	$startupAndTail += "SUCCESS_STR='$SuccessString'`n"
	$startupAndTail += "MY_CATALINA_BASE='$CatalinaHome'`n"

	# if there's a timeout, then we want to monitor the file; otherwise we just start the script
	# and move on immediately
	if($Timeout -gt 0){	
		Write-Verbose "Timeout is $timeout, including success check in deploy script..."
		$startupAndTail +=
@'
# This script will check the log file identified by $LOG
# for the string in $SUCCESS_STR.  If the string isn't found after
# $TIMEOUT seconds, then the script will exit with a nonzero 
# result.  Otherwise exits with a normal result (0).

LOG="$MY_CATALINA_BASE/logs/catalina.out"

## check $LOG for $SUCCESS_STR every second, until $TIMEOUT seconds have elapsed
check_success(){
	start_from="$(($(wc -l $LOG | awk '{print $1}') + 1))"
	for i in `seq 1 $TIMEOUT`; do
		if [ -z "$SUCCESS_STR" ]; then
			# NOP, we're just waiting for the timeout to elapse and won't
			# shortcut success because we're not searching for anything
			:
		elif $(tail -n +"$start_from" "$LOG" | grep -q "$SUCCESS_STR" ) ; then
			echo "'$SUCCESS_STR' found in $LOG!"
			return 0
		fi
		sleep 1
	done
	
	# if we're not checking a status string, just letting this tail while TIMEOUT
	# elapses, then we're just assuming that things succeeded
	if [ -z "$SUCCESS_STR" ]; then
		return 0
	else 
		echo "##vso[task.logissue type=error]'$SUCCESS_STR' not found in $LOG after $TIMEOUT seconds.  Assuming abnormal startup."
		return 10
	fi
}

## Start tomcat
($MY_CATALINA_BASE/bin/startup.sh)
if [ $? -ne 0 ]; then
	# startup was aborted, either because of a pid file issue
	# or a port conflict issue; don't tail, just bail
	echo "##vso[task.logissue type=error]$MY_CATALINA_BASE/bin/startup.sh failed"
	exit 66
fi

## show the log on the terminal, which might help with debugging
tail -f "$LOG" &

## poll, store the return val
check_success
result=$?

# the backgrounded tail job needs to exit for this term to exit
kill %1

exit $result
'@
	} else {
		Write-Verbose "Timeout is $Timeout, excluding success check from deploy script..."
	}

	# dos2unix this string 
	return $startupAndTail -replace "`r`n" ,"`n"
}

function Publish-SshScript {
	<#
	.SYNOPSIS
	Runs a script remotely, by copying it to a file then executing the file.
	.DESCRIPTION
	This function is meant to elimiate variable-expansion and escaping issues that occur when attempting run 
	remote scripts using "ssh username@host <script>" syntax.  Message will be written to the Error 
	Stream if the remote script exits with a nonzero exit code.
	.PARAMETER SshUrl
	SSH target, as "username@hostname"
	.PARAMETER Script 
	Value of the script you wish to run remotely. 
	.PARAMETER ForcePutty
	Use this if you are on Windows and have ssh/scp installed (for example, via git-bash or cygwin)
	and want this script to explicitly use pscp and putty (which must be on the path).
	.NOTES
	In PowerShell, all non-captured output is returned from a function.  In this case, we don't capture
	any of the output from ssh/plink/scp/pscp, so it all goes onto the Success Stream.
	#>
	[CmdletBinding(SupportsShouldProcess=$true)]
	param(
		[Parameter(Mandatory=$true)][string]$SshUrl,
		[Parameter(Mandatory=$true)][string]$Script,
		[switch]$ForcePutty
	)

	# Allow user to force use of PuTTY, which is useful when running locally if you have
	# ssh/scp installed but can't get ssh-add to work because you're in powershell here
	if( $ForcePutty ){
		Write-Verbose "Forcing use of PuTTY..."
		$scp = Get-Command pscp
		$ssh = Get-Command plink 
	 } else {
		# Find SSH and SCP Commands, preferring "ssh" and "scp" over "plink" and "pscp"
		foreach ($cmd in @("pscp", "scp") ) {
			if( Get-Command $cmd -ErrorAction SilentlyContinue) {
				$scp=$cmd
			}
		}
	 
		foreach ($cmd in @("plink", "ssh")) {
			if( Get-Command $cmd -ErrorAction SilentlyContinue) {
				$ssh=$cmd
			}
		}
	}
	
	$tmpFile=".tmp-$(Get-Random).sh"

	# write the script to a tmp file, copy it to remote server
	Write-Verbose "Writing script contents to $tmpFile..."
	$Script | Set-Content -NoNewLine $tmpFile

	# scp the file over
	Write-Verbose "Copying to ${SshUrl}:/tmp/$tmpFile..."
	if($PSCmdlet.ShouldProcess("${SshUrl}:/tmp/$tmpFile", "scp")){
		& $scp $tmpFile "${SshUrl}:/tmp"
	}

	# local cleanup
	Write-Verbose "Removing local $tmpFile..."
	if($PSCmdlet.ShouldProcess("$tmpFile", "delete")){
		# set-content won't have created a file if we're doing whatif, but
		# this command will fail, so we have to explicitly check ShouldProcess on it
		Remove-Item $tmpFile
	}

	# run the script and capture its result (to be returned from this function)
	# output non-terminating (Write-Error) error if remote script exits with nonzero value
	Write-Verbose "Running remote ${sshUrl}:/tmp/$tmpFile..."
	if($PSCmdlet.ShouldProcess("${SshUrl}:/tmp/$tmpFile", "execute")){
		& $ssh $SshUrl "chmod +x '/tmp/$tmpFile' && /tmp/'$tmpFile'" 
		if ($LASTEXITCODE -ne 0){
			Write-Error "/tmp/'$tmpFile' terminated with code $LASTEXITCODE"
		}
	}
	
	# remote cleanup; this is deliberately a separate ssh call
	Write-Verbose "Cleaning up remote ${sshUrl}:/tmp/$tmpFile..."
	if($PSCmdlet.ShouldProcess("${SshUrl}:/tmp/$tmpFile", "remove")){
		& $ssh $SshUrl "rm /tmp/'$tmpFile'"
		if ($LASTEXITCODE -ne 0){
			Write-Warning "Failed to delete /tmp/'$tmpFile'"
		}	
	}
}

Export-ModuleMember New-TomcatDeployScript
Export-ModuleMember Publish-War
Export-ModuleMember Publish-SshScript