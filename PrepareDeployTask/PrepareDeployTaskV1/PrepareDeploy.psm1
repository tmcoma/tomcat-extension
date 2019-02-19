function Initialize-Deploy {
	<#
	.SYNOPSIS
	Prepares a pipeline to deploy tomcat by shutting the instance down and staging files.

	.DESCRIPTION
	Shuts down the remote tomcat server, copies $file to remote server,

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
	.PARAMETER TargetFilename
	The name you want to use on the remote server.  For example, we may be installing 
	"my-app-SNAPSHOT-3.0.0.war" to "myapp.war". If not given, the original filename will be used. 
	.PARAMETER IgnoreHostKey
	Same as sets StrictHostKeyChecking=no when calling scp and ssh.

	#>
	[CmdletBinding(SupportsShouldProcess=$true)]
	param(
		[Parameter(Mandatory=$true)][string]$File,
		[Parameter(Mandatory=$true)][string]$SshUrl,
		[Parameter(Mandatory=$true)][string]$CatalinaHome,
		[string]$TargetFilename,
		[string]$SuccessString,
		[switch]$IgnoreHostKey
	)


	if($IgnoreHostKey){
		$sshOpts = @( "-o", "StrictHostKeyChecking=no")
	} 

	# verify that our ssh url is valid looking (specifically, make sure there's a username)
	if ( ! ($SshUrl -match "\w+@\w+") ){
		throw "'$SshUrl' does not appear to be a valid SSH url.  We were expecting user@hostname."
	}

	# verify that $file exists
	if(!(Test-Path $File)) {
		throw "File '$File' not found!"
	}

	# if no target specified, use the original filename
	if ([string]::IsNullOrEmpty($TargetFilename)){
		$TargetFilename = (Get-ChildItem $File).Name
	}

	# if we forget the ".war" extension, things get messy
	if ( !($TargetFilename.endsWith('war', 1)) ){
		Write-Error "TargetFilename '$TargetFilename' should end with .war"
	}
	$TargetLocation="$CatalinaHome/webapps/$TargetFilename"

	# explicitly verify that $CatalinaHome exists and fail immediately if it doesn't
	# do this regardless of whether or not this is a dry run, since it doesn't
	# change the output on the other side
	Write-Verbose "Verifying CATALINA_HOME ${sshUrl}:$CatalinaHome ..."
	ssh @sshOpts $sshUrl "[ -d `"$CatalinaHome`"/webapps ] || exit 200"
	if($LASTEXITCODE -eq 200){
		throw "($LASTEXITCODE) '$CatalinaHome' does not appear to be a valid CATALINA_HOME"
	} elseif ($LASTEXITCODE -ne 0) {
		throw "($LASTEXITCODE) ssh to ${SshUrl} failed"
	} else {
		Write-Output "$CatalinaHome looks ok..."
	}

	# copy the file to a temp place first and use mv to get it into place, 
	# because mv is POSIX atomic and works better when we're deploying 
	# without a shutdown/startup cycle
	# copy the war file to the remote server; fail hard here if this doesn't work
	$tmp="/tmp/$(Get-Random).war"
	if($PSCmdlet.ShouldProcess("${SshUrl}:$CatalinaHome/webapps", "copy $file")){
		Write-Output "Creating $SshUrl`:$tmp..."
		scp @sshOpts (Get-ChildItem $File).FullName "${SshUrl}:$tmp"
		if($LASTEXITCODE -ne 0){
			throw "($LASTEXITCODE) scp to ${SshUrl} failed"
		}
	}

	# shut down this tomcat if it's running, rely on the exit code of the
	# shutdown script to tell us if tomcat was previously running
	# once tomcat is shutdown, forcefully remove the directory which corresponds to the
	# war file we're deploying, if it exists
	[boolean]$shutdownSuccess=$null
	if($PSCmdlet.ShouldProcess("${SshUrl}:$CatalinaHome", "shutdown and remove exploded dir")){
		$explodedAppDir="$CatalinaHome/webapps/" + [io.path]::GetFilenameWithoutExtension($TargetLocation)
		$output = ssh $SshUrl (@"
echo "[`$(hostname)] Shutting Down $CatalinaHome..."
"$CatalinaHome"/bin/shutdown.sh 2>&1
shutdownCode=$?

if [ -d "$explodedAppDir" ]; then
		echo "[`$(hostname)] Removing exploded dir $explodedAppDir..."
		rm -rf "$explodedAppDir"
		if [ `$? -eq 0 ]; then
			echo "[`$(hostname)] Successfully removed $explodedAppDir"
		else
			echo "[`$(hostname)] Failed to remove $explodedAppDir" >&2
			exit 15
		fi
else
		echo "[`$(hostname)] $explodedAppDir not found."  
fi
exit $shutdownCode
"@  -replace "`r","")

		if($LASTEXITCODE -eq 15){
			# if this script can't remove the exploded directory, then 
			# tomcat won't be able to do any better when it starts, so we should fail the deploy
			# now
			Write-Warning "$output"
			throw "($LASTEXITCODE) ${SshUrl}: Failed to remove $explodedAppDir"
		} elseif ($LASTEXITCODE -ne 0) {
			# apps which weren't running will fail to shut down, which shouldn't fail the deploy,
			# but it's something we want to know about because it might not be what's expected
			$shutdownSuccess = $false
			Write-Warning "$output"
			Write-Output "($LASTEXITCODE) ${SshUrl}: shutdown failed with code $LASTEXITCODE"
		} else {
			Write-Output $output
			$shutdownSuccess = $true
		}

		# make sure tomcat actually shut down.
		# if it didn't, write an error back and change status so we "succeed with issues"
		# the trailing newline entries are required for this script to run
		$statusScript=@"
if  ps aux | grep -v grep | grep 'catalina.base=$CatalinaHome.*Bootstrap start'; then`n
	echo '##vso[task.logissue type=error] [`$(hostname)]After shutdown, tomcat still running from $CatalinaHome';`n
	exit 55;`n
fi`n
"@
		ssh @sshOpts $SshUrl ($statusScript -replace '\r','')
	}
}

