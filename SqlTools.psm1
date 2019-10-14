Function Copy-FileToRemote {

<#
.SYNOPSIS
    Short description
.DESCRIPTION
    Long description
.EXAMPLE
    PS C:\> <example usage>
    Explanation of what the example does
.INPUTS
    Inputs (if any)
.OUTPUTS
    Output (if any)
.NOTES
    General notes
#>

    [Cmdletbinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true,
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true,
                   HelpMessage="Enter path of file to copy")]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path $_ -PathType Leaf})]
        [string[]]$Path,

        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   HelpMessage="Enter destination path on remote computer(s)")]
        [ValidateNotNullOrEmpty()]
        [string]$Destination,

        [Parameter(Mandatory=$true,
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true,
                   HelpMessage="Enter computer(s) name.")]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName,

        [PSCredential]$Credential = [pscredential]::Empty,

        [switch]$Passthru
    )

    Begin {
        Write-Verbose -Message "Starting $($MyInvocation.MyCommand)"
        Write-Verbose -Message "Bound Parameters"
        Write-Verbose -Message ($PSBoundParameters | Out-String)

        Write-Verbose "Creating remote sessions"
        $myRemoteSessions = New-PSSession -ComputerName $ComputerName -Credential $Credential
        
        Write-Verbose "Verifying destination path $($Destination) on remote computer(s)"
        #Test to see if destination path exist on remote machine and is of valid syntax
        foreach ($session in $myRemoteSessions) {
            #Script block to create new directory if one does not exist
            $scriptBlock = {
                [Cmdletbinding(SupportsShouldProcess=$true)]
                Param ([string]$NewDir, [bool]$Passthru, [bool]$WhatIfPreference)
                
                $target = "[$env:COMPUTERNAME]"
                $action = "Create new directory: $NewDir"
                
                if ($PSCmdlet.ShouldProcess($target, $action)) {
                    New-Item -Path $NewDir -ItemType Directory -Credential $using:Credential | Out-Null

                    if ($Passthru) {
                        Get-Item -Path $NewDir
                    } #if Passthru
                } #if ShouldProcess
            } #End scriptBlock

            #Check to see if directory does not exist on remote computer.
            #If one does not exist, prompt user to create a new directory to copy the file to.
            if (-not (( Invoke-command -ScriptBlock {Test-Path -Path $using:Destination -PathType Container} -Session $session ))) {
                
                Write-Warning -Message "$($Destination) does not exist on $($session.ComputerName)"
                do {
                    try {
                        $strOk = $true
                        [string]$result = Read-Host "Do you want to create the directory $Destination on $($session.ComputerName): Yes/No?"
                        if ($result -eq "") {
                            Write-Warning -Message "Please enter 'Yes' or 'No'"
                        }
                    }
                    catch {
                        $strOk = $false
                    }
                } until (($result -contains "Yes" -or $result -contains "No") -and $strOk)
                
                
                try {
                    if ($result.Contains("Yes")) {
                        Invoke-Command -ScriptBlock $scriptBlock `
                                       -ArgumentList @($Destination, $Passthru, $WhatIfPreference) `
                                       -Session $session `
                                       -ErrorAction Stop
                    }
                    else {
                        $session | Remove-PSSession -WhatIf:$false
                    }
                }
                catch {
                    $msg = "Command failed $($_.Exception.Message)"
                    Write-Warning $msg
                 } #End try\catch
            } #if Invoke-Command
        } #End foreach
        $myRemoteSessions = $myRemoteSessions | Where-Object -FilterScript {$_.State -eq "Opened"}
        if ($null -eq $myRemoteSessions) {
            Write-Warning -Message "All PSSession have been closed. Script will now exit and close the console."
            Start-Sleep -Seconds 5
            exit
        }
        Write-Verbose ($myRemoteSessions | Out-String)
    } #Begin

    Process {
        foreach ($item in $Path) {
            #Normalize the path to a windows powershell provider type path.
            #This creates a consistency for use to use the file path in a way that powershell works.
            $itemPath = $Path | Convert-Path

            $fileContent = [System.IO.File]::ReadAllBytes($itemPath)

            $fileName = Split-Path -Path $itemPath -Leaf

            $destinationPath = Join-Path -Path $Destination -ChildPath $fileName
            
            Write-Verbose "Copying $itemPath to $destinationPath"

            #Script block that will be declared on remote computer
            $scriptBlock = {
                [Cmdletbinding(SupportsShouldProcess=$true)]
                Param ([bool]$Passthru, [bool]$WhatIfPreference)

                if (-not (Test-Path -Path $using:Destination)) {
                    Write-Warning "[$env:COMPUTERNAME] cant find path to $using:Destination"
                    return
                }

                $target = "[$env:COMPUTERNAME] $using:Destination"
                $action = "Copy remote file"

                if ($PSCmdlet.ShouldProcess($target, $action)) {
                    [System.IO.File]::WriteAllBytes($using:destinationPath, $using:fileContent)

                    if ($Passthru) {
                        Get-Item -Path $using:destinationPath
                    }
                } #if ShouldProcess
            } #End scriptBlock

            try {
                Invoke-Command -ScriptBlock $scriptBlock `
                               -ArgumentList @($Passthru, $WhatIfPreference) `
                               -Session $myRemoteSessions `
                               -ErrorAction Stop
            }
            catch {
                $msg = "Command failed $($_.Exception.Message)"
                Write-Warning -Message $msg
            } #End try\catch
        } #foreach $item
    } #Process

    End {
        Write-Verbose "Removing PSSession(s)"
        if ($myRemoteSessions) {
            $myRemoteSessions | Remove-PSSession -WhatIf:$false
        }
        Write-Verbose "Ending $($MyInvocation.MyCommand)"
    } #End
} #End Copy-FileToRemote

Function Dismount-SqlDataBase {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact="High")]
    Param (
        [Parameter()]
        [string]$ServerInstance,

        [Parameter()]
        [string]$Database,

        [Parameter()]
        [bool]$UpdateStatistics,

        [Parameter()]
        [bool]$RemoveFullTextIndexFile

    )

    Begin {
        Write-Verbose "Starting $($Myinvocation.MyCommand)"
        Write-Verbose "Bound Parameters"
        Write-Verbose ($PSBoundParameters | Out-String)

        Write-Verbose "Creating connection to $($ServerInstance)"
        $connection = New-Object -TypeName "System.Data.SqlClient.SqlConnection"
        $connectionString = "Server=$ServerInstance; Database=$Database; Trusted_Connection=True"
        $connection.ConnectionString = $connectionString
        Write-Verbose "Connection string is $($connection.ConnectionString)"

        $server = New-Object -TypeName "Microsoft.SqlServer.Management.SMO.Server" -ArgumentList $connection

        #Validate and test that server is online and ready to use.
        try {
            $server.ConnectionContext.Connect()
            if (-not ($server.Status -eq [Microsoft.SqlServer.Management.SMO.ServerStatus]::Online)) {
                throw "$server is currently not in a `'online`' status. $server`'s current status is $($server.status)."
            }
            try {
                #Assume the database is ready to detach until proven otherwise
                $IsReadyToDetach = $true
                if (-not ($server.Databases["$Database"].State -eq [Microsoft.SqlServer.Management.SMO.SqlSMOState]::Existing)) {
                    $IsReadyToDetach = $false
                    throw "$($server.Databases[$Database]) does not exist"
                }
                if (-not ($server.Databases["$Database"].Status -eq [Microsoft.SqlServer.Management.SMO.DatabaseStatus]::Normal)) {
                    $IsReadyToDetach = $false
                    throw "$($server.Databases[$Database]) is not in a `"Normal`" status"
                }
            }
            catch {
                $msg = "Database validation failed: $($_.Exception.Message)"
                Write-Output $msg
            }
        }
        catch [Microsoft.SqlServer.Management.Common.ConnectionFailureException] {
            $msg = "$($_.Exception.Message)"
            Write-Output $msg
        } #End try

        #Validate user is owner and has proper permission to detach database.
        #Assume user is owner of the database until proven otherwise.
        try {
            $IsOwner = $true
            if (-not ($($server.Databases[$Database].IsDbOwner -eq $true))) {
                $IsOwner = $false
                throw "$($server.Credentials.Identity) does not have permission to detach $($server.Databases[$Database])"
            }
        }
        catch {
            $msg = "Validation failed: $($_.Exception.Message)"
            Write-Output $msg
        }
    } #End Begin

    Process {
        #Values for -WhatIf
        $target = $server.Databases[$Database]
        $action = "Detach Database"

        if ($IsReadyToDetach -and $IsOwner) {
            if ($PSCmdlet.ShouldProcess($target, $action)) {
                Write-Verbose "Performing the operation `"DetachDatabase`" on $($Server.Databases[$Database])"
                try {
                    $ErrorActionPreference = 'Stop'
                    $server.DetachDatabase($Database, $UpdateStatistics, $RemoveFullTextIndexFile)
                    $ErrorActionPreference = 'Continue'
                }
                catch {
                    $msg = "Detaching database failed on $($Server.Databases[$Database]) $($_.Exception.Message)"
                    Write-Output $msg
                }
            }
        }
    } #End Process

    End {
        Write-Verbose "Disconnecting from $($server.Name)"
        #Explicitly disconnect from the database.
        $server.ConnectionContext.AutoDisconnectMode = [Microsoft.SqlServer.Management.Common.AutoDisConnectMode]::NoAutoDisconnect
        $server.ConnectionContext.Disconnect()
        Write-Verbose "Ending $($MyInvocation.MyCommand)"
    } #End End
} #End Dismount-SqlDataBase

Function Mount-SqlDataBase {

    #######Note: 10/9/2019 - Function goes to should process even if EnumDetachedDatabaseFiles fails.
<#
.SYNOPSIS
Attachs a Sql database to either a local or remote Sql Server Instance.
.DESCRIPTION
Mount-SqlDataBase uses the source server's Sql Instance to gather the required data and log files
that are necessary to attach the database onto either a local or remote Sql Server Instance. This command
can also describe a new owner for the database with the -NewOwner and -NewDBOwnerName parameter.

NOTE: In order to attach a database on a machine make sure the data and log files of the database
are copied into a new location on disk that the machine can access. This also goes for attaching to a local instance.
Otherwise, the command will fail, for the machine cannot access the files it needs to attach the database. 
Use the Copy-FileToRemote cmdlet if you need to copy files over to your target machine.
.PARAMETER SourceInstance
Specifies the name of the Sql Server Instance where the data and log files originate.
Can be repersented like "ServerName\Instance" or "ServerName".
.PARAMETER Database
The name of the database that will be attached on the destination machine.
.PARAMETER DataFile
The path on the source Sql instance that contains the data file for the database. Database files commonly end with .mdf.
.PARAMETER DestinationInstance
The Sql Instance that the database will be attached on.
.PARAMETER DestinationDataFolder
The folder on the destination machine that contains the data and log files that are necessary to attach the database.
.PARAMETER NewOwner
Indicates that this cmdlet will use the overloaded method of AttachDatabase to specifiy a new database owner's name.
.PARAMETER NewDBOwnerName
The name of the new database owner for the database that will attached to the destination Sql Instance.

.EXAMPLE
PS C:\> Mount-SqlDatabase -SourceInstance Sql01\Sql1 -Database DatabaseName -DataFile C:\DATA\DatabaseName.mdf -DestinationInstance Sql02\Sql2 -DestinationDataFolder C:\DATA
#>

    [Cmdletbinding(SupportsShouldProcess=$true, ConfirmImpact="High")]
    Param (
        [Parameter()]
        [string]$SourceInstance,

        [Parameter()]
        [string]$Database,

        [Parameter()]
        [string]$DataFile,

        [Parameter()]
        [string]$DestinationInstance,

        [Parameter()]
        [string]$DestinationDataFolder,

        [Parameter()]
        [switch]$NewOwner,

        [Parameter()]
        [string]$NewDBOwnerName,

        [Parameter()]
        [switch]$Passthru
    )

    Begin {

        Write-Verbose "Starting $($Myinvocation.MyCommand)"
        Write-Verbose "Bound Parameters"
        Write-Verbose ($PSBoundParameters | Out-String)

        #Connecting to source instance
        Write-Verbose "Creating connection to source instance $($SourceInstance)"
        $connection = New-Object -TypeName System.Data.SqlClient.SqlConnection
        $connectionString = "Server=$SourceInstance; Database=; Trusted_Connection=True"
        $connection.ConnectionString = $connectionString
        $sourceServer = New-Object -TypeName Microsoft.SqlServer.Management.SMO.Server -ArgumentList $connection

        #Connecting to destination instance
        Write-Verbose "Creating connection to destination instance $($DestinationInstance)"
        $connection = New-Object -TypeName System.Data.SqlClient.SqlConnection 
        $connectionString = "Server=$DestinationInstance; Database=; Trusted_Connection=True"
        $connection.ConnectionString = $connectionString
        $destinationServer = New-Object -TypeName Microsoft.SqlServer.Management.SMO.Server -ArgumentList $connection

        $serverList = New-Object System.Collections.Generic.List[Microsoft.SqlServer.Management.SMO.Server]
        $serverList.Add($sourceServer)
        $serverList.Add($destinationServer)

        foreach ($server in $serverList) {
            #Validate connection to server
            try {
                $server.ConnectionContext.Connect()
                try {
                    #Validate that server is online and ready for use.
                    if (-not ($server.Status -eq [Microsoft.SqlServer.Management.SMO.ServerStatus]::Online)) {
                    throw "$server is currently not in a `'online`' status. $server`'s current status is $($server.status)."
                    }
                }
                catch {
                    $msg = "$($_.Exception.Message)"
                    Write-Output $msg
                } #End try/catch
            }
            catch [Microsoft.SqlServer.Management.Common.ConnectionFailureException] {
                $msg = "$($_.Exception.Message)"
                Write-Output $msg
            } #End try/catch
        } #End foreach $server
    } #End Begin

    Process {
        #Storage for primary, secondary, and log file information
        $files = New-Object -TypeName System.Collections.Specialized.StringCollection

        $dataFilesCurrentPath = $sourceServer.EnumDetachedDatabaseFiles($DataFile)
        $logFileCurrentPath = $sourceServer.EnumDetachedLogFiles($DataFile)
        Write-Verbose "Data and log files current paths: `n $dataFilesCurrentPath `n $logFileCurrentPath"

        try {
            #Collect data and log files related to the specific mdf file
            $dataFilesCurrentPath | 
            ForEach-Object -Process {
                $newFile = Join-Path -Path $DestinationDataFolder -ChildPath (Split-Path -Path $_ -Leaf)
                $files.Add($newFile) | Out-Null
            }

            $logFileCurrentPath | 
            ForEach-Object -Process {
                $newFile = Join-Path -Path $DestinationDataFolder -ChildPath (Split-Path -Path $_ -Leaf)
                $files.Add($newFile) | Out-Null
            }
            Write-Verbose "Data and log files new paths:"
            foreach ($file in $files) {
                Write-Verbose $file
            }
        }
        catch [Microsoft.SqlServer.Management.SMO.FailedOperationException] {
            $msg = "$($_.Exception.Message)"
            Write-Output $msg
        } #End try/catch

        try {
            #Validate that the database is not already attached on this instance
            if ($destinationServer.Databases[$Database].State -eq [Microsoft.SqlServer.Management.SMO.SqlSMOState]::Existing) {
                throw "$($destinationServer.Databases[$Database]) is already attached."
            }
            try {
                #Set values for -WhatIf
                $target = $destinationServer
                $action = "Attach database"

                if ($NewOwner) {
                    if ($PSCmdlet.ShouldProcess($target, $action)) {
                        $destinationServer.AttachDatabase($Database, $files, $NewDBOwnerName)
                        if ($Passthru) {
                            Write-Output $destinationServer.Databases[$Database]
                        }
                    }
                }
                if ($PSCmdlet.ShouldProcess($target, $action)) {
                    $destinationServer.AttachDatabase($Database, $files)
                    if ($Passthru) {
                        Write-Output $destinationServer.Databases[$Database]
                    }
                }
            }
            catch [Microsoft.SqlServer.Management.SMO.FailedOperationException] {
                $msg = "$($_.Exception.Message)"
                Write-Output $msg
            } #End try/catch
        }
        catch {
            $msg = "Database validation failed: $($_.Exception.Message)"
            Write-Output $msg
        } #End try/catch

    } #End Process

    End {
        foreach ($server in $serverList) {
            Write-Verbose "Disconnecting from $($server.Name)"
            #Explicitly disconnect from the database.
            $server.ConnectionContext.AutoDisconnectMode = [Microsoft.SqlServer.Management.Common.AutoDisConnectMode]::NoAutoDisconnect
            $server.ConnectionContext.Disconnect()
        }
        Write-Verbose "Ending $($MyInvocation.MyCommand)"
    }
} #End Mount-SqlDataBase

Export-ModuleMember -Function Copy-FileToRemote,
                              Dismount-SqlDataBase,
                              Mount-SqlDataBase