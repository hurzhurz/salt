<#
.SYNOPSIS
Script that builds a NullSoft Installer package for Salt

.DESCRIPTION
This script takes the contents of the Python Directory that has Salt installed
and creates a NullSoft Installer based on that directory.

.EXAMPLE
build_pkg.ps1 -Version 3005

#>

param(
    [Parameter(Mandatory=$false)]
    [Alias("v")]
    # The version of Salt to be built. If this is not passed, the script will
    # attempt to get it from the git describe command on the Salt source
    # repo
    [String] $Version
)

# Script Preferences
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
$ProgressPreference = "SilentlyContinue"
$ErrorActionPreference = "Stop"

#-------------------------------------------------------------------------------
# Variables
#-------------------------------------------------------------------------------
$PROJECT_DIR    = $(git rev-parse --show-toplevel)
$SCRIPT_DIR     = (Get-ChildItem "$($myInvocation.MyCommand.Definition)").DirectoryName
$BUILD_DIR      = "$SCRIPT_DIR\buildenv"
$INSTALLER_DIR  = "$SCRIPT_DIR\installer"
$PREREQ_DIR     = "$SCRIPT_DIR\prereqs"
$SCRIPTS_DIR    = "$BUILD_DIR\Scripts"
$PYTHON_BIN     = "$SCRIPTS_DIR\python.exe"
$BUILD_SALT_DIR = "$BUILD_DIR\Lib\site-packages\salt"
$BUILD_CONF_DIR = "$BUILD_DIR\configs"
$PY_VERSION     = [Version]((Get-Command $PYTHON_BIN).FileVersionInfo.ProductVersion)
$PY_VERSION     = "$($PY_VERSION.Major).$($PY_VERSION.Minor)"
$NSIS_BIN       = "$( ${env:ProgramFiles(x86)} )\NSIS\makensis.exe"
$ARCH           = $(. $PYTHON_BIN -c "import platform; print(platform.architecture()[0])")

if ( $ARCH -eq "64bit" ) {
    $ARCH         = "AMD64"
    $ARCH_X       = "x64"
    $SALT_DEP_URL = "https://repo.saltproject.io/windows/dependencies/64"
} else {
    $ARCH         = "x86"
    $ARCH_X       = "x86"
    $SALT_DEP_URL = "https://repo.saltproject.io/windows/dependencies/32"
}

#-------------------------------------------------------------------------------
# Verify Salt and Version
#-------------------------------------------------------------------------------
if ( [String]::IsNullOrEmpty($Version) ) {
    $Version = $( git describe ).Trim("v")
    if ( [String]::IsNullOrEmpty($Version) ) {
        Write-Host "Failed to get version from $PROJECT_DIR"
        exit 1
    }
}

#-------------------------------------------------------------------------------
# Start the Script
#-------------------------------------------------------------------------------
Write-Host $("=" * 80)
Write-Host "Build NullSoft Installer for Salt" -ForegroundColor Cyan
Write-Host "- Architecture: $ARCH"
Write-Host "- Salt Version: $Version"
Write-Host $("-" * 80)

#-------------------------------------------------------------------------------
# Verify Environment
#-------------------------------------------------------------------------------
Write-Host "Verifying Python Build: " -NoNewline
if ( Test-Path -Path "$PYTHON_BIN" ) {
    Write-Host "Success" -ForegroundColor Green
} else {
    Write-Host "Failed" -ForegroundColor Red
    exit 1
}

Write-Host "Verifying Salt Installation: " -NoNewline
if ( Test-Path -Path "$BUILD_DIR\salt-minion.exe" ) {
    Write-Host "Success" -ForegroundColor Green
} else {
    Write-Host "Failed" -ForegroundColor Red
    exit 1
}

Write-Host "Verifying NSIS Installation: " -NoNewline
if ( Test-Path -Path "$NSIS_BIN" ) {
    Write-Host "Success" -ForegroundColor Green
} else {
    Write-Host "Failed" -ForegroundColor Red
    exit 1
}

#-------------------------------------------------------------------------------
# Cleaning Build Environment
#-------------------------------------------------------------------------------
if ( Test-Path -Path $BUILD_CONF_DIR) {
    Write-Host "Removing Configs Directory: " -NoNewline
    Remove-Item -Path $BUILD_CONF_DIR -Recurse -Force
    if ( ! (Test-Path -Path $BUILD_CONF_DIR) ) {
        Write-Host "Success" -ForegroundColor Green
    } else {
        Write-Host "Failed" -ForegroundColor Red
        exit 1
    }
}

if ( Test-Path -Path $PREREQ_DIR ) {
    Write-Host "Removing PreReq Directory: " -NoNewline
    Remove-Item -Path $PREREQ_DIR -Recurse -Force
    if ( ! (Test-Path -Path $PREREQ_DIR) ) {
        Write-Host "Success" -ForegroundColor Green
    } else {
        Write-Host "Failed" -ForegroundColor Red
        exit 1
    }
}

#-------------------------------------------------------------------------------
# Staging the Build Environment
#-------------------------------------------------------------------------------
Write-Host "Copying config files from Salt: " -NoNewline
New-Item -Path $BUILD_CONF_DIR -ItemType Directory | Out-Null
Copy-Item -Path "$PROJECT_DIR\conf\minion" -Destination "$BUILD_CONF_DIR"
if ( Test-Path -Path "$BUILD_CONF_DIR\minion" ) {
    Write-Host "Success" -ForegroundColor Green
} else {
    Write-Host "Failed" -ForegroundColor Red
    exit 1
}

Write-Host "Copying SSM to Bin: " -NoNewline
Invoke-WebRequest -Uri "$SALT_DEP_URL/ssm-2.24-103-gdee49fc.exe" -OutFile "$BUILD_DIR\ssm.exe"
if ( Test-Path -Path "$BUILD_DIR\ssm.exe" ) {
    Write-Host "Success" -ForegroundColor Green
} else {
    Write-Host "Failed" -ForegroundColor Red
    exit 1
}

New-Item -Path $PREREQ_DIR -ItemType Directory | Out-Null
Write-Host "Copying VCRedist 2013 $ARCH_X to prereqs: " -NoNewline
$file = "vcredist_$ARCH_X`_2013.exe"
Invoke-WebRequest -Uri "$SALT_DEP_URL/$file" -OutFile "$PREREQ_DIR\$file"
if ( Test-Path -Path "$PREREQ_DIR\$file" ) {
    Write-Host "Success" -ForegroundColor Green
} else {
    Write-Host "Failed" -ForegroundColor Red
    exit 1
}

Write-Host "Copying Universal C Runtimes $ARCH_X to prereqs: " -NoNewline
$file = "ucrt_$ARCH_X.zip"
Invoke-WebRequest -Uri "$SALT_DEP_URL/$file" -OutFile "$PREREQ_DIR\$file"
if ( Test-Path -Path "$PREREQ_DIR\$file" ) {
    Write-Host "Success" -ForegroundColor Green
} else {
    Write-Host "Failed" -ForegroundColor Red
    exit 1
}

#-------------------------------------------------------------------------------
# Remove binaries not needed by Salt
#-------------------------------------------------------------------------------
$binaries = @(
    "py.exe",
    "pyw.exe",
    "pythonw.exe",
    "venvlauncher.exe",
    "venvwlauncher.exe"
)
Write-Host "Removing Python binaries: " -NoNewline
$binaries | ForEach-Object {
    if ( Test-Path -Path "$SCRIPTS_DIR\$_" ) {
        # Use .net, the powershell function is asynchronous
        [System.IO.File]::Delete("$SCRIPTS_DIR\$_")
        if ( Test-Path -Path "$SCRIPTS_DIR\$_" ) {
            Write-Host "Failed" -ForegroundColor Red
            exit 1
        }
    }
}
Write-Host "Success" -ForegroundColor Green

#-------------------------------------------------------------------------------
# Remove Non-Windows Execution Modules
#-------------------------------------------------------------------------------
Write-Host "Removing Non-Windows Execution Modules: " -NoNewline
$modules = "acme",
           "aix",
           "alternatives",
           "apcups",
           "apf",
           "apt",
           "arista",
           "at",
           "bcache",
           "blockdev",
           "bluez",
           "bridge",
           "bsd",
           "btrfs",
           "ceph",
           "container_resource",
           "cron",
           "csf",
           "daemontools",
           "deb*",
           "devmap",
           "dpkg",
           "ebuild",
           "eix",
           "eselect",
           "ethtool",
           "extfs",
           "firewalld",
           "freebsd",
           "genesis",
           "gentoo",
           "glusterfs",
           "gnomedesktop",
           "groupadd",
           "grub_legacy",
           "guestfs",
           "htpasswd",
           "ilo",
           "img",
           "incron",
           "inspector",
           "ipset",
           "iptables",
           "iwtools",
           "k8s",
           "kapacitor",
           "keyboard",
           "keystone",
           "kmod",
           "layman",
           "linux",
           "localemod",
           "locate",
           "logadm",
           "logrotate",
           "lvs",
           "lxc",
           "mac",
           "makeconf",
           "mdadm",
           "mdata",
           "monit",
           "moosefs",
           "mount",
           "napalm",
           "netbsd",
           "netscaler",
           "neutron",
           "nfs3",
           "nftables",
           "nova",
           "nspawn",
           "openbsd",
           "openstack",
           "openvswitch",
           "opkg",
           "pacman",
           "parallels",
           "parted",
           "pcs",
           "pkgin",
           "pkgng",
           "pkgutil",
           "portage_config",
           "postfix",
           "poudriere",
           "powerpath",
           "pw_",
           "qemu_",
           "quota",
           "redismod",
           "restartcheck",
           "rh_",
           "riak",
           "rpm",
           "runit",
           "s6",
           "scsi",
           "seed",
           "sensors",
           "service",
           "shadow",
           "smartos",
           "smf",
           "snapper",
           "solaris",
           "solr",
           "ssh_",
           "supervisord",
           "sysbench",
           "sysfs",
           "sysrc",
           "system",
           "test_virtual",
           "timezone",
           "trafficserver",
           "tuned",
           "udev",
           "upstart",
           "useradd",
           "uswgi",
           "varnish",
           "vbox",
           "virt",
           "xapi",
           "xbpspkg",
           "xfs",
           "yum*",
           "zfs",
           "znc",
           "zpool",
           "zypper"
$modules | ForEach-Object {
    Remove-Item -Path "$BUILD_SALT_DIR\modules\$_*" -Recurse
    if ( Test-Path -Path "$BUILD_SALT_DIR\modules\$_*" ) {
        Write-Host "Failed" -ForegroundColor Red
        Write-Host "Failed to remove: $BUILD_SALT_DIR\modules\$_"
        exit 1
    }
}
Write-Host "Success" -ForegroundColor Green

#-------------------------------------------------------------------------------
# Remove Non-Windows State Modules
#-------------------------------------------------------------------------------
Write-Host "Removing Non-Windows State Modules: " -NoNewline
$states = "acme",
          "alternatives",
          "apt",
          "at",
          "blockdev",
          "ceph",
          "cron",
          "csf",
          "deb",
          "eselect",
          "ethtool",
          "firewalld",
          "glusterfs",
          "gnome",
          "htpasswd",
          "incron",
          "ipset",
          "iptables",
          "k8s",
          "kapacitor",
          "keyboard",
          "keystone",
          "kmod",
          "layman",
          "linux",
          "lxc",
          "mac",
          "makeconf",
          "mdadm",
          "monit",
          "mount",
          "nftables",
          "pcs",
          "pkgng",
          "portage",
          "powerpath",
          "quota",
          "redismod",
          "smartos",
          "snapper",
          "ssh",
          "supervisord",
          "sysrc",
          "trafficserver",
          "tuned",
          "vbox",
          "virt.py",
          "zfs",
          "zpool"
$states | ForEach-Object {
    Remove-Item -Path "$BUILD_SALT_DIR\states\$_*" -Recurse
    if ( Test-Path -Path "$BUILD_SALT_DIR\states\$_*" ) {
        Write-Host "Failed" -ForegroundColor Red
        Write-Host "Failed to remove: $BUILD_SALT_DIR\states\$_"
        exit 1
    }
}
Write-Host "Success" -ForegroundColor Green

Write-Host "Removing unneeded files (.pyc, .chm): " -NoNewline
$remove = "__pycache__",
          "*.pyc",
          "*.chm"
$remove | ForEach-Object {
    $found = Get-ChildItem -Path "$BUILD_DIR\$_" -Recurse
    $found | ForEach-Object {
        Remove-Item -Path "$_" -Recurse -Force
        if ( Test-Path -Path $_ ) {
            Write-Host "Failed" -ForegroundColor Red
            Write-Host "Failed to remove: $_"
            exit 1
        }
    }
}
Write-Host "Success" -ForegroundColor Green

#-------------------------------------------------------------------------------
# Build the Installer
#-------------------------------------------------------------------------------
Write-Host "Building the Installer: " -NoNewline
$installer_name = "Salt-Minion-$Version-Py$($PY_VERSION.Split(".")[0])-$ARCH-Setup.exe"
Start-Process -FilePath $NSIS_BIN `
              -ArgumentList "/DSaltVersion=$Version", `
                            "/DPythonArchitecture=$ARCH", `
                            "$INSTALLER_DIR\Salt-Minion-Setup.nsi" `
              -Wait -WindowStyle Hidden
if ( Test-Path -Path "$INSTALLER_DIR\$installer_name" ) {
    Write-Host "Success" -ForegroundColor Green
} else {
    Write-Host "Failed" -ForegroundColor Red
    Write-Host "Failed to find $installer_name in installer directory"
    exit 1
}

if ( ! (Test-Path -Path "$SCRIPT_DIR\build") ) {
    New-Item -Path "$SCRIPT_DIR\build" -ItemType Directory | Out-Null
}
if ( Test-Path -Path "$SCRIPT_DIR\build\$installer_name" ) {
    Write-Host "Backing up existing installer: " -NoNewline
    $new_name = "$installer_name.$( Get-Date -UFormat %s ).bak"
    Move-Item -Path "$SCRIPT_DIR\build\$installer_name" `
              -Destination "$SCRIPT_DIR\build\$new_name"
    if ( Test-Path -Path "$SCRIPT_DIR\build\$new_name" ) {
        Write-Host "Success" -ForegroundColor Green
    } else {
        Write-Host "Failed" -ForegroundColor Red
        exit 1
    }
}

Write-Host "Moving the Installer: " -NoNewline
Move-Item -Path "$INSTALLER_DIR\$installer_name" -Destination "$SCRIPT_DIR\build"
if ( Test-Path -Path "$SCRIPT_DIR\build\$installer_name" ) {
    Write-Host "Success" -ForegroundColor Green
} else {
    Write-Host "Failed" -ForegroundColor Red
    exit 1
}

#-------------------------------------------------------------------------------
# Finished
#-------------------------------------------------------------------------------
Write-Host $("-" * 80)
Write-Host "Build NullSoft Installer for Salt Completed" `
    -ForegroundColor Cyan
Write-Host $("=" * 80)
Write-Host "Installer can be found at the following location:"
Write-Host "$SCRIPT_DIR\build\$installer_name"