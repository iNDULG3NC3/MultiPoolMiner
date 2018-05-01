﻿using module ..\Include.psm1

param(
    [alias("Wallet")]
    [String]$BTC, 
    [alias("WorkerName")]
    [String]$Worker, 
    [TimeSpan]$StatSpan,
    [bool]$Info = $false,
    [PSCustomObject]$Config
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

$Pool_APIUrl           = "http://api.zergpool.com:8080/api/status"
$Pool_CurrenciesAPIUrl = "http://api.zergpool.com:8080/api/currencies"

if ($Info) {
    # Just return info about the pool for use in setup
    $Description  = "Pool allows payout in BTC, LTC & any currency available in API"
    $WebSite      = "http://zergpool.com"
    $Note         = "To receive payouts specify at least one valid wallet" 

    try {
        $APICurrenciesRequest = Invoke-RestMethod $Pool_CurrenciesAPIUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    }
    catch {
        Write-Log -Level Warn "Pool API ($Name) has failed. "
    }

    if (($APICurrenciesRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1) {
        Write-Warning  "Unable to load supported algorithms and currencies for ($Name) - may not be able to configure all pool settings"
    }

    # Define the settings this pool uses.
    $SupportedAlgorithms = @($APICurrenciesRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Foreach-Object {Get-Algorithm $APICurrenciesRequest.$_.algo} | Select-Object -Unique | Sort-Object)
    $Payout_Currencies = @($APICurrenciesRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Foreach-Object {
        if ($APICurrenciesRequest.$_.symbol) {$APICurrenciesRequest.$_.symbol} else {$_} # filter ...-algo
    } | Select-Object -Unique | Sort-Object )
    $Settings = @(
        [PSCustomObject]@{
            Name        = "Worker"
            Required    = $true
            Default     = $Worker
            ControlType = "string"
            Description = "Worker name to report to pool "
            Tooltip     = ""    
        },
        [PSCustomObject]@{
            Name        = "BTC"
            Required    = $false
            Default     = $Config.Wallet
            ControlType = "string"
            Description = "Bitcoin payout address "
            Tooltip     = "Enter Bitcoin wallet address to receive payouts in BTC"    
        },
        [PSCustomObject]@{
            Name        = "LTC"
            Required    = $false
            Default     = $Config.LTC
            ControlType = "string"
            Description = "LiteCoin payout address "
            Tooltip     = "Enter LiteCoin wallet address to receive payouts in LTC"
        }
    )
    #add all possible payout currencies
    $Payout_Currencies | Foreach-Object {
        $Settings += [PSCustomObject]@{
            Name        = "$_"
            Required    = $false
            Default     = "$($Config.Pools.$Name.$_)"
            ControlType = "string"
            Description = "$($APICurrenciesRequest.$_.Name) payout address "
            Tooltip     = "Enter $($APICurrenciesRequest.$_.Name) wallet address to receive payouts in $($_)"    
        }
    }
    $Settings += @(
        [PSCustomObject]@{
            Name        = "IgnorePoolFee"
            Required    = $false
            ControlType = "switch"
            Default     = $false
            Description = "Tick to disable pool fee calculation for this pool"
            Tooltip     = "If ticked MPM will NOT take pool fees into account"
        },
        [PSCustomObject]@{
            Name        = "PricePenaltyFactor"
            ControlType = "int"
            Min         = 0
            Max         = 99
            Default     = $Config.PricePenaltyFactor
            Description = "This adds a multiplicator on estimations presented by the pool. "
            Tooltip     = "If not set or 0 then the default of 1 (no penalty) is used"
        },  
        [PSCustomObject]@{
            Name        = "MinWorker"
            ControlType = "int"
            Min         = 0
            Max         = 999
            Default     = $Config.MinWorker
            Description = "Minimum number of workers that must be mining an alogrithm.`nLow worker numbers will cause long delays until payout. "
            Tooltip     = "You can also set the the value globally in the general parameter section. The smaller value takes precedence"
        },
        [PSCustomObject]@{
            Name        = "ExcludeAlgorithm"
            Required    = $false
            Default     = @()
            ControlType = "string[,]"
            Description = "List of excluded algorithms for this miner. "
            Tooltip     = "Case insensitive, leave empty to mine all algorithms"
        }
    )

    return [PSCustomObject]@{
        Name        = $Name
        WebSite     = $WebSite
        Description = $Description
        Algorithms  = $SupportedAlgorithms
        Note        = $Note
        Settings    = $Settings
    }
}

try {
    $APIRequest           = Invoke-RestMethod $Pool_APIUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop # required for fees
    $APICurrenciesRequest = Invoke-RestMethod $Pool_CurrenciesAPIUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
}
catch {
    Write-Log -Level Warn "Pool API ($Name) has failed. "
    return
}

if (($APIRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1 -or ($APICurrenciesRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1) {
    Write-Log -Level Warn "Pool API ($Name) returned nothing. "
    return
}

$Regions = "us", "europe"

# Pool allows payout in BTC, LTC & any currency available in API
$Payout_Currencies = @("BTC", "LTC") + ($APICurrenciesRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name) | Select-Object -Unique | Where-Object {$Config.Pools.$Name.$_}

$APIRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | 

    # do not mine if there is no one else is mining (undesired quasi-solo-mining)
    Where-Object {$APIRequest.$_.hashrate -gt 0} |

    # a minimum of $MinWorkers is required. Low worker numbers will cause long delays until payout
    Where-Object {$APIRequest.$_.workers -gt $Config.Pools.$Name.MinWorker} |

    # filter excluded algorithms (pool and global  definition)
    Where-Object {$Config.Pools.$Name.ExcludeAlgorithm -inotcontains (Get-Algorithm $_)} |

    ForEach-Object {
    
    $Pool_Host      = "mine.zergpool.com"
    $Port           = $APIRequest.$_.port
    $Algorithm      = $APIRequest.$_.name
    $Algorithm_Norm = Get-Algorithm $Algorithm
    $Currency       = ""
    $Workers        = $APIRequest.$_.workers

    # leave fee empty if IgnorePoolFee
    if (-not $Config.IgnorePoolFee -and -not $Config.Pools.$Name.IgnorePoolFee) {$FeeInPercent = $APIRequest.$Algorithm.Fees}
    
    if ($FeeInPercent) {
        $FeeFactor = 1 - $FeeInPercent / 100
    }
    else {
        $FeeFactor = 1
    }

    $Divisor = 1000000

    switch ($Algorithm_Norm) {
        "blake2s"   {$Divisor *= 1000}
        "blakecoin" {$Divisor *= 1000}
        "decred"    {$Divisor *= 1000}
        "equihash"  {$Divisor /= 1000}
        "keccak"    {$Divisor *= 1000}
        "keccakc"   {$Divisor *= 1000}
        "quark"     {$Divisor *= 1000}
        "qubit"     {$Divisor *= 1000}
        "scrypt"    {$Divisor *= 1000}
        "x11"       {$Divisor *= 1000}
    }


    if ($PricePenaltyFactor -le 0) {
        $PricePenaltyFactor = 1
    }

    if ((Get-Stat -Name "$($Name)_$($Algorithm_Norm)_Profit") -eq $null) {$Stat = Set-Stat -Name "$($Name)_$($Algorithm_Norm)_Profit" -Value ([Double]$APIRequest.$_.estimate_last24h / $Divisor) -Duration (New-TimeSpan -Days 1)}
    else {$Stat = Set-Stat -Name "$($Name)_$($Algorithm_Norm)_Profit" -Value ([Double]$APIRequest.$_.estimate_current / $Divisor) -Duration $StatSpan -ChangeDetection $true}

    $Regions | ForEach-Object {
        $Region = $_
        $Region_Norm = Get-Region $Region

        $Payout_Currencies | ForEach-Object {
            #Option 1
            [PSCustomObject]@{
                Algorithm     = $Algorithm_Norm
                Info          = $Currency
                Price         = $Stat.Live * $FeeFactor * $PricePenaltyFactor
                StablePrice   = $Stat.Week * $FeeFactor * $PricePenaltyFactor
                MarginOfError = $Stat.Week_Fluctuation
                Protocol      = "stratum+tcp"
                Host          = "$Algorithm.$Pool_Host"
                Port          = $Port
                User          = $Config.Pools.$Name.$_
                Pass          = "$Worker,c=$_"
                Region        = $Region_Norm
                SSL           = $false
                Updated       = $Stat.Updated
                Fee           = $FeeInPercent
                Workers       = $Workers
            }
        }
    }
}