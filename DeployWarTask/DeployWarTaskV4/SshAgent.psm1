
# SSH Connection
$SshConnectionId = Get-VstsInput -Name SshConnection -Require
$SshConnectionEndpoint = Get-VstsEndpoint -Name $SshConnectionId -Require
# Write-Output ($SshConnectionEndpoint | ConvertTo-Json)
$sshAgentEnv = "$env:AGENT_TEMPDIRECTORY/$($SshConnectionId).ps1"

function Get-SshUrl {
    # SSH Connection
    # Endpoint objects will have 3 attributes: Url, Data, and Auth
    # You can get username and password as:  
    #   $SshConnectionEndpoint.Auth.parameters.username
    #   $SshConnectionEndpoint.Auth.parameters.password
    # $SshConnectionId = Get-VstsInput -Name SshConnection -Require
    # $SshConnectionEndpoint = Get-VstsEndpoint -Name $SshConnectionId -Require
    #Write-Output ($SshConnectionEndpoint | ConvertTo-Json)
    [string]$username = $SshConnectionEndpoint.Auth.Parameters.username
    [string]$SshUrl = $username + "@" + ($SshConnectionEndpoint.Url -replace "ssh:")
    $SshUrl = $SshUrl -replace "/"
    $SshUrl = $SshUrl -replace ":22"
    return $SshUrl
}


function Start-Agent {
    $bourne = & ssh-agent -s

    # SSH_AUTH_SOCK=/tmp/ssh-g7sl1Ym2i6ER/agent.19495; export SSH_AUTH_SOCK;
    # SSH_AGENT_PID=19496; export SSH_AGENT_PID;
    # echo Agent pid 19496;
    $split = $bourne -split ';'

    # SSH_AUTH_SOCK=/tmp/ssh-g7sl1Ym2i6ER/agent.19495
    $sshAuthSock = $split[0] -replace '.*='

    # SSH_AGENT_PID=19496
    $sshAgentPid = $split[3] -replace '.*='

    $envScript = @"
`$env:SSH_AUTH_SOCK='$sshAuthSock'
`$env:SSH_AGENT_PID='$sshAgentPid'
"@

    # set the variables
    Set-Content -Path $sshAgentEnv -Value $envScript
    . $sshAgentEnv

    # create a SSH_ASKPASS script for ssh-add to use
    $passphrase = $SshConnectionEndpoint.Auth.parameters.password
    $askPassScript = "echo '$passphrase'"
    Set-Content -Path "$PSScriptRoot\AskPass.ps1" -Value $askPassScript
    $env:SSH_ASKPASS="$PSScriptRoot\AskPass.ps1"

    try {
        # ssh-add will call SSH_ASKPASS if DISPLAY=:0
        $env:DISPLAY=":0"
        Write-Output "Display is $env:DISPLAY"
        $SshConnectionEndpoint.Data.PrivateKey | ssh-add -
    } finally {
        Remove-Item env:\SSH_ASKPASS
        Remove-Item env:\SSH_AUTH_SOCK
        Remove-Item env:\SSH_AGENT_PID
        Remove-Item env:\DISPLAY
    }
}

function Read-Agent {
    # set environment variables
    . $sshAgentEnv
}

function Stop-Agent {
    # it's possible that this was already cleaned up
    if(Test-Path $sshAgentEnv){
        . $sshAgentEnv
        ssh-agent -k
        remove-item $sshAgentEnv
        Remove-Item env:\SSH_AUTH_SOCK
        Remove-Item env:\SSH_AGENT_PID
    }
}
