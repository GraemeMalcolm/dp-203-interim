Clear-Host
write-host "Starting script at $(Get-Date)"

# Handle cases where the user has multiple subscriptions
$subs = Get-AzSubscription | Select-Object
if($subs.GetType().IsArray -and $subs.length -gt 1){
    Write-Host "You have multiple Azure subscriptions - please select the one you want to use:"
    for($i = 0; $i -lt $subs.length; $i++)
    {
            Write-Host "[$($i)]: $($subs[$i].Name) (ID = $($subs[$i].Id))"
    }
    $selectedIndex = -1
    $selectedValidIndex = 0
    while ($selectedValidIndex -ne 1)
    {
            $enteredValue = Read-Host("Enter 0 to $($subs.Length - 1)")
            if (-not ([string]::IsNullOrEmpty($enteredValue)))
            {
                if ([int]$enteredValue -in (0..$($subs.Length - 1)))
                {
                    $selectedIndex = [int]$enteredValue
                    $selectedValidIndex = 1
                }
                else
                {
                    Write-Output "Please enter a valid subscription number."
                }
            }
            else
            {
                Write-Output "Please enter a valid subscription number."
            }
    }
    $selectedSub = $subs[$selectedIndex].Id
    Select-AzSubscription -SubscriptionId $selectedSub
    az account set --subscription $selectedSub
}


# Register resource providers
Write-Host "Registering resource providers...";
$provider_list = "Microsoft.Storage", "Microsoft.Compute", "Microsoft.Databricks"
foreach ($provider in $provider_list){
    $result = Register-AzResourceProvider -ProviderNamespace $provider
    $status = $result.RegistrationState
    Write-Host "$provider : $status"
}

# Generate unique random suffix
[string]$suffix =  -join ((48..57) + (97..122) | Get-Random -Count 7 | % {[char]$_})
Write-Host "Your randomly-generated suffix for Azure resources is $suffix"
$resourceGroupName = "dp203-$suffix"

# Get a list of locations for Azure Databricks
Write-Host "Creating Azure Databricks workspace in $resourceGroupName resource group..."
$hot_regions = "australiaeast", "northeurope", "uksouth"
$locations = Get-AzLocation | Where-Object {
    $_.Providers -contains "Microsoft.Databricks" -and
    $_.Providers -contains "Microsoft.Compute" -and
    $_.Location -notin $hot_regions
}

# Try to create an Azure Databricks workspace in a region that has capacity
$max_index = $locations.Count - 1
$rand = (0..$max_index) | Get-Random
$Region = $locations.Get($rand).Location
$stop = 0
$attempt = 0
$tried_regions = New-Object Collections.Generic.List[string]
$tried_regions.Add($Region)
while ($stop -ne 1){
    try {
        write-host "Trying $Region..."
        $attempt = $attempt + 1
        $quota = @(Get-AzVMUsage -Location $Region).where{$_.name.LocalizedValue -match 'Standard DSv2 Family vCPUs'}
        $cores =  $quota.currentvalue
        $maxcores = $quota.limit
        write-host "$cores of $maxcores cores in use."
        if ($maxcores - $cores -lt 8)
        {
            Write-Host "$Region has insufficient capacity."
            $tried_regions.Add($Region)
            $locations = $locations | Where-Object {$_.Location -notin $tried_regions}
            if ($locations.length -gt 0)
            {
                $rand = (0..$($locations.Count - 1)) | Get-Random
                $Region = $locations.Get($rand).Location
            }
            else {
                Write-Host "Could not create a Databricks workspace."
                Write-Host "Use the Azure portal to add one to the $resourceGroupName resource group."
                $stop = 1
            }
        }
        else {
            $dbworkspace = "databricks$suffix$attempt"
            New-AzDatabricksWorkspace -Name $dbworkspace -ResourceGroupName $resourceGroupName -Location $Region -Sku standard -ErrorAction Stop | Out-Null
            $stop = 1
        }
    }
    catch {
      $stop = 0
      Remove-AzDatabricksWorkspace -Name $dbworkspace -ResourceGroupName $resourceGroupName -AsJob | Out-Null
      $tried_regions.Add($Region)
      $locations = $locations | Where-Object {$_.Location -notin $tried_regions}
      if ($locations.length -gt 0)
      {
        $rand = (0..$($locations.Count - 1)) | Get-Random
        $Region = $locations.Get($rand).Location
      }
      else {
          Write-Host "Could not create a Databricks workspace."
          Write-Host "Use the Azure portal to add one to the $resourceGroupName resource group."
          $stop = 1
      }
    }
}

write-host "Script completed at $(Get-Date)"