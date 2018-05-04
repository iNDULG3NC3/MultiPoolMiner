﻿using module ..\Include.psm1

param(
    [PSCustomObject]$Pools,
    [PSCustomObject]$Stats,
    [PSCustomObject]$Config,
    [PSCustomObject]$Devices
)

# Compatibility check with old MPM builds
if (-not $Config.Miners) {return}

$Name = "$(Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName)"
$Path = ".\Bin\NVIDIA-Zealot\z-enemy.exe"
$Type = "NVIDIA"
$API  = "Ccminer"
$Port = 4068
$DeviceIdBase = 16 # DeviceIDs are in hex
$DeviceIdOffset = 0 # DeviceIDs start at 0

$MinerFileVersion = "2018050402" # Format: YYYYMMDD[TwoDigitCounter], higher value will trigger config file update
$MinerBinaryInfo = "zealot/enemy-1.08, 1% devfee"
$MinerBinaryHash = "59e413741711e2984a1911db003fee807941f9a9f838cb96ff050194bc74bfce" # If newer MinerFileVersion and hash does not math MPM will trigger an automatick binary update (if Uri is present)
$Uri = ""
$ManualUri = "https://mega.nz/#!5WACFRTT!tV1vUsFdBIDqCzBrcMoXVR2G9YHD6xqct5QB2nBiuzM"
$WebLink = "https://bitcointalk.org/index.php?topic=3378390.0;all"
$MinerFeeInPercent = 1 # Fixed at 1%. Dev fee will start randomly when miner is first started. After 1% of time mined then automatically switches back to user pool 

if ($Info) {
    # Just return info about the miner for use in setup
    # attributes without a curresponding settings entry are read-only by the GUI, to determine variable type use .GetType().FullName
    return [PSCustomObject]@{
        MinerFileVersion  = $MinerFileVersion
        MinerBinaryInfo   = $MinerBinaryInfo
        Uri               = $Uri
        ManualUri         = $ManualUri
        Type              = $Type
        Path              = $Path
        Port              = $Port
        WebLink           = $WebLink
        MinerFeeInPercent = $MinerFeeInPercent
        Settings          = @(
            [PSCustomObject]@{
                Name        = "IgnoreMinerFee"
                ControlType = "switch"
                Default     = $false
                Description = "Miner contains dev fee $($MinerFeeInPercent)%. Tick to ignore miner fees in internal calculations. "
                Tooltip     = "Miner does not allow to disable miner dev fee"
            },
			[PSCustomObject]@{
                Name        = "IgnoreHWModel"
                Required    = $false
                ControlType = "string[0,$($Devices.$Type.count)]"
                Default     = $DefaultMinerConfig.IgnoreHWModel
                Description = "List of hardware models you do not want to mine with this miner, e.g. 'GeforceGTX1070'. Leave empty to mine with all available hardware. "
                Tooltip     = "Detected $Type miner HW:`n$($Devices.$Type | ForEach-Object {"$($_.Name_Norm): DeviceIDs $($_.DeviceIDs -join ' ,')"})"
            },
            [PSCustomObject]@{
                Name        = "IgnoreDeviceID"
                Required    = $false
                ControlType = "int[0,$($Devices.$Type.DeviceIDs)]"
                Min         = 0
                Max         = $Devices.$Type.DeviceIDs
                Default     = $DefaultMinerConfig.IgnoreDeviceID
                Description = "List of device IDs you do not want to mine with this miner, e.g. '0'. Leave empty to mine with all available hardware. "
                Tooltip     = "Detected $Type miner HW:`n$($Devices.$Type | ForEach-Object {"$($_.Name_Norm): DeviceIDs $($_.DeviceIDs -join ' ,')"})"
            },
            [PSCustomObject]@{
                Name        = "Commands"
                Required    = $false
                ControlType = "PSCustomObject[1,]"
                Default     = $DefaultMinerConfig.Commands
                Description = "Each line defines an algorithm that can be mined with this miner. Optional miner parameters can be added after the '=' sign. "
                Tooltip     = "Note: Most extra parameters must be prefixed with a space`nTo disable an algorithm prefix it with '#'"
            },
            [PSCustomObject]@{
                Name        = "CommonCommands"
                Required    = $false
                ControlType = "string"
                Default     = $DefaultMinerConfig.CommonCommands
                Description = "Optional miner parameter that gets appended to the resulting miner command line (for all algorithms). "
                Tooltip     = "Note: Most extra parameters must be prefixed with a space"
            },
            [PSCustomObject]@{
                Name        = "DoNotMine"
                Required    = $false
                ControlType = "PSCustomObject[0,]"
                Default     = $DefaultMinerConfig.DoNotMine
                Description = "Optional filter parameter per algorithm and pool. MPM will not use the miner for this algorithm at the listed pool. "
                Tooltip     = "Syntax: 'Algorithm_Norm = @(`"Poolname`", `"PoolnameCoins`")"
            }
        )
    }
}

if ($MinerFileVersion -gt $Config.Miners.$Name.MinerFileVersion) {
    $DefaultMinerConfig = [PSCustomObject]@{
        "MinerFileVersion" = $MinerFileVersion
        #"IgnoreHWModel" = @("GPU Model Name", "Another GPU Model Name", e.g "GeforceGTX1070") # Available model names are in $Devices.$Type.Name_Norm, Strings here must match GPU model name reformatted with (Get-Culture).TextInfo.ToTitleCase(($_.Name)) -replace "[^A-Z0-9]"
        "IgnoreHWModel" = @()
        #"IgnoreDeviceID" = @(0, 1) # Available deviceIDs are in $Devices.$Type.DeviceIDs
        "IgnoreDeviceID" = @()
        "Commands" = [PSCustomObject]@{
            "bitcore" = "" #Bitcore
            #"blake2s" = "" #Blake2s - Not Supported
            #"blakecoin" = "" #Blakecoin - Not Supported
            #"c11" = "" #C11 - Not Supported
            #"cryptonight" = "" #CryptoNight - Not Supported; ASIC territory
            "decred" = "" #Decred - NOT TESTED
            #"equihash" = "" #Equihash - Not Supported
            #"ethash" = "" #Ethash - Not Supported
            #"groestl" = "" #Groestl - Not Supported
            #"hmq1725" = "" #HMQ1725 - Not Supported
            #"hsr" = "" #HSR - Not Supported
            "jha" = "" #JHA - NOT TESTED
            #"keccak" = "" #Keccak - Not Supported
            #"keccakc" = "" #Keccakc - Not Supported
            #"lbry" = "" #Lbry - Not Supported
            #"lyra2v2" = "" #Lyra2RE2 - Not Supported
            #"lyra2z" = "" #Lyra2z - Not Supported
            #"myr-gr" = "" #MyriadGroestl - Not Supported
            #"neoscrypt" = "" #NeoScrypt - Not Supported
            #"nist5" = "" #Nist5 is ASIC territory
            #"pascal" = "" #Pascal - Not Supported
            "phi" = "" #PHI
            "poly" = "" #Polytmos - NOT TESTED
            #"qubit" = "" #qubit - Not Supported
            #"quark" = "" #Quark - Not Supported
            #"sib" = "" #Sib - Not Supported
            #"skein" = "" #Skein - Not Supported
            #"skunk" = "" #Skunk - Not Supported
            #"timetravel" = "" #Timetravel - Not Supported
            #"tribus" = "" #Tribus - Not Supported
            "vanilla" = "" #BlakeVanilla - NOT TESTED
            "veltor" = "" #Veltor - NOT TESTED
            #"x11" = "" #X11 - Not Supported
            #"x11evo" = "" #X11evo - Not Supported
            "x12" = "" #X12 - NOT TESTED
            #"x13" = "" #X13 - Not Supported
            "x14" = "" #X14 - NOT TESTED
            "x16r" = "" #Rave
            "x16s" = "" #Pigeon
            #"x17" = "" #X17 - Not Supported
            #"xevan" = "" #Xevan - Not Supported
            #"yescrypt" = "" #Yescrypt - Not Supported
        }
        "CommonCommands" = ""
        "DoNotMine" = [PSCustomObject]@{ # Syntax: "Algorithm" = @("Poolname", "Another_Poolname") 
            #e.g. "equihash" = @("Zpool", "ZpoolCoins")
        }
    }
    if (-not $Config.Miners.$Name.MinerFileVersion) { # new miner, create basic config
        $Config = Add-MinerConfig $Name $DefaultMinerConfig
    }
    else { # Update existing miner config
        try {
            # Execute action, e.g force re-download of binary
            # Should be the first action. If it fails no further update will take place, update will be retried on next loop
            Update-Binaries -RemoveMinerBenchmarkFiles $Config.AutoReBenchmark

            # Read existing config file, do not use $Config because variables are expanded (e.g. $Wallet)
            $NewConfig = Get-Content -Path 'Config.txt' | ConvertFrom-Json -InformationAction SilentlyContinue

            # Always update MinerFileVersion -Force to enforce setting
            $NewConfig.Miners.$Name | Add-member MinerFileVersion $MinerFileVersion -Force

            # Remove config item if in existing config file
            $NewConfig.Miners.$Name.Commands.PSObject.Properties.Remove("myr-gr")
            $NewConfig.Miners.$Name.Commands.PSObject.Properties.Remove("nist5")
            $NewConfig.Miners.$Name.Commands.PSObject.Properties.Remove("cryptonight")
                        
            # Remove miner benchmark files, these are no longer needed
            Remove-MinerBenchmarkFiles -MinerName $Name -Algorithm (Get-Algorithm "cryptonight")
            Remove-MinerBenchmarkFiles -MinerName $Name -Algorithm (Get-Algorithm "nist5")
            Remove-MinerBenchmarkFiles -MinerName $Name -Algorithm (Get-Algorithm "myr-gr")

            # Save config to file
            Write-Config $NewConfig $Name

            # Apply config, must re-read from file to expand variables
            $Config = Get-ChildItemContent "Config.txt" | Select-Object -ExpandProperty Content
        }
        catch {}
    }
}

# Get device list
$Devices.$Type | ForEach-Object {

    if ($DeviceTypeModel -and -not $Config.MinerInstancePerCardModel) {return} # after first loop $DeviceTypeModel is present; generate only one miner
    $DeviceTypeModel = $_

    # Get array of IDs of all devices in device set, returned DeviceIDs are of base $DeviceIdBase representation starting from $DeviceIdOffset
    $DeviceIDs = (Get-DeviceSet)."All"

    if ($DeviceIDs.Count -gt 0) {

        $Config.Miners.$Name.Commands | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Where-Object {$Pools.(Get-Algorithm $_).Protocol -eq "stratum+tcp" -and $Config.Miners.$Name.DoNotMine.$_ -inotcontains $Pools.(Get-Algorithm $_).Name} | ForEach-Object {

            $Algorithm_Norm = Get-Algorithm $_

            if ($Config.MinerInstancePerCardModel -and (Get-Command "Get-CommandPerDeviceSet" -ErrorAction SilentlyContinue)) {
                $Miner_Name = "$Name-$($DeviceTypeModel.Name_Norm)"
                $Commands = Get-CommandPerDeviceSet -Command $Config.Miners.$Name.Commands.$_ # additional command line options for algorithm
            }
            else {
                $Miner_Name = $Name
                $Commands = $Config.Miners.$Name.Commands.$_.Split(";") | Select-Object -Index 0 # additional command line options for algorithm
            }

            $HashRate = $Stats."$($Miner_Name)_$($Algorithm_Norm)_HashRate".Week
            if ($Config.IgnoreMinerFee -or $Config.Miners.$Name.IgnoreMinerFee) {
                $Fees = @($null)
            }
            else {
                $HashRate = $HashRate * (1 - $MinerFeeInPercent / 100)
                $Fees = @($MinerFeeInPercent)
            }

            [PSCustomObject]@{
                Name             = $Miner_Name
                Type             = $Type
                Path             = $Path
                Arguments        = ("-a $_ -o $($Pools.$Algorithm_Norm.Protocol)://$($Pools.$Algorithm_Norm.Host):$($Pools.$Algorithm_Norm.Port) -u $($Pools.$Algorithm_Norm.User) -p $($Pools.$Algorithm_Norm.Pass)$Commands$($Config.Miners.$Name.CommonCommands) -b 127.0.0.1:$($Port) $($Config.Miners.$Name.MinerFeeInPercent) -d $($DeviceIDs -join ',')" -replace "\s+", " ").trim()
                HashRates        = [PSCustomObject]@{$Algorithm_Norm = $Hashrate}
                API              = $Api
                Port             = $Port
                URI              = $Uri
                Fees             = @($Fees)
                Index            = $DeviceTypeModel.DeviceIDs -join ';' # Always list all devices
                ShowMinerWindow  = $Config.ShowMinerWindow
            }
        }
    }
    $Port++ # next higher port for next device
}