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
Import-VstsLocStrings "$PSScriptRoot\task.json"

[string]$CatalinaLocation = Get-VstsInput -Name CatalinaLocation
[string]$WarFile = Get-VstsInput -Name Warfile
[string]$TargetFileName = Get-VstsInput -Name TargetFileName
[int]$Timeout = Get-VstsInput -Name Timeout -AsInt -Default 60
[string]$SuccessString = Get-VstsInput -name SuccessString
# [boolean]$DryRun = Get-VstsInput -name DryRun -AsBool

# ordinarily we'd like our commands to only dump output on error, but this
# task necessarily shows lots of debug info on stdout (namely, it tails catalina.out)
# so we might as well print the params to the console while we're at it 
Write-Output "CatalinaLocation=$CatalinaLocation"
Write-Output "WarFile=$WarFile"
Write-Output "Timeout=$Timeout"
Write-Output "SuccessString=$SuccessString"

# if WarFile isn't explicitly declared, look for one
if ([string]::IsNullOrWhiteSpace($WarFile)) {
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

if ([string]::IsNullOrEmpty($TargetFileName)){
	$TargetFileName = $War.Name
	Write-Output "No TargetFileName specified.  Using default."
}

Write-Output "TargetFileName='$TargetFileName'"

# we expect CatalinaLocation to be something like "tomcat@192.168.11.1:/home/tomcat/tomcat-8.5.31" 
# use bizarro syntax rule; if url starts with '!' then use -ForceRestart 
$ForceRestart = $CatalinaLocation -like "!*"
$spl = ($CatalinaLocation -replace '!', '') -split ":"
$SshUrl = $spl[0] # tomcat@192.168.11.1
$CatalinaHome = $spl[1] # /home/tomcat-8.5.31

Write-Output "Publish-War -File $War -SshUrl $SshUrl -CatalinaHome $CatalinaHome -Timeout $Timeout -SuccessString $SuccessString -TargetFileName $TargetFilename -ForceRestart:$ForceRestart"
Publish-War -File $War -SshUrl $SshUrl -CatalinaHome $CatalinaHome -Timeout $Timeout -SuccessString $SuccessString -TargetFileName $TargetFilename -ForceRestart:$ForceRestart
