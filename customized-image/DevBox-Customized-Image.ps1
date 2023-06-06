
if($args.Count -lt 6){
    Write-Host "The typical command: .\DevBox-Customized-Image.ps1 <image resource group> <location> <image template name> <gallery name> <image definition name> <replicate region>"
    Exit
}

# Destination image resource group  
$imageResourceGroup=$args[0]  

# Location  
$location=$args[1]  

# Image template name  
$imageTemplateName=$args[2]

# Gallery name 
$galleryName=$args[3]

# Image definition name 
$imageDefName =$args[4]

# Additional replication region 
$replRegion2=$args[5] 

# Define the publisher, offer and sku when others want to use your customized image
$imagePubliser="TheCompany123"
$imageOffer="TheOffer123"
$imageSku="TheSku123"
if($args.Count -ge 9){
    $imagePubliser=$args[6] 
    $imageOffer=$args[7] 
    $imageSku=$args[8] 
}

# Image distribution metadata reference name  
$runOutputName="aibCustWinManImg01"  

##################### 1-Install PowerShell module Az.ImageBuilder and Az.ManagedServiceIdentity #####################
Write-Host "1.Install PowerShell module Az.ImageBuilder and Az.ManagedServiceIdentity"
Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
'Az.ImageBuilder', 'Az.ManagedServiceIdentity' | ForEach-Object {Install-Module -Name $_ -AllowPrerelease}

# Get existing context 
$currentAzContext = Get-AzContext  
# Get your current subscription ID.  
$subscriptionID=$currentAzContext.Subscription.Id  

##################### 2-Create a user-assigned identity and set permissions on the resource group #####################
Write-Host "2.Create a user-assigned identity and set permissions on the resource group"
# setup role def names, these need to be unique 
$timeInt=$(get-date -UFormat "%s") 
$imageRoleDefName="Azure Image Builder Image Def"+$timeInt 
$identityName="aibIdentity"+$timeInt 

## Add an Azure PowerShell module to support AzUserAssignedIdentity 
Install-Module -Name Az.ManagedServiceIdentity 

# Create an identity 
New-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Location $location -Name $identityName 

$identityNameResourceId=$(Get-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $identityName).Id 
$identityNamePrincipalId=$(Get-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $identityName).PrincipalId

##################### 3-Assign permissions for the identity to distribute the images #####################
Write-Host "3.Assign permissions for the identity to distribute the images"
$aibRoleImageCreationUrl="https://raw.githubusercontent.com/azure/azvmimagebuilder/master/solutions/12_Creating_AIB_Security_Roles/aibRoleImageCreation.json" 
$aibRoleImageCreationPath = "aibRoleImageCreation.json" 

# Download the configuration 
if (Test-Path $aibRoleImageCreationPath) {
    <# Action to perform if the condition is true #>
    Remove-Item $aibRoleImageCreationPath -Force
    Write-Host "Delete temp file $aibRoleImageCreationPath"
}

Write-Host "imageRoleDefName: $imageRoleDefName"
Invoke-WebRequest -Uri $aibRoleImageCreationUrl -OutFile $aibRoleImageCreationPath -UseBasicParsing
((Get-Content -path $aibRoleImageCreationPath -Raw) -replace '<subscriptionID>',$subscriptionID) | Set-Content -Path $aibRoleImageCreationPath 
((Get-Content -path $aibRoleImageCreationPath -Raw) -replace '<rgName>', $imageResourceGroup) | Set-Content -Path $aibRoleImageCreationPath 
((Get-Content -path $aibRoleImageCreationPath -Raw) -replace 'Azure Image Builder Service Image Creation Role', $imageRoleDefName) | Set-Content -Path $aibRoleImageCreationPath 

# Create a role definition 
if( $null -eq (Get-AzRoleDefinition -Name $imageRoleDefName)) {
    New-AzRoleDefinition -InputFile $aibRoleImageCreationPath

    while($null -eq (Get-AzRoleDefinition -Name $imageRoleDefName)){
        Start-Sleep -Seconds 20
        Write-Host "Wait for Role definition $imageRoleDefName"
    }

    # Please wait for several moments, role definition creation needs to take effect
    Start-Sleep -Seconds 240
}

# Grant the role definition to the VM Image Builder service principal 
Write-Host "identityNamePrincipalId:$identityNamePrincipalId"

if( $null -eq (Get-AzRoleAssignment -ObjectId $identityNamePrincipalId )){
    New-AzRoleAssignment -ObjectId $identityNamePrincipalId -RoleDefinitionName $imageRoleDefName -Scope "/subscriptions/$subscriptionID/resourceGroups/$imageResourceGroup"
}

##################### 4-Create Azure Compute Gallery and Image Definition #####################
Write-Host "4.Create Azure Compute Gallery and Image Definition"
# Create the gallery 
if ( $null -eq (Get-AzGallery -GalleryName $galleryName -ResourceGroupName $imageResourceGroup)){
    Write-Host "Create new Gallery: $galleryName"
    New-AzGallery -GalleryName $galleryName -ResourceGroupName $imageResourceGroup -Location $location 
}

$SecurityType = @{Name='SecurityType';Value='TrustedLaunch'}  
$features = @($SecurityType) 

# Create the image definition
$imageDefinition = $null
try{ #when image definition is not found, it will throw the exception instead of returning $null, so here we catch this exception
    $imageDefinition = Get-AzGalleryImageDefinition -GalleryImageDefinitionName  $imageDefName -GalleryName $galleryName -ResourceGroupName $imageResourceGroup
}catch{
    $imageDefinition = $null
}

if($null -eq $imageDefinition){
    New-AzGalleryImageDefinition -GalleryName $galleryName -ResourceGroupName $imageResourceGroup  -Location $location  -Name $imageDefName  -OsState generalized  -OsType Windows  -Publisher $imagePubliser  -Offer $imageOffer  -Sku $imageSku -Feature $features -HyperVGeneration "V2"
}

$templateFilePath = "aib-template.json"

Copy-Item "aib-template-base.json" -Destination $templateFilePath -Force

(Get-Content -path $templateFilePath -Raw ) -replace '<subscriptionID>',$subscriptionID | Set-Content -Path $templateFilePath 
(Get-Content -path $templateFilePath -Raw ) -replace '<rgName>',$imageResourceGroup | Set-Content -Path $templateFilePath 
(Get-Content -path $templateFilePath -Raw ) -replace '<runOutputName>',$runOutputName | Set-Content -Path $templateFilePath  
(Get-Content -path $templateFilePath -Raw ) -replace '<imageDefName>',$imageDefName | Set-Content -Path $templateFilePath  
(Get-Content -path $templateFilePath -Raw ) -replace '<sharedImageGalName>',$galleryName| Set-Content -Path $templateFilePath  
(Get-Content -path $templateFilePath -Raw ) -replace '<region1>',$location | Set-Content -Path $templateFilePath  
(Get-Content -path $templateFilePath -Raw ) -replace '<region2>',$replRegion2 | Set-Content -Path $templateFilePath  
((Get-Content -path $templateFilePath -Raw) -replace '<imgBuilderId>',$identityNameResourceId) | Set-Content -Path $templateFilePath

##################### 5-Build the Image #####################
Write-Host "5.Build the Image"

while ($null -eq (Get-AzRoleAssignment -ObjectId $identityNamePrincipalId)) {
    Start-Sleep -Seconds 20
    Write-Host "Wait for role assignment to take effect"
}

# submit image template to service
New-AzResourceGroupDeployment  -ResourceGroupName $imageResourceGroup  -TemplateFile $templateFilePath  -Api-Version "2020-02-14"  -imageTemplateName $imageTemplateName  -svclocation $location

Start-Sleep -Seconds 10

# build the image
Invoke-AzResourceAction -ResourceName $imageTemplateName  -ResourceGroupName $imageResourceGroup  -ResourceType Microsoft.VirtualMachineImages/imageTemplates  -ApiVersion "2020-02-14"  -Action Run -Force

Write-Host "Start to build the image. It may take several moments."
while ( (Get-AzImageBuilderTemplate -ImageTemplateName $imageTemplateName -ResourceGroupName $imageResourceGroup).LastRunStatusRunState -ne "Succeeded" ) {
    "Building the image~"
    Start-Sleep -Seconds 30
}

Write-Host "Image building completed!"