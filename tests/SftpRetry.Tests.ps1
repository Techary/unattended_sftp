#Requires -Module Pester
<#
.SYNOPSIS
    Unit tests for SftpRetry module.
#>

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "..\modules\SftpRetry\SftpRetry.psd1"
    Import-Module $modulePath -Force
}

Describe "Invoke-WithRetry" {
    It "Should return result on first success" {
        $result = Invoke-WithRetry -ScriptBlock { "success" } -MaxAttempts 3

        $result | Should -Be "success"
    }

    It "Should retry on failure and eventually succeed" {
        $script:attempts = 0

        $result = Invoke-WithRetry -ScriptBlock {
            $script:attempts++
            if ($script:attempts -lt 3) {
                throw [System.IO.IOException]::new("Transient error")
            }
            return "success"
        } -MaxAttempts 5 -DelaySeconds 0

        $result | Should -Be "success"
        $script:attempts | Should -Be 3
    }

    It "Should throw after max attempts exhausted" {
        {
            Invoke-WithRetry -ScriptBlock {
                throw [System.IO.IOException]::new("Permanent error")
            } -MaxAttempts 3 -DelaySeconds 0
        } | Should -Throw
    }

    It "Should call OnRetry callback" {
        $script:retryCount = 0

        try {
            Invoke-WithRetry -ScriptBlock {
                throw [System.IO.IOException]::new("Error")
            } -MaxAttempts 3 -DelaySeconds 0 -OnRetry {
                $script:retryCount++
            }
        } catch {}

        $script:retryCount | Should -Be 2  # Called before each retry (not initial attempt)
    }

    It "Should not retry non-retryable exceptions" {
        $script:attempts = 0

        {
            Invoke-WithRetry -ScriptBlock {
                $script:attempts++
                throw [System.ArgumentException]::new("Invalid argument")
            } -MaxAttempts 5 -DelaySeconds 0 -RetryableExceptions @("System.IO.IOException")
        } | Should -Throw

        $script:attempts | Should -Be 1
    }
}

Describe "Test-RetryableException" {
    It "Should return true for matching exception type" {
        $exception = [System.IO.IOException]::new("Test")

        $result = Test-RetryableException -Exception $exception -RetryableExceptions @("System.IO.IOException")

        $result | Should -Be $true
    }

    It "Should return false for non-matching exception type" {
        $exception = [System.ArgumentException]::new("Test")

        $result = Test-RetryableException -Exception $exception -RetryableExceptions @("System.IO.IOException")

        $result | Should -Be $false
    }

    It "Should detect transient patterns in message" {
        $exception = [System.Exception]::new("Connection timed out")

        $result = Test-RetryableException -Exception $exception -RetryableExceptions @()

        $result | Should -Be $true
    }

    It "Should check inner exceptions" {
        $innerException = [System.IO.IOException]::new("Inner error")
        $outerException = [System.Exception]::new("Outer error", $innerException)

        $result = Test-RetryableException -Exception $outerException -RetryableExceptions @("System.IO.IOException")

        $result | Should -Be $true
    }
}

Describe "Get-RetryDelay" {
    It "Should return base delay without backoff" {
        $delay = Get-RetryDelay -Attempt 1 -BaseDelaySeconds 5 -ExponentialBackoff $false

        $delay | Should -BeGreaterOrEqual 5
        $delay | Should -BeLessOrEqual 6  # Allow for jitter
    }

    It "Should increase delay with exponential backoff" {
        $delay1 = Get-RetryDelay -Attempt 1 -BaseDelaySeconds 5 -ExponentialBackoff $true
        $delay2 = Get-RetryDelay -Attempt 2 -BaseDelaySeconds 5 -ExponentialBackoff $true
        $delay3 = Get-RetryDelay -Attempt 3 -BaseDelaySeconds 5 -ExponentialBackoff $true

        # Base delays (before jitter): 5, 10, 20
        $delay2 | Should -BeGreaterThan $delay1
        $delay3 | Should -BeGreaterThan $delay2
    }

    It "Should cap at maximum delay" {
        $delay = Get-RetryDelay -Attempt 10 -BaseDelaySeconds 60 -ExponentialBackoff $true -MaxDelaySeconds 300

        $delay | Should -BeLessOrEqual 300
    }
}
