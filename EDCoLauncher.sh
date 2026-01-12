#!/bin/bash

# General vars
username="$(whoami)"
os_pretty_name=$(. /etc/os-release && echo "$PRETTY_NAME")
os_id=$(. /etc/os-release && echo "$ID")
os_like=$(. /etc/os-release && echo "$ID_LIKE")
config_file_path="$PWD/EDCoLauncher_config"
log_file_path="$PWD/EDCoLauncher.log"

# Text helpers
tab=$'\t'
colour_red=$(tput setaf 1)
colour_green=$(tput setaf 2)
colour_yellow=$(tput setaf 3)
colour_cyan=$(tput setaf 6)
colour_reset=$(tput sgr0)

strip_colour() {
    sed -Eu 's/\x1b(\[[0-9;]*[mGK]|\(B)//g'
}

# Send output to the log file with no colour chars and with timestamps
exec > >(stdbuf -oL tee -a >(strip_colour | grep --line-buffered . | while IFS= read -r line; do printf '%(%Y-%m-%d %H:%M:%S)T %s\n' -1 "$line"; done >> "${log_file_path}")) 2>&1

echo ""
echo "${colour_cyan}INFO:${colour_reset} Starting execution"
echo ""

# Steam vars
export PROTON_NO_ESYNC=1
export PROTON_NO_FSYNC=1
export ELECTRON_DISABLE_GPU_SANDBOX=1
unset LD_PRELOAD

# Elite Dangerous vars
ed_app_id="359320"
ed_wine_prefix="$(protontricks --no-bwrap -c "echo \$WINEPREFIX" "${ed_app_id}" 2>/dev/null)"

# EDCoPilot & EDCoPTER vars
ignore_pattern="Fossilize INFO|gameoverlayrenderer.so|WARN: Skipping fix execution."
edcopilot_log_file="$PWD/EDCoLauncher_EDCoPilot.log"
edcopter_log_file="$PWD/EDCoLauncher_EDCoPTER.log"
edcopilot_install_log_file="$PWD/EDCoLauncher_EDCoPilot_Install.log"
edcopter_install_log_file="$PWD/EDCoLauncher_EDCoPTER_Install.log"
edcopilot_default_install_exe_path="${ed_wine_prefix}/drive_c/EDCoPilot/LaunchEDCoPilot.exe"
edcopter_default_per_user_exe_path="${ed_wine_prefix}/drive_c/users/steamuser/AppData/Local/Programs/EDCoPTER/EDCoPTER.exe"
edcopter_default_all_users_exe_path="${ed_wine_prefix}/drive_c/Program Files/EDCoPTER/EDCoPTER.exe"
edcopter_default_install_exe_path=$([[ -f "${edcopter_default_per_user_exe_path}" ]] && echo "${edcopter_default_per_user_exe_path}" || echo "${edcopter_default_all_users_exe_path}") # Check the per-user install location first and fall back on the system-wide install location

# Load variable values from config file
if [[ -f "$PWD/EDCoLauncher_config" ]]; then
    install_edcopilot=$(. "${config_file_path}" && echo "$INSTALL_EDCOPILOT")
    install_edcopter=$(. "${config_file_path}" && echo "$INSTALL_EDCOPTER")
    edcopilot_enabled=$(. "${config_file_path}" && echo "$EDCOPILOT_ENABLED")
    edcopter_enabled=$(. "${config_file_path}" && echo "$EDCOPTER_ENABLED")
    edcopilot_path=$(. "${config_file_path}" && echo "$EDCOPILOT_EXE_PATH")
    edcopter_path=$(. "${config_file_path}" && echo "$EDCOPTER_EXE_PATH")
    hotas_fix_enabled=$(. "${config_file_path}" && echo "$HOTAS_FIX_ENABLED")

    # Handle empty path variables
    edcopilot_final_path=$([[ -z "$edcopilot_path" ]] && echo "${edcopilot_default_install_exe_path}" || echo "${edcopilot_path}")
    edcopter_final_path=$([[ -z "$edcopter_path" ]] && echo "${edcopter_default_install_exe_path}" || echo "${edcopter_path}")
else
    echo "${colour_yellow}WARNING:${colour_reset} Config file does not exist. Setting defaults"
    install_edcopilot="false"
    install_edcopter="false"
    edcopilot_enabled="true"
    edcopter_enabled="true"
    edcopilot_final_path="${edcopilot_default_install_exe_path}"
    edcopter_final_path="${edcopter_default_install_exe_path}"
    hotas_fix_enabled="false"
fi

echo "${colour_cyan}Current User:${colour_reset} ${username}"
echo "${colour_cyan}OS Pretty Name:${colour_reset} ${os_pretty_name}"
echo "${colour_cyan}OS ID:${colour_reset} ${os_id}"
echo "${colour_cyan}OS Like:${colour_reset} ${os_like}"
echo "${colour_cyan}Config File Path:${colour_reset} ${config_file_path}"
echo "${colour_cyan}Elite Dangerous Steam App ID:${colour_reset} ${ed_app_id}"
echo "${colour_cyan}Elite Dangerous Wine Prefix:${colour_reset} ${ed_wine_prefix}"
echo "${colour_cyan}EDCoPilot Enabled:${colour_reset} ${edcopilot_enabled}"
echo "${colour_cyan}EDCoPTER Enabled:${colour_reset} ${edcopter_enabled}"
echo "${colour_cyan}EDCoPilot Path:${colour_reset} ${edcopilot_final_path}"
echo "${colour_cyan}EDCoPTER Path:${colour_reset} ${edcopter_final_path}"
echo "${colour_cyan}HOTAS Fix Enabled:${colour_reset} ${hotas_fix_enabled}"
echo ""

#
# Download and install EDCoPilot if INSTALL_EDCOPILOT is set to true
#

if [[ ${install_edcopilot} == "true" ]]; then
    if [[ ! -f "${edcopilot_final_path}" ]]; then
        latest_edcopilot_msi_url=$(LD_LIBRARY_PATH="" curl -s "https://api.github.com/repos/Razzafrag/EDCoPilot-Installer/releases/latest" | grep -oP '"browser_download_url":\s*"\K[^"]+\.msi' | head -n 1)

        echo "${colour_cyan}INFO:${colour_reset} Downloading EDCoPilot installer. Please wait..."
        LD_LIBRARY_PATH="" curl -s -L -O --output-dir "${ed_wine_prefix}/drive_c" "${latest_edcopilot_msi_url}"

        echo "${colour_cyan}INFO:${colour_reset} Installing EDCoPilot. Please wait..."
        protontricks -c "wine msiexec /i \"${ed_wine_prefix}/drive_c/$(basename $latest_edcopilot_msi_url)\" /quiet /qn /norestart" ${ed_app_id}  > "${edcopilot_install_log_file}" 2>&1

        sleep 2

        if [[ ! -f "${edcopilot_final_path}" ]]; then
            echo "${colour_red}ERROR:${colour_reset} It looks like EDCoPilot wasn't installed properly. Please check the install log here: ${edcopilot_install_log_file}"
            exit
        else
            echo "${colour_cyan}INFO:${colour_reset} EDCoPilot was installed successully. Setting the INSTALL_EDCOPILOT config variable back to false"
            sed -i 's/^INSTALL_EDCOPILOT=.*/INSTALL_EDCOPILOT="false"/' "${config_file_path}" # Set the INSTALL_EDCOPILOT config variable to false to prevent re-runs
        fi

        echo "${colour_cyan}INFO:${colour_reset} Cleaning up EDCoPilot installer"
        rm -f "${ed_wine_prefix}/drive_c/$(basename $latest_edcopilot_msi_url)"
    else
        echo "${colour_cyan}WARN:${colour_reset} The INSTALL_EDCOPILOT config variable was set to true, but I detected an existing install here: $(dirname "${edcopilot_final_path}"). Setting the INSTALL_EDCOPILOT config variable back to false"
        sed -i 's/^INSTALL_EDCOPILOT=.*/INSTALL_EDCOPILOT="false"/' "${config_file_path}" # Set the INSTALL_EDCOPILOT config variable to false to prevent re-runs
    fi
fi

#
# Download and install EDCoPTER if INSTALL_EDCOPTER is set to true and if EDCoPilot is installed
#

if [[ ${install_edcopter} == "true" ]]; then
    if [[ -f "${edcopilot_final_path}" ]]; then
        if [[ ! -f "${edcopter_final_path}" ]]; then

            latest_edcopter_exe_url=$(LD_LIBRARY_PATH="" curl -s "https://api.github.com/repos/markhollingworth-worthit/EDCoPTER2.0-public-releases/releases/latest" | grep -oP '"browser_download_url":\s*"\K[^"]+\.exe' | head -n 1)

            echo "${colour_cyan}INFO:${colour_reset} Downloading EDCoPTER installer. Please wait..."
            LD_LIBRARY_PATH="" curl -s -L -O --output-dir "${ed_wine_prefix}/drive_c" "${latest_edcopter_exe_url}"

            echo "${colour_cyan}INFO:${colour_reset} Installing EDCoPTER. Please wait..."
            protontricks -c "wine \"${ed_wine_prefix}/drive_c/$(basename $latest_edcopter_exe_url)\" /S /allusers /D=\"C:\Program Files\EDCoPTER\"" ${ed_app_id}  > "${edcopter_install_log_file}" 2>&1

            sleep 2

            if [[ ! -f "${edcopter_final_path}" ]]; then
                echo "${colour_red}ERROR:${colour_reset} It looks like EDCoPTER wasn't installed properly. Please check the install log here: ${edcopter_install_log_file}"
            else
                echo "${colour_cyan}INFO:${colour_reset} EDCoPTER was installed successully. Setting the INSTALL_EDCOPTER config variable back to false"
                sed -i 's/^INSTALL_EDCOPTER=.*/INSTALL_EDCOPTER="false"/' "${config_file_path}" # Set the INSTALL_EDCOPTER config variable to false to prevent re-runs
            fi

            echo "${colour_cyan}INFO:${colour_reset} Cleaning up EDCoPTER installer"
            rm -f "${ed_wine_prefix}/drive_c/$(basename $latest_edcopter_exe_url)"
        else
            echo "${colour_yellow}WARN:${colour_reset} The INSTALL_EDCOPTER config variable was set to true, but I detected an existing install here: $(dirname "${edcopter_final_path}"). Setting the INSTALL_EDCOPTER config variable back to false"
            sed -i 's/^INSTALL_EDCOPTER=.*/INSTALL_EDCOPTER="false"/' "${config_file_path}" # Set the INSTALL_EDCOPTER config variable to false to prevent re-runs
        fi
    else
        echo "${colour_yellow}WARN:${colour_reset} Can't install EDCoPTER as a valid install of EDCoPilot wasn't detected"
    fi
fi

#
# Clean up old error files
#

[[ -f "${edcopilot_log_file}" ]] && echo "${colour_cyan}INFO:${colour_reset} Cleaning up temp EDCoPilot log file"; rm -f "${edcopilot_log_file}"
[[ -f "${edcopter_log_file}" ]] && echo "${colour_cyan}INFO:${colour_reset} Cleaning up temp EDCoPTER log file"; rm -f "${edcopter_log_file}"

#
# wait for the Elite Dangerous Launcher OR MinEdLauncher to start
#

echo "${colour_cyan}INFO:${colour_reset} Waiting for Elite Dangerous Launcher or MinEdLauncher to start..."
while ! { pgrep -f "Z:..*steamapps.common.Elite Dangerous.EDLaunch.exe.*" > /dev/null || { pgrep -f "MinEdLauncher" > /dev/null && pgrep -f "Z:..*EliteDangerous64.exe" > /dev/null; }; }; do
    sleep 2
done

echo "${colour_cyan}INFO:${colour_reset} Found a launcher. Determining the launcher type..."

# Get the correct launcher PID
if pgrep -f "MinEdLauncher" > /dev/null; then
    edlauncher_pid=$(pgrep -f "Z:..*EliteDangerous64.exe")
    echo "${colour_cyan}INFO:${colour_reset} Detected MinEdLauncher. Elite Dangerous window PID: ${edlauncher_pid}. Preparing to launch Add-ons..."
else
    edlauncher_pid=$(pgrep -f "Z:..*steamapps.common.Elite Dangerous.EDLaunch.exe.*")
    echo "${colour_cyan}INFO:${colour_reset} Detected the Elite Dangerous Launcher (PID: ${edlauncher_pid}). Preparing to launch Add-ons..."
fi

#
# Manage windows.gaming.input to fix HOTAS crash problem
#

if protontricks --no-bwrap -c 'wine reg query "HKEY_CURRENT_USER\Software\Wine\DllOverrides" /v "windows.gaming.input"' "${ed_app_id}" 2>/dev/null | grep -q "windows.gaming.input"; then
    echo "${colour_cyan}INFO:${colour_reset} The HOTAS fix to override windows.gaming.input is currently active."
    if [[ "${hotas_fix_enabled}" != "true" ]]; then
        if protontricks --no-bwrap -c 'wine reg delete "HKEY_CURRENT_USER\Software\Wine\DllOverrides" /v "windows.gaming.input" /f' "${ed_app_id}" 2>/dev/null | grep -q "The operation completed successfully"; then
            echo "${colour_cyan}INFO:${colour_reset} Removed the windows.gaming.input DLL override from the wine prefix. The HOTAS fix is now NOT active."
        else
            echo "${colour_yellow}WARNING:${colour_reset} Failed to remove the windows.gaming.input DLL override from the wine prefix. Consider doing this manually through the protontricks GUI"
        fi
    fi
else
    if [[ "${hotas_fix_enabled}" == "true" ]]; then
        echo "${colour_cyan}INFO:${colour_reset} The HOTAS fix to override windows.gaming.input was not found."
        if protontricks --no-bwrap -c 'wine reg add "HKEY_CURRENT_USER\Software\Wine\DllOverrides" /v "windows.gaming.input" /t REG_SZ /d "" /f' "${ed_app_id}" 2>/dev/null | grep -q "The operation completed successfully"; then
            echo "${colour_cyan}INFO:${colour_reset} Added the windows.gaming.input DLL override from the wine prefix. The HOTAS fix is now active."
        else
            echo "${colour_yellow}WARNING:${colour_reset} Failed to add the windows.gaming.input DLL override from the wine prefix. Consider doing this manually through the protontricks GUI"
        fi
    fi
fi

#
# Launch EDCoPilot
#

if [[ "$edcopilot_enabled" == "true" ]]; then

    # Set RunningOnLinux EDCoPilot flag to 1
    echo "${colour_cyan}INFO:${colour_reset} Setting the EDCoPilot RunningOnLinux flag to 1. This might need a relaunch to take effect"
    sed -i "s/RunningOnLinux=\"0\"/RunningOnLinux=\"1\"\\r/" "$(dirname ${edcopilot_final_path})/EDCoPilot.ini"
    sed -i "s/RunningOnLinux=\"0\"/RunningOnLinux=\"1\"\\r/" "$(dirname ${edcopilot_final_path})/edcopilotgui.ini"

    echo ""
    echo "${colour_cyan}INFO:${colour_reset} Launching EDCoPilot"
    LD_LIBRARY_PATH="" protontricks-launch --no-bwrap --appid ${ed_app_id} "${edcopilot_final_path}" > "${edcopilot_log_file}" 2>&1 &
    edcopilot_pid=$!

    sleep 4

    # Check if the process is still running
    if kill -0 $edcopilot_pid 2>/dev/null; then
        echo "${colour_cyan}INFO:${colour_reset} EDCoPilot launched successfully (PID: ${edcopilot_pid})"
    else
        echo "${colour_red}ERROR:${colour_reset} EDCoPilot failed to start or crashed immediately. Check ${edcopilot_log_file}"
        exit
    fi

fi

#
# Launch EDCoPTER
#

# Wait for EDCoPilot to start

echo "${colour_cyan}INFO:${colour_reset} Waiting for EDCoPilot to fully initialise..."

while ! pgrep -f "EDCoPilotGUI2.exe" > /dev/null; do
    sleep 1
done

# Give another 20 seconds grace period for EDCoPilot to fully launch

sleep 20

# Start EDCoPTER

if [[ "$edcopter_enabled" == "true" ]]; then
    echo ""
    echo "${colour_cyan}INFO:${colour_reset} Launching EDCoPTER"
    LD_LIBRARY_PATH="" protontricks-launch --appid ${ed_app_id} "${edcopter_final_path}" --no-sandbox --disable-gpu > "${edcopter_log_file}" 2>&1 &
    edcopter_pid=$!

    sleep 4

    # Check if the process is still running
    if kill -0 $edcopter_pid 2>/dev/null; then
        echo "${colour_cyan}INFO:${colour_reset} EDCoPTER launched successfully (PID: ${edcopter_pid})"
    else
        echo "${colour_red}ERROR:${colour_reset} EDCoPTER failed to start or crashed immediately. Check ${edcopter_log_file}"
    fi
fi

#
# Monitor the Elite Dangerous Launcher and exit EDCoPilot and EDCoPTER once it closed
#

echo ""
echo "${colour_cyan}INFO:${colour_reset} To close EDCoPilot and EDCoPTER, please close the Elite Dangerous Launcher"

while kill -0 "$edlauncher_pid" 2>/dev/null; do
    sleep 1
done

#
# Send murder signals to EDCoPTER
#

echo "${colour_cyan}INFO:${colour_reset} Closing EDCoPTER. Please wait"
kill -15 $(pgrep -f "EDCoPTER.exe") &>/dev/null

#
# Gracefully shutdown EDCoPilot
#

echo "${colour_cyan}INFO:${colour_reset} Closing EDCoPilot. Please wait"

# Check if EDCoPilot is still running
if pgrep -f "EDCoPilot.exe|LaunchEDCoPilot.exe|EDCoPilotGUI2.exe" > /dev/null; then

    # Send graceful shutdown command to EDCoPilot
    echo Shutdown >> "$(dirname "${edcopilot_final_path}")/EDCoPilot.request.txt"

    # Wait for EDCoPilot to shutdown
    while pgrep -f "EDCoPilot.exe|LaunchEDCoPilot.exe|EDCoPilotGUI2.exe" > /dev/null; do
        sleep 1
    done

    echo "${colour_cyan}INFO:${colour_reset} EDCoPilot has closed successfully."

    # Clean up the EDCoPilot.request.txt in case there is a race condition
    rm -f "$(dirname "${edcopilot_final_path}")/EDCoPilot.request.txt" &>/dev/null
fi

#
# Ensure all processes in the Wine prefix for Elite Dangerous are stopped properly
#

echo "${colour_cyan}INFO:${colour_reset} Closing EDCoPTER and cleaning up Wine prefix subprocesses"
protontricks --no-bwrap -c "wineserver -k" "${ed_app_id}"

sleep 2

echo "${colour_cyan}INFO:${colour_reset} All done! Exiting"
