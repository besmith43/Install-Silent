param (
    [Parameter(Mandatory = $true)]
    [string]$executable,
    [string]$executablearg,
    [Parameter(Mandatory = $true,
				   ValueFromPipeline = $true,
				   ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [Alias('SCCMID','ADOU')]
    [string[]]$hostnames,
    [System.Management.Automation.PSCredential]$Credential = $(Get-Credential)
)

function install-executable {
    param (
        [string]$exe,
        [string]$exeargs,
        [string]$hostname,
        [System.Management.Automation.PSCredential]$creds
    )

    write-host "Starting Function with $hostname"

    if ($(Test-Connection -ComputerName $hostname -quiet))
    {
        write-host "Connecting to $hostname over PSSession"

        $session = New-PSSession -ComputerName $hostname
    
        if (!$session)
        {
            write-host "PSSession failed to $hostname"
            return $false
        }
    }
    else 
    {
        write-host "$hostname is not online"
        return $false
    }

    write-host "creating folder structure on $hostname"

    invoke-command -Session $session -ScriptBlock {
        if (!$(test-path C:\Temp))
        {
            new-item -itemtype Directory -path C:\Temp
            $(get-item -path C:\Temp -Force).attributes = "Hidden"
        }

        if (!$(test-path -path "C:\Temp\Bin\"))
        { 
            new-item -ItemType Directory -path "C:\Temp\Bin\"
        }
    }

    write-host "Copying $exe to $hostname"

    Copy-Item -ToSession $session -Path "$PSScriptRoot\$exe" -Destination "C:\Temp\Bin"

    write-host "Running $exe on $hostname"

    invoke-command -Session $session -ScriptBlock {
        set-location -path 'C:\Temp\Bin'
        start-process -filepath "C:\Temp\Bin\$using:exe" -ArgumentList "$using:exeargs" -wait
    }

    write-host "Disconnecting from $hostname"

    Remove-PSSession -Session $session

    return $true
}

$installedlist = $executable.remove($($executable.length - 4), 4)
$installedlist = "$installedlist.txt"

if (!$executablearg)
{
    $answer = Read-Host -Prompt "Does this executable require commandline arguments (Y/N)"

    if ($answer -eq "y")
    {
        $executablearg = Read-Host -Prompt "What is the required argument?"
    }
}

if ($(test-path -path $PSScriptRoot\$installedlist -PathType Leaf))
{
    $templist = Get-Content -path $PSScriptRoot\$installedlist

    $list = @()

    foreach ($line in $templist)
    {
        $list += $line
    }
}
else 
{
    $list = @()
}

if ($(get-module -ListAvailable | Where-Object { $_.name -eq "ActiveDirectory"}))
{
    import-module -name ActiveDirectory

    if ($hostnames)
    {
        foreach ($comp in $hostnames)
        {
            [string]$comp_string = Out-String -InputObject $comp

            if ($comp_string -like "*name*")
            {
                $comp = $comp.split("=")
                $comp = $comp[1].split("}")
                $comp = $comp[0]
            }

            if ($(get-adcomputer -filter { Name -eq $comp }))
            {
                if ($comp -match $list)
                {
                    $success = install-executable -exe $executable -exeargs $executablearg -hostname $comp -creds $Credential
                    
                    if ($success)
                    {
                        out-file -FilePath $PSScriptRoot\$installedlist -append -InputObject $comp
                    }
                }
            }
            else 
            {
                write-host "$comp is not in Active Directory"    
            }
        }
    }
}
else 
{
    write-host "Powershell Active Directory is not available"
    exit    
}