#!/bin/env pwsh
<#
.SYNOPSIS

.DESCRIPTION

.PARAMETER CatalinaHome 
Location on linux server of Catalina directory

.PARAMETER SshUrl
The url you wish to SSH to, in the form "username@hostname".  If you have SSH keys installed
(on linux, via ssh-add, or on windows via Pageant, or with Posh-Git), they will be used.  Otherwise, you will
be prompted multiple times for the remote password.

.PARAMETER ForcePutty
Use this if you are on Windows and have ssh/scp installed (for example, via git-bash or cygwin)
and want this script to explicitly use pscp and putty (which must be on the path).


.EXAMPLE
#>

[CmdletBinding(SupportsShouldProcess=$True)]
param(
	[Parameter(Mandatory=$true)][string]$CatalinaHome,
	[Parameter(Mandatory=$true)][string]$SshUrl,
	[Parameter(Mandatory=$true)][string]$Version,
	[switch]$ForcePutty
)
Import-Module -Force $PSScriptRoot\TomcatUtils.psm1

# ordinarily we'd like our commands to only dump output on error, but this
# task necessarily shows lots of debug info on stdout (namely, it tails catalina.out)
# so we might as well print the params to the console while we're at it 
Write-Output "CatalinaHome=$CatalinaHome"
Write-Output "SshUrl=$SshUrl"
Write-Output "ForcePutty=$ForcePutty"
Write-Output "Version=$Version"

$file=Get-TomcatArtifact $Version -Verbose:$Verbose
install-tomcat -File $File -SshUrl $SshUrl -CatalinaHome $CatalinaHome -Verbose:$Verbose
