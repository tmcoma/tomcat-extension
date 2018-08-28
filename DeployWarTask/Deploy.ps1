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
foreach ($key in $MyInvocation.BoundParameters.keys) {
    Get-Variable $key -ErrorAction SilentlyContinue
}

Write-Output "Working from..."
Get-ChildItem

Write-Output "WarFile is $WarFile..."

# Look for WAR files if $WarFile is "" or $null.
if (!$WarFile){
	Write-Output "Looking for WAR files..."
	$WarFile = Get-ChildItem -re *.war 
} else if ((Get-Item $WarFile) -is [System.IO.DirectoryInfo]){
	# VSTS will pass the current *directory*, so search starting from there
	$WarFile = Get-ChildItem -Path $Warfile -re *.war
} else {
	$WarFile = Get-Item $WarFile 
}

$cnt = ($WarFile | Measure-Object).Count

if ($WarFile -eq $null){
 	throw "No *war found to deploy!"
} elseif ($cnt -ne 1) {
	Write-Error $Warfile
 	throw "Expected to find 1 war file but found $cnt"
}

Write-Output "Deploying $WarFile..."

if (!$SuccessString){
	Write-Warning "SuccessString is unspecified"
}

if (!$TargetFileName){
	$TargetFileName = $WarFile.Name
}

Publish-War -File $WarFile -SshUrl $SshUrl -CatalinaHome $CatalinaHome -ForcePutty:$ForcePutty -Verbose:($PSBoundParameters['Verbose'] -eq $true) -Timeout $Timeout -SuccessString $SuccessString -TargetFileName $TargetFilename -WhatIf:($PSBoundParameters['WhatIf'] -eq $true)

