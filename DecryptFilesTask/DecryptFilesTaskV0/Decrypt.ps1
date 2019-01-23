Import-Module "$PSScriptRoot/ps_modules/RepoCrypto"

$KeyString = Get-VstsInput -Name KeyString
$Algorithm = Get-VstsInput -Name Algorithm -Require
$RemoveSource = Get-VstsInput -Name RemoveSource -Require -AsBool
$SearchDir = Get-VstsInput -Name SearchDir


if ($KeyString) {
    $key = $KeyString.trim() | ConvertTo-SecureString -AsPlainText -Force
} else {
    # download the secure file and read it as a SecureString
    $secFileId = Get-VstsInput -Name KeyFile -Require
    $secTicket = Get-VstsSecureFileTicket -Id $secFileId
    $secName = Get-VstsSecureFileName -Id $secFileId
    $tempDirectory = Get-VstsTaskVariable -Name "Agent.TempDirectory" -Require
    $collectionUrl = Get-VstsTaskVariable -Name "System.TeamFoundationCollectionUri" -Require
    $project = Get-VstsTaskVariable -Name "System.TeamProject" -Require
    $filePath = Join-Path $tempDirectory $secName

    $token= Get-VstsTaskVariable -Name "System.AccessToken" -Require
    $user = Get-VstsTaskVariable -Name "Agent.MachineName" -Require # it doesn't matter what we use for the username
    
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $User, $token)))
    $headers = @{
        Authorization=("Basic {0}" -f $base64AuthInfo)
        Accept="application/octet-stream"
    } 

    Invoke-RestMethod -Uri "$($collectionUrl)$project/_apis/distributedtask/securefiles/$($secFileId)?ticket=$($secTicket)&download=true&api-version=5.0-preview.1" -Headers $headers -OutFile $filePath
    $key = (Get-Content $filePath -Raw).trim() | ConvertTo-SecureString -AsPlainText -Force
}

Write-Output "Recursively searching $searchdir`..."
Get-ChildItem -Path $SearchDir -Include "*.$Algorithm" -Recurse | ForEach-Object {
    UnProtect-File $_ -Algorithm $Algorithm -Key $key -RemoveSource:$RemoveSource 
    if( test-path $_ -ErrorAction Ignore ){
        $_
    }
}
