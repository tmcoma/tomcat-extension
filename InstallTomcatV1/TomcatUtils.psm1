function Test-ArtifactChecksum {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory=$true,Position=1)][System.IO.FileInfo]$File
	)

	
	# checksum files are of the form <file>.<algorithm>
	$hashfile = Get-Item "checksums/$($file.name)*"
	if(!$hashfile){
		throw "Checksum for $file not found!" 
	}

	$alg = $hashfile.name.substring($hashfile.name.lastIndexOf('.') + 1)
	Write-Verbose "Using $alg..."

	$expectedHash = (Get-Content $hashfile).split(' ')[0]
	Write-Verbose "Expected: $expectedHash"
	$actualHash = (Get-FileHash $file -Algorithm $alg).Hash
	Write-Verbose "Actual:   $actualHash"

	# powershell is case insensitive
	if($expectedHash -ne $actualHash){
		Write-Warning "Expected '$expectedHash' but got '$actualHash' on $file"
		return $false
	} else {
		return $true
	}
}

function Get-TomcatArtifact {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory=$true,Position=1)][string]$version
	)

	Write-Verbose "Looking up url for $version..."
	$urltable = Get-Content "$PSScriptRoot/tomcat-versions.json" | Out-String | ConvertFrom-Json -AsHashtable
	$urls = $urltable["$version"]
	write-verbose "urls $urls"

	if(!$urls){
		# we didn't find anything
		throw "Unknown tomcat version $version!"
	}

	foreach ($url in $urls) {
		# filename is just the name of the tarball
		$filename = $url.substring($url.lastIndexOf('/') + 1)

		Invoke-WebRequest $url -OutFile $filename

		$file = get-item $filename
		if(! (Test-ArtifactChecksum $file)){
			throw "Checksum mismatch on $file!"
		}
		return $file
	}

	throw "Failed to retrieve Apache Tomcat version '$version'"
}

function Install-Tomcat {
	<#
	.SYNOPSIS
	.DESCRIPTION
	.PARAMETER File
	.EXAMPLE
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory=$true)][string]$SshUrl,
		[Parameter(Mandatory=$true)][string]$CatalinaHome,
		[Parameter(Mandatory=$true)][System.IO.FileInfo]$File,
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
		Write-Warning "'$SshUrl' does not appear to be a valid SSH url.  We were expecting user@hostname."
	}
	
	$tmp="/tmp/$(New-Guid)"
	try {
		# I don't want this to fail if this file winds up with
		# windows newlines, so there's a -replace here
		$script=@"
mkdir $tmp;
if [ -d "$CatalinaHome" ]; then
	exit 10;
fi
mkdir -p "$CatalinaHome";
"@ -replace '\r',''
		& $ssh $SshUrl $script
		if ($LASTEXITCODE -eq 10){
			throw "Directory $CatalinaHome already exists on $SshUrl!"
		} elseif ($LASTEXITCODE -ne 0){
			throw "Failed to create $CatalinaHome on $SshUrl!"
		}
		Write-Verbose "Copying '$file' to '${SshUrl}:$tmp'..."
		& $scp $File "${SshUrl}:$tmp" 
		Write-Verbose "Extracting '$tmp/$($File.Name)' to '${SshUrl}:$CatalinaHome'..."
		& $ssh $SshUrl "tar xzf $tmp/$($File.Name) -C $CatalinaHome --strip 1"
	} finally {
		Write-Verbose "Cleaning up $tmp..."
		& $ssh $SshUrl "rm -rf $tmp"
	}
}

Export-ModuleMember Get-TomcatArtifact
Export-ModuleMember Install-Tomcat
