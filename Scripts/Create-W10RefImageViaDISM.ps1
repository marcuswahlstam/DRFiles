﻿# Note #1: 
# To service a newer version of WinPE than the OS you are servicing from, for example service Windows 10 v1709 
# from a Windows Server 2016 server, you need a newer DISM version.
# Solution, simply install the latest Windows ADK 10, and use DISM from that version
#
# Note #2:
# Due to how applying updates offline works, you can not use Cleanup-Image /StartComponentCleanup /ResetBase with DISM to reduce the size
# This is because there are pending operations after applying updates offline.
#
# Note #3:
# Adding updates offline typically increases the WIM size with 1 - 1.5 GB
#
# Note #4:
# If your Windows OS already have a newer version of dism, uncomment the below line, and comment out line 18 and 19
# $DISMFile = 'dism.exe'

# Configuring the script to use the Windows ADK 10 version of DISM
$DISMFile = 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\DISM\dism.exe'
If (!(Test-Path $DISMFile)){ Write-Warning "DISM in Windows ADK not found, aborting..."; Break }

# Set additional parameters
$ISO = "C:\Setup\ISO\Windows 10 Business Editions x64 v1709.iso"
$ServicingUpdate = "C:\Setup\Updates\windows10.0-kb4132650-x64_80c6e23ef266c2848e69946133cc800a5ab9d6b3.msu"
$AdobeFlashUpdate = "C:\Setup\Updates\windows10.0-kb4093110-x64_2422543693a0939d7f7113ac13d97a272a3770bb.msu"
$MonthlyCU = "C:\Setup\Updates\windows10.0-kb4103714-x64_97bad62ead2010977fa1e9b5226e77dd9e5a5cb7.msu"
$ImageMountFolder = "C:\Mount_Image"
$BootImageMountFolder = "C:\Mount_BootImage"
$WIMImageFolder = "C:\WIMs"
$TmpImage = "$WIMImageFolder\tmp_install.wim"
$RefImage = "$WIMImageFolder\install.wim"
$BootImage = "$WIMImageFolder\boot.wim"

# Verify that files and folder exist
if (!(Test-Path -path $ISO)) {Write-Warning "Could not find Windows 10 ISO file. Aborting...";Break}
if (!(Test-Path -path $ServicingUpdate)) {Write-Warning "Could not find Servicing Update for Windows 10. Aborting...";Break}
if (!(Test-Path -path $AdobeFLashUpdate)) {Write-Warning "Could not find Adobe Flash Update for Windows 10. Aborting...";Break}
if (!(Test-Path -path $MonthlyCU)) {Write-Warning "Could not find Monthly Update for Windows 10. Aborting...";Break}
if (!(Test-Path -path $ImageMountFolder)) {New-Item -path $ImageMountFolder -ItemType Directory}
if (!(Test-Path -path $BootImageMountFolder)) {New-Item -path $BootImageMountFolder -ItemType Directory}
if (!(Test-Path -path $WIMImageFolder)) {New-Item -path $WIMImageFolder -ItemType Directory}

# Check Windows Version
$OSCaption = (Get-WmiObject win32_operatingsystem).caption
If ($OSCaption -like "Microsoft Windows 10*" -or $OSCaption -like "Microsoft Windows Server 2016*")
{
    # All OK
}
Else
{
    Write-Warning "$Env:Computername Oupps, you really should use Windows 10 or Windows Server 2016 when servicing Windows 10 offline"
    Write-Warning "$Env:Computername Aborting script..."
    Break
}

# Mount the Windows 10 ISO
Mount-DiskImage -ImagePath $ISO
$ISOImage = Get-DiskImage -ImagePath $ISO | Get-Volume
$ISODrive = [string]$ISOImage.DriveLetter+":"

# Export the Windows 10 Enterprise index to a new (temporary) WIM
Export-WindowsImage -SourceImagePath "$ISODrive\Sources\install.wim" -SourceName "Windows 10 Enterprise" -DestinationImagePath $TmpImage

# Mount the Windows 10 Enterprise image/index with the Optimize option (reduces initial mount time)
Mount-WindowsImage -ImagePath $TmpImage -Index 1 -Path $ImageMountFolder -Optimize

# Add .NET Framework 3.5.1 to the Windows 10 Enterprise image 
& $DISMFile /Image:$ImageMountFolder /Add-Package /PackagePath:$ISODrive\sources\sxs\microsoft-windows-netfx3-ondemand-package.cab 

# Add the Updates to the Windows 10 Enterprise image
& $DISMFile /Image:$ImageMountFolder /Add-Package /PackagePath:$ServicingUpdate
& $DISMFile /Image:$ImageMountFolder /Add-Package /PackagePath:$AdobeFlashUpdate
& $DISMFile /Image:$ImageMountFolder /Add-Package /PackagePath:$MonthlyCU

# Mount the WinRE Image (which resides inside the mounted Windows 10 image)
Mount-WindowsImage -ImagePath $ImageMountFolder\Windows\System32\Recovery\winre.wim -Index 1 -Path $BootImageMountFolder

# Add the Updates to the WinRE image (adds about 100 MB in size)
& $DISMFile /Image:$BootImageMountFolder /Add-Package /PackagePath:$ServicingUpdate
& $DISMFile /Image:$BootImageMountFolder /Add-Package /PackagePath:$MonthlyCU

# Dismount the WinRE image
DisMount-WindowsImage -Path $BootImageMountFolder -Save

# Dismount the Windows 10 Enterprise image
DisMount-WindowsImage -Path $ImageMountFolder -Save

# Export the Windows 10 Enterprise index to a new WIM (the export operation reduces the WIM size with about 400 - 500 MB)
Export-WindowsImage -SourceImagePath $TmpImage -SourceName "Windows 10 Enterprise" -DestinationImagePath $RefImage

# Remove the temporary WIM
if (Test-Path -path $TmpImage) {Remove-Item -Path $TmpImage -Force}

# Mount index 2 of the Windows 10 boot image (boot.wim)
Copy-Item "$ISODrive\Sources\boot.wim" $WIMImageFolder
Attrib -r $BootImage 
Mount-WindowsImage -ImagePath $BootImage -Index 2 -Path $BootImageMountFolder

# Add the Updates to the boot image
& $DISMFile /Image:$BootImageMountFolder /Add-Package /PackagePath:$ServicingUpdate
& $DISMFile /Image:$BootImageMountFolder /Add-Package /PackagePath:$MonthlyCU

# Dismount the boot image
DisMount-WindowsImage -Path $BootImageMountFolder -Save

# Dismount the Windows 10 ISO
Dismount-DiskImage -ImagePath $ISO 