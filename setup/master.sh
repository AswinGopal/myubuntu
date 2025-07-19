#!/bin/bash

# Color codes
RC='\e[0m'
RED='\e[1;38;2;255;51;51m'
GREEN='\e[1;32m'
YELLOW='\e[1;33m'

# Global directories
githubDirectory="$(git rev-parse --show-toplevel 2>/dev/null)"
tempDirectory="/tmp/SETUP"

# Handle error messages and print them
log_error() {
    local log_file="error_log.txt"
    local timestamp=$(date +"%Y-%m-%d %T")
    local log_message=$1
    
    # Create log file if it doesn't exist
    touch "$log_file"
    
    # Append error message with timestamp to the log file
    echo -e "[$timestamp] ERROR: $log_message" >> "$log_file"
    
    # Print error message to the terminal
    echo -e "${RED}Error: $log_message${RC}"
}

# Print message to the terminal
show_info() {
    local timestamp=$(date +"%Y-%m-%d %T")
    echo -e "\n${YELLOW}[$timestamp] INFO: $1${RC}"
}

# Print success message to the terminal
success_message() {
    echo -e "${GREEN}$1 \xE2\x9C\x94${RC}"
}

# Update repos and enable universe if in live environment
update_repository() {
    show_info "Updating package repositories..."
    if ! sudo apt update > /dev/null 2>&1; then
        log_error "Repository update failed."
        exit 1
    fi
    success_message "Repository update successful."
    return 0
}

update_snap_packages() {
    show_info "Updating Snap packages..."
    if sudo snap refresh > /dev/null 2>&1; then
        success_message "Snap packages updated successfully"
        return 0
    else
        log_error "Failed to update Snap packages"
        return 1
    fi
}

install_programs() {
    show_info "Installing programs via APT..."

    if [ -f program_list.txt ]; then
        while IFS= read -r program; do
            echo -e "\n\e[1;30;47mInstalling $program...${RC}"
            if sudo apt install -y "$program" > /dev/null 2>&1; then
                success_message "$program installed"
            else
                log_error "Failed to install $program \xE2\x9C\x98"
                return 1
            fi
        done < program_list.txt
        success_message "Programs installation completed"
        return 0
    else
        log_error "Program list file not found. No programs installed 🚫"
        return 1
    fi
}

setup_firefox_profiles() {
    # Update Firefox snap
    show_info "Updating Firefox..."
    sudo snap refresh firefox > /dev/null 2>&1

    # Collect profile names from user input
    show_info "Setting up Firefox profiles..."
    profile_names=()

    while true; do
        read -p "Enter the profile name (or 'done' to finish): " profile_name
        if [ "$profile_name" = "done" ]; then
            break
        fi
        profile_names+=("$profile_name")
    done

    # Verify profile names availability; exit if none provided
    if [ ${#profile_names[@]} -eq 0 ]; then
        log_error "No profile names provided. Aborting Firefox profile creation."
        return 1
    fi

    # Loop through each provided profile name
    for profile in "${profile_names[@]}"; do
        show_info "Creating Firefox profile: $profile"

        # Create Firefox profile and configure settings
        if firefox -CreateProfile "$profile" > /dev/null 2>&1; then
            firefoxProfileDir="$HOME/snap/firefox/common/.mozilla/firefox"
            profileDirectory=$(find "$firefoxProfileDir" -maxdepth 1 -type d -name "*.$profile" -exec basename {} \;)
            userjs_path="$firefoxProfileDir/$profileDirectory/user.js"

            # Ask if user wants to add user.js to the profile
            read -p "Do you want to add user.js for the profile '$profile'? (yes/no): " add_userjs

            if [ "$add_userjs" = "yes" ]; then
                # Download user.js from the online repository if it does not exist in /tmp/SETUP
                if [ ! -f "/tmp/SETUP/user.js" ]; then
                    userjs_url="https://raw.githubusercontent.com/yokoffing/Betterfox/main/user.js"
                    wget -q --show-progress=off -O "/tmp/SETUP/user.js" "$userjs_url" || {
                        log_error "Failed to download user.js file for profile: $profile"
                        return 1
                    }
                fi

                # Copy user.js to the Firefox profile directory
                show_info "Copying user.js file to Firefox profile directory for profile: $profile"
                cp "/tmp/SETUP/user.js" "$userjs_path" || {
                    log_error "Failed to copy user.js file for profile: $profile"
                    return 1
                }
            fi

            # Create desktop shortcut for the profile
            cp "/var/lib/snapd/desktop/applications/firefox_firefox.desktop" "$HOME/.local/share/applications/firefox_$profile.desktop"
            desktop_file="$HOME/.local/share/applications/firefox_$profile.desktop"

            # Modify the desktop file with profile-specific settings
            if [ -f "$desktop_file" ]; then
                sed -i "s|/snap/bin/firefox -new-window|& -p $profile|g" "$desktop_file"
                sed -i "s|/snap/bin/firefox -private-window|& -p $profile|g" "$desktop_file"
                sed -i "s|\(/snap/bin/firefox\) %u$|\1 -p $profile %u|g" "$desktop_file"
                sed -i "s|Name=Firefox Web Browser|Name=$(echo "$profile" | sed 's/.*/\L\u&/') Browser|g" "$desktop_file"
            fi
        else
            log_error "Failed to create Firefox profile: $profile"
            return 1
        fi
    done

    success_message "Firefox profiles set up successfully"
    return 0
}

# Change commonly used Ubuntu Settings
change_ubuntu_settings() {
    show_info "Changing Ubuntu settings..."

    declare -A settings=(
        ["Modify terminal key shortcut"]="gsettings set org.gnome.settings-daemon.plugins.media-keys terminal \"['<Super>Return']\""
        ["Modify window close shortcut"]="gsettings set org.gnome.desktop.wm.keybindings close \"['<Super>w']\""
        ["Change screen-blank time to never"]="gsettings set org.gnome.desktop.session idle-delay 0"
        ["Set system timezone"]="sudo timedatectl set-timezone Asia/Kolkata"
        ["Change clock format (GNOME)"]="gsettings set org.gnome.desktop.interface clock-format '12h'"
        ["Change clock format (GTK)"]="gsettings set org.gtk.Settings.FileChooser clock-format '12h'"
        ["Set hardware clock to local time"]="sudo timedatectl set-local-rtc 1"
    )

    error_occurred=false

    for setting in "${!settings[@]}"; do
        show_info "Running: $setting"
        error=$(eval "${settings[$setting]}" 2>&1 > /dev/null)
        if [ $? -ne 0 ]; then
            log_error "Failed to $setting - Error: $error"
            error_occurred=true
        fi
    done
    
    if [ "$error_occurred" = false ]; then
        success_message "Ubuntu settings changed successfully"
        return 0
    fi    
}

# Function to install terminal theme
configureTerminalTheme() {
    font_download_directory="$tempDirectory"
    font_install_path="/usr/local/share/fonts/"
    
    # Add more fonts with their respective filenames and extraction directories here
    declare -A font_info=(
        ["Hack.zip"]="Hack"
        ["Meslo.zip"]="Meslo"
        ["FiraCode.zip"]="FiraCode"
    )

    show_info "Installing terminal theme..."

    for font_file in "${!font_info[@]}"; do
        font_name="${font_info[$font_file]}"
        font_download_path="${font_download_directory}/${font_file}"
        font_extract_path="${font_download_directory}/${font_name}"

        # Downloading latest release of the fonts from nerdfonts.com
        latest_release_url=$(curl -s "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest" | jq -r ".assets[] | select(.name == \"$font_file\") | .browser_download_url")

        if [ -n "$latest_release_url" ]; then
            show_info "Downloading latest $font_name font release..."
            wget -q --show-progress=off -P "$font_download_directory" "$latest_release_url" || { log_error "Failed to download $font_name font"; return 1; }
            
            unzip -q "$font_download_path" -d "$font_extract_path" || { log_error "Failed to unzip $font_name font directory"; return 1; }
            
            sudo cp -r "$font_extract_path" "$font_install_path" || { log_error "Failed to copy $font_name font files"; return 1; }

            success_message "$font_name downloaded successfully."
        else
            log_error "Failed to fetch latest $font_name font release URL."
            return 1
        fi
    done

    # Update font cache and fetch/execute theme after all fonts are installed
    sudo fc-cache -f || { log_error "Failed to update font cache"; return 1; }
    
    show_info "Fetching and executing the theme from git..."
    bash -c "$(curl -sLo- https://git.io/JvvDs)" || { log_error "Failed to fetch the theme from git"; return 1; }
    
    success_message "Terminal theme installed successfully."
    return 0
}

# Function to configure mpv
configureMpv() {
    show_info "Configuring mpv..."

    local mpv_config_dir="$HOME/.config/mpv"
    local yt_dlp_path="$HOME/.local/bin/yt-dlp"

    if [ ! -d "$mpv_config_dir" ]; then
        mkdir -p "$mpv_config_dir" || { log_error "Failed to create directory $mpv_config_dir"; return 1; }
    fi

    # Copy all config files first
    cp -r "$githubDirectory/mpv/"* "$mpv_config_dir/" || { log_error "Failed to copy files to $mpv_config_dir"; return 1; }

    # Replace placeholder in the mpv.conf file with actual yt-dlp path
    sed -i "s|__YT_DLP_PATH__|$yt_dlp_path|g" "$mpv_config_dir/mpv.conf"

    success_message "MPV configured successfully."
    return 0
}

# Function to setup bash
configureBash() {
    show_info "Configuring bash... "

    # Backup existing .bashrc
    if [ -f "$HOME/.bashrc" ]; then
        cp "$HOME/.bashrc" "$HOME/.bashrc.backup" || { log_error "Failed to backup existing .bashrc"; return 1; }
        success_message "Existing .bashrc backed up as .bashrc.backup"
    fi
    
    # Copy and hide dot files from source to destination 
    copied_files=()
    for file in "$githubDirectory/bash/"*; do
        filename=$(basename "$file")
        dest="$HOME/$filename"
        hidden_dest="$HOME/.$filename"

        if cp "$file" "$dest"; then
            if mv "$dest" "$hidden_dest"; then
                copied_files+=("$hidden_dest")
            else
                log_error "Failed to hide $filename"
                return 1
            fi
        else
            log_error "Failed to copy $filename"
            return 1
        fi
    done

    success_message "Bash setup successful. Copied and hid files: ${copied_files[*]}"
    return 0
}

# Function to download and configure yt-dlp
configureYtdlp() {
    show_info "Installing yt-dlp..."

    if [ ! -d "$HOME/.local/bin" ]; then
        mkdir -p "$HOME/.local/bin" || { log_error "Failed to create directory $HOME/.local/bin"; return 1; }
    fi

    if ! curl -sL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o "$HOME/.local/bin/yt-dlp"; then
        log_error "Failed to download yt-dlp binary"
        return 1
    else
        success_message "yt-dlp installed successfully."
        return 0
    fi
}

# Function to copy binaries to .local/bin
configureBinary() {
    show_info "Configuring binaries..."

    # Copying my binaries except channels.toml
    for file in "$githubDirectory/bin/"*; do
        [[ "$file" == *.toml ]] && continue
        cp "$file" "$HOME/.local/bin/" || { log_error "Failed to copy $file"; return 1; }
    done > /dev/null 2>&1

    # Ensure all files in ~/.local/bin are executable
    for file in "$HOME/.local/bin/"*; do
        [ -f "$file" ] && [ ! -x "$file" ] && chmod +x "$file"
    done

    success_message "Binaries copied to .local/bin."
    return 0
}

# Function to configure twitchtv
configureTwitch() {
    show_info "Configuring Twitch..."

    local twitchDir="$HOME/.config/twitchtv"

    #Copy channels.toml to twitchDir
    if [ ! -d "$twitchDir" ]; then
        mkdir -p "$twitchDir" || { log_error "Failed to create $twitchDir"; return 1; }
    fi

    cp "$githubDirectory/bin/"*.toml "$twitchDir" || { log_error "Failed to copy files to $twitchDir"; return 1; }

    success_message "Twitch config file setup succesfully."
    return 0
}

# Function to configure virtualenv for yt-dlp and streamlink
configureVirtualenv() {
    show_info "Installing Python virtual environment..."

    if virtualenv $HOME/myenv > /dev/null 2>&1; then
        show_info "Installing Streamlink..."
        cd $HOME/myenv/bin/
        if source activate; then
            if pip install -U streamlink > /dev/null 2>&1; then
                deactivate
                success_message "Streamlink installed successfully."
                return 0
            else
                log_error "Failed to install streamlink"
                deactivate
                return 1
            fi
        else
            log_error "Failed to activate virtualenv"
            return 1
        fi
    else
        log_error "Failed to create virtual environment"
        return 1
    fi
}

# Function to finalize the installation
finalConfigurations() {
    configureBash
    configureTerminalTheme
    configureMpv
    configureYtdlp
    configureBinary
    configureTwitch
    configureVirtualenv

    success_message "\nEverything setup successfully. Enjoy Linux"
}

# Funtion to cleanup the configuration files
cleanUp() {
    show_info "Removing temporary directory..."

    if [ -d "$tempDirectory" ]; then
        rm -rf "$tempDirectory"
        success_message "Temporary directory removed succesfully"
        return 0
    else
        log_error "No temporary directory present to remove"
        return 1
    fi
}

# Function to create SETUP directory in /tmp if it doesn't exist
create_SETUP_directory() {
    if [ ! -d "$tempDirectory" ]; then
        mkdir -p "$tempDirectory"
    fi
}

# Main function

# Array of valid case names
valid_args=("full" "test")
# Join the elements of the array with a pipe separator
valid_args_str=$(IFS=\|; echo "${valid_args[*]}")

check_argument() {
    create_SETUP_directory

    local arg="$1"

    case $arg in
        full)
            show_info "Running install function..."

            update_repository
            update_snap_packages
            install_programs
            #setup_firefox_profiles
            change_ubuntu_settings
            finalConfigurations
            cleanUp
            ;;
        test)
            show_info "Running test functions..."
            ;;
        *)
            log_error "The argument you provided is invalid"
            log_error "Usage: script_name.sh [${valid_args_str}]"
            return 1
            ;;
    esac
}

# Check for arguments and invoke the necessary actions
if [ $# -eq 0 ]; then
    log_error "Please provide an argument."
    log_error "Usage: script_name.sh [${valid_args_str}]"
    exit 1
fi

check_argument "$1"
