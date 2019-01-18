
# SSH Connection
$SshConnectionId = Get-VstsInput -Name SshConnection -Require
$SshConnectionEndpoint = Get-VstsEndpoint -Name $SshConnectionId -Require
# Write-Output ($SshConnectionEndpoint | ConvertTo-Json)
$sshAgentEnv = "$env:AGENT_TEMPDIRECTORY/$($SshConnectionId).ps1"

<#
.SYNOPSIS
Reads the url from an SSH Connection Endpoint, as stored in the global $sshConnectionEndpoint, stripping
out the leading "ssh://" and port number (assumes :22), and prepends the username, producing something like 
"myuser@myhost.mycorp.com"
#>
function Get-SshUrl {
    [string]$username = $SshConnectionEndpoint.Auth.Parameters.username
    [string]$SshUrl = $username + "@" + ($SshConnectionEndpoint.Url -replace "ssh:")
    $SshUrl = $SshUrl -replace "/"
    $SshUrl = $SshUrl -replace ":22"
    return $SshUrl
}

<#
.SYNOPSIS
Start an ssh-agent, setting SSH_AUTH_SOCK and SSH_AGENT_PID environment variables.
As a side-effect, will leave a file at "$sshAgentEnv" which sets environment
variables for later use by Read-Agent.
#>
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

    try {
        # create a SSH_ASKPASS script for ssh-add to use
        if ($env:AGENT_TEMPDIRECTORY){
            $env:SSH_ASKPASS="$env:AGENT_TEMPDIRECTORY/$([guid]::NewGuid()).ps1"
        } else {
            $env:SSH_ASKPASS="$env:TEMP/$([guid]::NewGuid()).ps1"
        }

        $passphrase = $SshConnectionEndpoint.Auth.parameters.password
        Set-Content -Path $env:SSH_ASKPASS -Value  "echo '$passphrase'"

        # ssh-add will call SSH_ASKPASS if DISPLAY=:0
        $env:DISPLAY=":0"
        $SshConnectionEndpoint.Data.PrivateKey | ssh-add -
        if ($LASTEXITCODE -ne 0){
            throw "Failed to add private key to agent."
        }
    } finally {
        Remove-Item $env:SSH_ASKPASS -ErrorAction Continue
        Remove-Item env:\SSH_ASKPASS -ErrorAction Continue
        Remove-Item env:\SSH_AUTH_SOCK -ErrorAction Continue
        Remove-Item env:\SSH_AGENT_PID -ErrorAction Continue
        Remove-Item env:\DISPLAY -ErrorAction Continue
    }
}

<#
.SYNOPSIS
Reads the configuration established by Start-Agent
#>
function Read-Agent {
    # set environment variables
    . $sshAgentEnv
}

<#
.SYNOPSIS
Stops the agent using ssh-agent -k and removes "$sshAgentEnv", SSH_AUTH_SOCK, and SSH_AGENT_PID.
#>
function Stop-Agent {
    # it's possible that this was already cleaned up
    if(Test-Path $sshAgentEnv){
        . $sshAgentEnv
        ssh-agent -k
        Remove-Item $sshAgentEnv -ErrorAction Continue
        Remove-Item env:\SSH_AUTH_SOCK -ErrorAction Continue
        Remove-Item env:\SSH_AGENT_PID -ErrorAction Continue
    }
}
