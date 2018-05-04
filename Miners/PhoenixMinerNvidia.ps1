using module ..\Include.psm1

param(
    [PSCustomObject]$Pools,
    [PSCustomObject]$Stats,
    [PSCustomObject]$Config,
    [PSCustomObject]$Devices
)

# Compatibility check with old MPM builds
if (-not $Config.Miners) {return}

$Name = "$(Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName)"
$Path = ".\Bin\PhoenixMiner\PhoenixMiner.exe"
$Type = "NVIDIA"
$API  = "Claymore"
$Port = 23334
$DeviceIdBase = 16 # DeviceIDs are in decimal format
$DeviceIdOffset = 1 # DeviceIDs start at 1

$MinerFileVersion = "2018050400" # Format: YYYYMMDD[TwoDigitCounter], higher value will trigger config file update
$MinerBinaryInfo = "PhoenixMiner 2.9e: fastest Ethereum/Ethash miner with lowest devfee"
$MinerBinaryHash = "a531b7b0bb925173d3ea2976b72f3d280f64751bdb094d5bb980553dfa85fb07" # If newer MinerFileVersion and hash does not math MPM will trigger an automatick binary update (if Uri is present)
$Uri = ""
$ManualUri = "https://mega.nz/#F!2VskDJrI!lsQsz1CdDe8x5cH3L8QaBw"
$WebLink = "https://bitcointalk.org/index.php?topic=2647654.0" # See here for more information about the miner
$MinerFeeInPercent = 90*60/35/100 # Fixed, after every 90 minutes the miner will mine for the developers for 35 seconds

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
                ControlType = "int[0,$($Devices.$Type.DeviceIDs)]"
                Min         = 0
                Max         = $Devices.$Type.DeviceIDs
                Default     = $DefaultMinerConfig.IgnoreHWModel
                Description = "List of hardware models you do not want to mine with this miner, e.g. 'GeforceGTX1070'. Leave empty to mine with all available hardware. "
                Tooltip     = "Detected $Type miner HW:`n$($Devices.$Type | ForEach-Object {"$($_.Name_Norm): DeviceIDs $($_.DeviceIDs -join ' ,')"})"
            },
            [PSCustomObject]@{
                Name        = "IgnoreDeviceID"
                Required    = $false
                ControlType = "int[0,$($Devices.$Type.DeviceIDs)];0;$($Devices.$Type.DeviceIDs)"
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
    # Create default miner config, required for setup
    $DefaultMinerConfig = [PSCustomObject]@{
        "MinerFileVersion" = $MinerFileVersion
        #"IgnoreHWModel" = @("GPU Model Name", "Another GPU Model Name", e.g "GeforceGTX1070") # Available model names are in $Devices.$Type.Name_Norm, Strings here must match GPU model name reformatted with (Get-Culture).TextInfo.ToTitleCase(($_.Name)) -replace "[^A-Z0-9]"
        "IgnoreHWModel" = @()
        #"IgnoreDeviceID" = @(0, 1) # Available deviceIDs are in $Devices.$Type.DeviceIDs
        "IgnoreDeviceID" = @()
        "Commands" = [PSCustomObject]@{
            "Ethash"    = "" #Ethash
            "Ethash2gb" = "" #Ethash2gb
            "Ethash3gb" = "" #Ethash3gb
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

    # Get list of active devices
    $DeviceSet = Get-DeviceSet

    $Config.Miners.$Name.Commands | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Where-Object {$Pools.(Get-Algorithm $_).Protocol -eq "stratum+tcp" -and $Config.Miners.$Name.DoNotMine.$_ -inotcontains $Pools.(Get-Algorithm $_).Name} | ForEach-Object {

        $Algorithm_Norm = Get-Algorithm $_

        # Retrieve array of all DeviceIDs in DeviceSet, returned DeviceIDs are of base $DeviceIdBase representation starting from $DeviceIdOffset
        Switch ($Algorithm_Norm) { # default is all devices, ethash has a 4GB minimum memory limit
            "Ethash"    {$DeviceIDs = $DeviceSet."4gb"}
            "Ethash3gb" {$DeviceIDs = $DeviceSet."3gb"}
            default     {$DeviceIDs = $DeviceSet."All"}
        }

        if ($DeviceIDs.Count -gt 0) {
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
                $DisableMinerFee = " --no-devfee"
            }
            else {
                $HashRate = $HashRate * (1 - $MinerFeeInPercent / 100)
                $Fees = @($MinerFeeInPercent)
            }
            
            [PSCustomObject]@{
                Name             = $Miner_Name
                Type             = $Type
                Path             = $Path
                Arguments        = ("-rmode 0 -cdmport 23334 -cdm 1 -pool $($Pools.$Algorithm_Norm.Host):$($Pools.$Algorithm_Norm.Port) -wal $($Pools.$Algorithm_Norm.User) -pass $($Pools.$Algorithm_Norm.Pass)$Commands$($Config.Miners.$Name.CommonCommands) -proto 4 -coin auto -gpus $($DeviceIDs -join ',')" -replace "\s+", " ").trim()
                HashRates        = [PSCustomObject]@{$Algorithm_Norm = $Stats."$($Miner_Name)_$($Algorithm_Norm)_HashRate".Week}
                API              = $Api
                Port             = $Port
                URI              = $Uri
                Fees             = $Fees
                Index            = $DeviceTypeModel.DeviceIDs -join ';' # Always list all devices
                ShowMinerWindow  = $Config.ShowMinerWindow
            }
        }
    }
    $Port++ # next higher port for next device
}