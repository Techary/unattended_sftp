#Requires -Version 5.1
<#
.SYNOPSIS
    SFTP Retry module for handling transient failures with exponential backoff.
.DESCRIPTION
    Provides retry logic with configurable attempts, delays, and exponential backoff
    for handling transient network and transfer failures.
#>

function Invoke-WithRetry {
    <#
    .SYNOPSIS
        Executes a script block with configurable retry logic.
    .PARAMETER ScriptBlock
        The operation to execute.
    .PARAMETER MaxAttempts
        Maximum number of attempts (including initial).
    .PARAMETER DelaySeconds
        Base delay between retries.
    .PARAMETER ExponentialBackoff
        Use exponential backoff (2^attempt * DelaySeconds).
    .PARAMETER RetryableExceptions
        Array of exception type names that trigger retry.
    .PARAMETER OnRetry
        Script block to execute before each retry.
    .OUTPUTS
        Result of successful ScriptBlock execution.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [int]$MaxAttempts = 3,

        [Parameter()]
        [int]$DelaySeconds = 5,

        [Parameter()]
        [bool]$ExponentialBackoff = $true,

        [Parameter()]
        [string[]]$RetryableExceptions = @(
            "System.Net.Sockets.SocketException",
            "WinSCP.SessionRemoteException",
            "System.TimeoutException",
            "System.IO.IOException"
        ),

        [Parameter()]
        [scriptblock]$OnRetry = $null
    )

    $attempt = 0
    $lastException = $null

    while ($attempt -lt $MaxAttempts) {
        $attempt++

        try {
            return & $ScriptBlock
        }
        catch {
            $lastException = $_

            # Check if we should retry
            $shouldRetry = Test-RetryableException -Exception $_.Exception -RetryableExceptions $RetryableExceptions

            if (-not $shouldRetry -or $attempt -ge $MaxAttempts) {
                throw
            }

            # Calculate delay
            $delay = Get-RetryDelay -Attempt $attempt `
                                    -BaseDelaySeconds $DelaySeconds `
                                    -ExponentialBackoff $ExponentialBackoff

            # Execute OnRetry callback if provided
            if ($OnRetry) {
                try {
                    & $OnRetry
                }
                catch {
                    # Ignore errors in callback
                }
            }

            # Wait before retry
            Start-Sleep -Seconds $delay
        }
    }

    # Should not reach here, but just in case
    if ($lastException) {
        throw $lastException
    }
}

function Test-RetryableException {
    <#
    .SYNOPSIS
        Determines if an exception should trigger a retry.
    .PARAMETER Exception
        The exception to test.
    .PARAMETER RetryableExceptions
        Array of exception type names that should trigger retry.
    .OUTPUTS
        Boolean indicating if retry should occur.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Exception]$Exception,

        [Parameter()]
        [string[]]$RetryableExceptions = @()
    )

    if ($RetryableExceptions.Count -eq 0) {
        return $true
    }

    $exceptionType = $Exception.GetType().FullName

    foreach ($retryableType in $RetryableExceptions) {
        if ($exceptionType -eq $retryableType -or $exceptionType -like "*$retryableType*") {
            return $true
        }
    }

    # Check inner exception
    if ($Exception.InnerException) {
        return Test-RetryableException -Exception $Exception.InnerException -RetryableExceptions $RetryableExceptions
    }

    # Check for common transient error patterns in message
    $transientPatterns = @(
        "connection reset",
        "connection refused",
        "connection timed out",
        "timeout",
        "temporarily unavailable",
        "network unreachable",
        "socket",
        "host not found"
    )

    $message = $Exception.Message.ToLower()
    foreach ($pattern in $transientPatterns) {
        if ($message -like "*$pattern*") {
            return $true
        }
    }

    return $false
}

function Get-RetryDelay {
    <#
    .SYNOPSIS
        Calculates delay for current retry attempt.
    .PARAMETER Attempt
        Current attempt number (1-based).
    .PARAMETER BaseDelaySeconds
        Base delay in seconds.
    .PARAMETER ExponentialBackoff
        Whether to use exponential backoff.
    .PARAMETER MaxDelaySeconds
        Maximum delay cap.
    .OUTPUTS
        Delay in seconds.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Attempt,

        [Parameter(Mandatory)]
        [int]$BaseDelaySeconds,

        [Parameter()]
        [bool]$ExponentialBackoff = $true,

        [Parameter()]
        [int]$MaxDelaySeconds = 300
    )

    if ($ExponentialBackoff) {
        # Exponential: delay * 2^(attempt-1)
        $delay = $BaseDelaySeconds * [math]::Pow(2, $Attempt - 1)
    }
    else {
        $delay = $BaseDelaySeconds
    }

    # Add jitter (up to 20% random variation)
    $jitter = Get-Random -Minimum 0 -Maximum ([int]($delay * 0.2 + 1))
    $delay += $jitter

    # Cap at maximum
    return [math]::Min($delay, $MaxDelaySeconds)
}

Export-ModuleMember -Function Invoke-WithRetry, Test-RetryableException, Get-RetryDelay
