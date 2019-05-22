<#
.SYNOPSIS
Deploys WAR Files over SSH.  Does not accept any parameters, as this is intended
to be called from within an Azure DevOps task.
All parameters are retrieved using Get-VstsInput, rather than the param section.

.LINK
https://github.com/Microsoft/azure-pipelines-tasks/blob/master/Tasks/MSBuildV1/MSBuild.ps1 for an example
.LINK
https://github.com/Microsoft/azure-pipelines-task-lib 
#>
[CmdletBinding()]
param()

Import-Module -Force "$PSScriptRoot\DeployUtils.psm1"
Import-Module -Force "$PSScriptRoot\SshAgent.psm1"
Import-VstsLocStrings "$PSScriptRoot\task.json"

# get ssh url using our own powershell module
[string]$SshUrl = Get-SshUrl

[string]$CatalinaBase = Get-VstsInput -Name CatalinaBase 
[string]$WarFile = Get-VstsInput -Name Warfile
[string]$TargetFileName = Get-VstsInput -Name TargetFileName
[int]$Timeout = Get-VstsInput -Name Timeout -AsInt -Default 60
[string]$SuccessString = Get-VstsInput -name SuccessString
[boolean]$IgnoreHostKey = Get-VstsInput -name IgnoreHostKey -AsBool

# ordinarily we'd like our commands to only dump output on error, but this
# task necessarily shows lots of debug info on stdout (namely, it tails catalina.out)
# so we might as well print the params to the console while we're at it 
Write-VstsTaskDebug "SshUrl=$SshUrl"
Write-VstsTaskDebug "CatalinaBase=$CatalinaBase"
Write-VstsTaskDebug "WarFile=$WarFile"
Write-VstsTaskDebug "Timeout=$Timeout"
Write-VstsTaskDebug "SuccessString=$SuccessString"
Write-VstsTaskDebug "IgnoreHostKey=$IgnoreHostKey"

# if WarFile isn't explicitly declared, look for one
if ([string]::IsNullOrWhiteSpace($WarFile)) {
	Write-VstsTaskDebug "Looking for WAR files..."
	$War = Get-ChildItem -re *.war 
} elseif ((Get-Item $WarFile) -is [System.IO.DirectoryInfo]) {
	Write-VstsTaskDebug "Looking for WAR files in $Warfile..."
	# VSTS will pass the current *directory*, so search starting from there
	$War = Get-ChildItem -Path $Warfile -re *.war
} else {
	$War = Get-Item $WarFile 
}

$warcnt = ($War | Measure-Object).Count 
if ($warcnt -ne 1) {
	$lst = $War -join "," 
 	throw "Expected to find exactly 1 war file but got $warcnt [$lst]!"
}

if ([string]::IsNullOrEmpty($TargetFileName)){
	$TargetFileName = $War.Name
	Write-Output "No TargetFileName specified.  Using $TargetFileName."
}

Write-Output "Deploying $($War.FullName) to [$sshUrl] $CatalinaBase/webapps/$TargetFilename"
Write-VstsTaskDebug "TargetFileName='$TargetFileName'"

# have SSH_AGENT_PID available for subsequent SSH calls
Read-Agent

Write-VstsTaskDebug "Publish-War -File $($War.FullName) -SshUrl $SshUrl -CatalinaHome $CatalinaBase -Timeout $Timeout -SuccessString $SuccessString -TargetFileName $TargetFilename -ForceRestart:$ForceRestart -IgnoreHostKey:$IgnoreHostKey"
Publish-War -File $War.FullName -SshUrl $SshUrl -CatalinaHome $CatalinaBase -Timeout $Timeout -SuccessString $SuccessString -TargetFileName $TargetFilename -ForceRestart:$ForceRestart -IgnoreHostKey:$IgnoreHostKey
