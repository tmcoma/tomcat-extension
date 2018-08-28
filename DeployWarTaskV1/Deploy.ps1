<#
.SYNOPSIS
Deploys mef-admin-portal war file to a remote tomcat instance running
on Linux.

.DESCRIPTION
This script is meant to be run from a VSTS Powershell Release Step.

You can use this script in combination with the VSTS 'Install SSH Keys' task,
which will make ssh credentials available.

This script will also work from any PowerShell prompt.  See examples.

.PARAMETER CatalinaHome 
Location on linux server of Catalina directory

.PARAMETER WarFile 
Location of local war file to be deployed.  If not specified, script will recursively search for a war file starting,
in the current directory, proceeding if and only if exactly one war file is found.

You may use powershell globs here.

.PARAMETER TargetFileName
Name of the file to use on the remote machine (for example, we may be deploying my-application-3.0.0-SNAPSHOT.war but we want it to be MyApp.war remotely).
If not specified, $WarFile.Name will be used.

.PARAMETER SshUrl
The url you wish to SSH to, in the form "username@hostname".  If you have SSH keys installed
(on linux, via ssh-add, or on windows via Pageant, or with Posh-Git), they will be used.  Otherwise, you will
be prompted multiple times for the remote password.

.PARAMETER ForcePutty
Use this if you are on Windows and have ssh/scp installed (for example, via git-bash or cygwin)
and want this script to explicitly use pscp and putty (which must be on the path).

.PARAMETER Timeout
Timeout in seconds.  Passing 0 here will avoid any log tailing and will use exit code from startup.sh


.EXAMPLE
.\Deploy.ps1 -ForcePutty -CatalinaHome /usr/local/appservers/cio-Dev-Test/rev-MeF -sshurl tomcat@10.200.11.22 -TargetFileName mefAdmin.war -Timeout 60 -SuccessString "initialization complete"
#>

[CmdletBinding(SupportsShouldProcess=$True)]
param(
	[Parameter(Mandatory=$true)][string]$CatalinaHome,
	[Parameter(Mandatory=$true)][string]$SshUrl,
	[string]$WarFile,
	[string]$TargetFileName,
	[int]$Timeout=60,
	[string]$SuccessString,
	[switch]$ForcePutty
)
Import-Module -Force $PSScriptRoot\DeployUtils.psm1

# ordinarily we'd like our commands to only dump output on error, but this
# task necessarily shows lots of debug info on stdout (namely, it tails catalina.out)
# so we might as well print the params to the console while we're at it 
Write-Output "CatalinaHome=$CatalinaHome"
Write-Output "SshUrl=$SshUrl"
Write-Output "WarFile=$WarFile"
Write-Output "TargetFileName=$TargetFileName"
Write-Output "Timeout=$Timeout"
Write-Output "SuccessString=$SuccessString"
Write-Output "ForcePutty=$ForcePutty"

# Look for WAR files if $WarFile is "" or $null.
if (!$WarFile){
	Write-Output "Looking for WAR files..."
	$War = Get-ChildItem -re *.war 
} elseif ((Get-Item $WarFile) -is [System.IO.DirectoryInfo]) {
	Write-Output "Looking for WAR files in $Warfile..."
	# VSTS will pass the current *directory*, so search starting from there
	$War = Get-ChildItem -Path $Warfile -re *.war
} else {
	$War = Get-Item $WarFile 
}

if (($War | Measure-Object).Count -ne 1) {
	$War
 	throw "Expected to find exactly 1 war file!"
}

Write-Output "Deploying $($War.FullName)..."

if (!$SuccessString){
	Write-Warning "SuccessString is unspecified"
}

if (!$TargetFileName){
	$TargetFileName = $WarFile.Name
}

Publish-War -File $War -SshUrl $SshUrl -CatalinaHome $CatalinaHome -ForcePutty:$ForcePutty -Verbose:($PSBoundParameters['Verbose'] -eq $true) -Timeout $Timeout -SuccessString $SuccessString -TargetFileName $TargetFilename -WhatIf:($PSBoundParameters['WhatIf'] -eq $true)

