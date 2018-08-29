<#
.SYNOPSIS
Replaces tokens in the form ##TOKENNAME## with tokens from a hashmap.  Also includes Environment Variables, so
you can use things like ##RELEASE_RELEASENAME## in VSTS.

.DESCRIPTION
Environment variables are included as tokens here, so you may reference variables like ##PATH## or ##USERNAME## or ##JAVA_HOME##.  Additionally, the following tokens are set by default.

'BUILDTIMESTAMP' =  $(get-date).ToString('yyyy-MM-dd HH:mm')
'BUILDDATE' =  $(get-date).ToString('yyyy-MM-dd')
'BUILDTIME' =  $(get-date).ToString('HH:mm')
'BUILDTIMEHUMAN' = $(get-date)
'FILENAME' = "$File"

.PARAMETER Tokens
Hashmap of tokens, e.g. @{ REVISION="1.2", DATE="2018-08-02" }

.PARAMETER Path
File Pattern (or patterns), e.g. "*.xml" or "*.xml","*.json"

.PARAMETER Inline
If passed, will overwrite the contents of File instead of writing contents back to the success stream

.EXAMPLE
.\ReplaceTokens.ps1 src/MyFile.xml

Replace any of the default tokens in src/MyFile.xml. Default tokens include all Environment variables like ##PATH## or ##USERNAME##.  Output will be written to the success stream.

.EXAMPLE
.\ReplaceTokens.ps1 src/*.xml -Tokens @{ REVISION='1.2', AUTHOR='Tom McLaughlin' } -Inline

Occurrences of "##REVISION##" and "##AUTHOR##" in src/*.xml will be replaced by
"1.2" and "Tom McLaughlin", respectively.

#>
[CmdletBinding(SupportsShouldProcess=$True)]
param(
	[Parameter(Mandatory=$true, Position=1)][string[]]$Path,
	[hashtable]$Tokens=@{},
	[switch]$Inline,
	[string]$Delim='##'
)

process {
	foreach($File in (Resolve-Path $Path)) {		
		if (Test-Path $File ){
			$buf = Get-Content -Path $File -RAW
			
			# some default tokens
			$allTokens = @{
				'BUILDTIMESTAMP' =  $(get-date).ToString('yyyy-MM-dd HH:mm')
				'BUILDDATE' =  $(get-date).ToString('yyyy-MM-dd')
				'BUILDTIME' =  $(get-date).ToString('HH:mm')
				'BUILDTIMEHUMAN' = $(get-date)
				'FILENAME' = "$File"
			}
			
			# all environment variables
			Get-ChildItem env:* |% { $allTokens.add($_.key, $_.value) }
	
			# the user's tokens	
			foreach ( $t in $Tokens.GetEnumerator() ) {
				if( ! $allTokens[$t.key] ){
					$allTokens.add($t.key, $t.value)
				}
			}

			foreach( $t in $allTokens.GetEnumerator() ) {
				$pattern = "$Delim{0}$Delim" -f $t.key
				$buf = $buf -replace $pattern, $t.Value
			}
			
			if($Inline){
				Set-Content -Path $File -Value $buf -Force -NoNewline
			} else {
				return $buf
			}
		}
	}
}


