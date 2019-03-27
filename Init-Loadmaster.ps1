<#
    .SYNOPSIS
    Sets the initial configuration of KEMP loadmasters. 

    .DESCRIPTION
    Accepts the EULA, retreives an online license,
    sets the password for user bal, configures arbitrary parameters,
    and configures the IP addresses of the network interfaces.

    Use the variables $loadBalancers and $LMParameters to configure the script.
    See comments within the script for further information.
    
    .NOTES

    Version:    1.0
    Author:     Roman Korecky
    Date:       2018-07-09
    Changes:
#>

# Array of LoadMasters to configure

$loadBalancers = @(

    # Each loadmaster is an object

    @{
        # The hostname, the LoadMaster will receive

        hostname = 'KEMP1'

        # The connection property is an object with the connection parameters
        # to connect to the LoadMaster during configuration

        Connection = @{
            
            # LoadBalancer contain the network address of the LoadMaster to configure

            LoadBalancer = '10.0.1.109'

            # LBPort is the port to connection to, normally 443

            LBPort = 443 
        }

        # The NetworkInterfaces property is an array of objects
        # containing the network interfaces to configure

        NetworkInterfaces = @(

            # Each network interface is an object

            @{
                # InterfaceID is the ID of the interface to configure
                # Interface 0 is the management interface

                InterfaceID = 0

                # IPAddress defines the IP adress in CIDR notation
                # e. g. 10.0.1.31/24 for the IP address 10.0.1.31
                # and the subnet mask 255.255.255.0

                IPAddress = '10.0.1.31/24'
            }
            @{
                InterfaceID = 1
                IPAddress = '10.0.2.31/24'
            }
        )
    }
    @{
        hostname = 'KEMP2'
        Connection = @{
            LoadBalancer = '10.0.1.113'
            LBPort = 443 
        }
        NetworkInterfaces = @(
            @{
                InterfaceID = 0
                IPAddress = '10.0.1.32/24'
            }
            @{
                InterfaceID = 1
                IPAddress = '10.0.2.32/24'
            }
        )
    }
    @{
        hostname = 'KEMP3'
        Connection = @{
            LoadBalancer = '10.0.1.112'
            LBPort = 443 
        }
        NetworkInterfaces = @(
            @{
                InterfaceID = 0
                IPAddress = '10.0.1.33/24'
            }
            @{
                InterfaceID = 1
                IPAddress = '10.0.2.33/24'
            }
        )
    }
)

# LMParameters defines common parameters for all LoadMasters

$LMParameters = @(

    # Each parameter is defined as an object with properties

    @{
        # Param is the name of the parameter
        # For a list of supported parameters see
        # https://kemptechnologies.github.io/powershell-sdk-vnext/ps-help.html#Set-LmParameter

        Param = 'ntphost'

        # Value is the value for the parameter

        Value = '10.0.1.1'
    }
    @{
        Param = 'timezone'
        Value = 'Europe/Vienna'
    }
    @{
        Param = 'Dfltgw'
        Value = '10.0.1.254'
    }
    @{
        Param = 'searchlist'
        Value = 'kemp.lab'
    }
    @{
        Param = 'DNSNamesEnable'
        Value = 0
    }
)

# Iterate through all LoadMasters

if ($balPassowrd -eq $null) {
    $balPassword = Read-Host -Prompt 'Password for user bal'
}

$credential = New-Object pscredential(
    'bal', 
    (ConvertTo-SecureString -String $balPassword -AsPlainText -Force)
)

$loadBalancers | ForEach-Object {
    $connection = $PSItem.Connection
    $license = Get-LicenseInfo @connection -Credential $credential

    if($license.Data -eq $null) {

        if ($kempID -eq $null) {
            $kempID = Read-Host -Prompt 'Your KEMP ID'
        }
        if ($kempPassword -eq $null) {
            $kempPassword = Read-Host -Prompt 'Password for KEMP ID'
        }


        #region Accept EULAs

            Write-Verbose "Read first EULA for LoadMaster $($PSItem.LoadBalancer)"
            $eula = Read-LicenseEULA @connection   
            Write-Verbose $eula.Data.Eula.Eula
            Write-Debug "MagicString: $($eula.Data.Eula.MagicString)"

            Write-Verbose "Confirm first EULA for LoadMaster $($PSItem.LoadBalancer) and get second EULA"
            $eula2 = Confirm-LicenseEULA @connection `
                -Magic $eula.Data.Eula.MagicString

            Write-Verbose "Second EULA for LoadMaster$($PSItem.LoadBalancer)"
            Write-Verbose $eula2.Data.Eula2.Eula2
            Write-Debug "MagicString: $($eula2.Data.Eula2.MagicString)"

            Write-Verbose "Confirm second EULA for LoadMaster $($PSItem.LoadBalancer)"
            Confirm-LicenseEULA2 @connection `
                -Magic $eula2.Data.Eula2.MagicString `
                -Accept yes
        #endregion

        #region Get online license
            Write-Verbose "Get online license for LoadMaster $($PSItem.LoadBalancer)"
            Request-LicenseOnline @connection `
                -KempId $kempID `
                -Password $kempPassword
        #endregion

        #region Set initial password
            Write-Verbose "Set password for LoadMaster $($PSItem.LoadBalancer)"
            Set-LicenseInitialPassword @connection -Passwd $balPassword
            $credential = New-Object pscredential(
                'bal', 
                (ConvertTo-SecureString -String $balPassword -AsPlainText -Force)
            )
        #endregion
    }

    # Set hostname
    Set-LmParameter -Param hostname -Value $PSItem.hostname `
        -Credential $credential @connection 

    #region Set other common parameters
        $LMParameters | ForEach-Object {
            Set-LmParameter -Credential $credential @PSItem @Connection
        }
    #endregion

    #region Configure network interfaces

    $PSItem.NetworkInterfaces | ForEach-Object {
        # Set IP address of network interface
        # PSItem contains an object with the properties 
        # InterfaceID and IPAddres
        Set-NetworkInterface @PSItem @connection -Credential $credential

        # If the IP address of interface 0 is changed
        # we have to change the load balancer name for futher actions
        # since interface 0 is the management interface
        if ($PSItem.InterfaceID -eq 0 ) {

            # The split operator splits the IP address at any slash
            # For the pure IP address, we take the the first part
            $connection.LoadBalancer = ($PSItem.IPAddress -split '\/')[0]
        }
    }
    #endregion
}
