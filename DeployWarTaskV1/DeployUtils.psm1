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
		@("pscp", "scp") |% {
			if( Get-Command $_ -ErrorAction SilentlyContinue) {
				$scp=$_
			}
		}
	 
		@("plink", "ssh") |% {
			if( Get-Command $_ -ErrorAction SilentlyContinue) {
				$ssh=$_
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

	# if we forget the ".war" extension, things get messy
	if ( !($TargetFilename.endsWith('war', 1)) ){
		Write-Error "TargetFilename '$TargetFilename' should end with .war"
	}

	# explicitly verify that $CatalinaHome exists and fail immediately if it doesn't
	if($PSCmdlet.ShouldProcess("${SshUrl}:$CatalinaHome", "verify CATALINA_HOME")){
		Write-Verbose "Verifying CATALINA_HOME ${sshUrl}:$CatalinaHome ..."
		& $ssh $sshUrl "[ -d $CatalinaHome/webapps ] || exit 200"
		if($LASTEXITCODE -eq 200){
			throw "($LASTEXITCODE) '$CatalinaHome' does not appear to be a valid CATALINA_HOME"
		} elseif ($LASTEXITCODE -ne 0) {
			throw "($LASTEXITCODE) Failed to test remote server"
		}	
	}

	# "mv" is POSIX atomic, but scp is not, so we copy the file to a temp place first
	# copy the war file to the remote server; fail hard here if this doesn't work
	$tmp="/tmp/$(Get-Random).war"
	if($PSCmdlet.ShouldProcess("${SshUrl}:$CatalinaHome/webapps", "copy $file")){
		& $scp $File.FullName "${SshUrl}:$tmp"
		if($LASTEXITCODE -ne 0){
			throw "Failed to scp war to remote server!"
		}
	}

	# shutdown tomcat	
	$shutdownCmd="$CatalinaHome/bin/shutdown.sh"
	if($PSCmdlet.ShouldProcess("${SshUrl}:$CatalinaHome", "shutdown")){
		$shutdownOutput = & $ssh $SshUrl $shutdownCmd
		if($LASTEXITCODE -ne 0){
			# apps which weren't running will fail to shut down, which is ok, but 
			# usually this means something abnormal happened, so write a warning
			Write-Warning $shutdownOutput
			Write-Warning "${SshUrl}: $shutdownCmd failed with code $LASTEXITCODE"
		} else {
			Write-Output $shutdownOutput
			Write-Output "$shutdownCmd completed with exit code $LASTEXITCODE..."
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
			throw "Remote move command failed with code $LASTEXITCODE"
		}
	}
	
	# start tomcat, monitor log file, and look for "Success String"
	$startScript = New-TomcatDeployScript -CatalinaHome $CatalinaHome -Timeout $Timeout -SuccessString $SuccessString
	Publish-SshScript -SshUrl $SshUrl -Script $startScript -ForcePutty:$ForcePutty
}

function New-TomcatDeployScript {
	<#
	.SYNOPSIS
	Makes a bash script which will start a tomcat instance and check its output for succsess. 
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
	[CmdletBinding(SupportsShouldProcess=$true)]
	param(
		[Parameter(Position=1,Mandatory=$true)][string]$CatalinaHome,
		[string]$SuccessString,
		[int]$Timeout=60
	)

	$startupAndTail = "#!/bin/bash"	
	$startupAndTail = "################# Built $(date) #####################`n"
	$startupAndTail += "TIMEOUT=$Timeout`n"
	$startupAndTail += "SUCCESS_STR='$SuccessString'`n"
	$startupAndTail += "LOG='$CatalinaHome/logs/catalina.out'`n"
	$startupAndTail += "($CatalinaHome/bin/startup.sh)`n"

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
		echo "'$SUCCESS_STR' not found in $LOG after $TIMEOUT seconds.  Assuming abnormal startup."
		return 10
	fi
}

## show the log on the terminal, which might help with debugging
tail -f "$LOG" &

## poll, store the return val
check_success
result=$?

# the backgrounded tail job needs to exit for this term to exit
kill %1

echo "Exiting with result $result..."
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
	# default to success, but we will inherit the LASTEXITCODE of ssh, which will be the
	# exit code of the remote script we're running
	$exitCode=0 

	# Allow user to force use of PuTTY, which is useful when running locally if you have
	# ssh/scp installed but can't get ssh-add to work because you're in powershell here
	if( $ForcePutty ){
		Write-Verbose "Forcing use of PuTTY..."
		$scp = Get-Command pscp
		$ssh = Get-Command plink 
	 } else {
		# Find SSH and SCP Commands, preferring "ssh" and "scp" over "plink" and "pscp"
		@("pscp", "scp") |% {
			if( Get-Command $_ -ErrorAction SilentlyContinue) {
				$scp=$_
			}
		}
	 
		@("plink", "ssh") |% {
			if( Get-Command $_ -ErrorAction SilentlyContinue) {
				$ssh=$_
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
	
	# remote cleanup
	Write-Verbose "Cleaning up remote ${sshUrl}:/tmp/$tmpFile..."
	if($PSCmdlet.ShouldProcess("${SshUrl}:/tmp/$tmpFile", "remove")){
		& $ssh $SshUrl "rm /tmp/'$tmpFile'"
		if ($LASTEXITCODE -ne 0){
			Write-Warning "Failed to delete /tmp/'$tmpFile'"
		}	
	}
}

Export-ModuleMember Publish-War
Export-ModuleMember Publish-SshScript

