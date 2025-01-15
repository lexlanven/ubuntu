#!/bin/bash

# Update the package list and install system updates
sudo apt update && sudo apt upgrade -y

# Install zsh
sudo apt install zsh -y

# Change the default shell to zsh
# Note: Changes will take effect after a new login
chsh -s "$(which zsh)"

# Configure the prompt for zsh if it's not already configured
PROMPT_CONFIG="PROMPT='%n@%m:%~ %# '"
if ! grep -Fxq "$PROMPT_CONFIG" ~/.zshrc; then
  echo "$PROMPT_CONFIG" >> ~/.zshrc
fi

# Add alias for the ls command with color support
ALIAS_LS="alias ls='ls --color=auto'"
if ! grep -Fq "$ALIAS_LS" ~/.zshrc; then
  echo "$ALIAS_LS" >> ~/.zshrc
fi

# Install Docker
sudo apt install -y docker.io
sudo systemctl start docker
sudo systemctl enable docker

# Install tmux
sudo apt install tmux -y

# Install neovim, zip, and htop
sudo apt install -y neovim zip htop

# Update the package list and install .NET SDK 8.0
sudo apt-get update && \
sudo apt-get install -y dotnet-sdk-8.0

# Install dotnet-script tool (optional)
dotnet tool install -g dotnet-script || dotnet tool update -g dotnet-script

# Add the .NET tools directory to PATH
echo 'export PATH="$PATH:$HOME/.dotnet/tools"' >> ~/.zshrc

# Configure automatic tmux startup in zsh if tmux is installed and not running
read -r -d '' TMUX_CONFIG << 'EOF'
if command -v tmux &>/dev/null && [ -z "$TMUX" ]; then
  tmux new-session -A -s mysession
fi
EOF

# Add tmux auto-start configuration to ~/.zshrc if not already added
if ! grep -Fq "tmux new-session -A -s mysession" ~/.zshrc; then
  echo -e "\n$TMUX_CONFIG" >> ~/.zshrc
fi

# Configure the tmux configuration file (~/.tmux.conf)
# Enable mouse support and change prefix to C-a
TMUX_CONF_PATH="$HOME/.tmux.conf"
TMUX_MOUSE_CONFIG="set -g mouse on"
TMUX_PREFIX_CONFIG="set -g prefix C-a"

if [ ! -f "$TMUX_CONF_PATH" ]; then
  # If the file does not exist, create it and add both settings
  echo "$TMUX_MOUSE_CONFIG" > "$TMUX_CONF_PATH"
  echo "$TMUX_PREFIX_CONFIG" >> "$TMUX_CONF_PATH"
else
  # If the file exists, check for each setting separately
  if ! grep -Fxq "$TMUX_MOUSE_CONFIG" "$TMUX_CONF_PATH"; then
    echo "$TMUX_MOUSE_CONFIG" >> "$TMUX_CONF_PATH"
  fi
  if ! grep -Fxq "$TMUX_PREFIX_CONFIG" "$TMUX_CONF_PATH"; then
    echo "$TMUX_PREFIX_CONFIG" >> "$TMUX_CONF_PATH"
  fi
fi

# Apply tmux configuration if the tmux server is already running
if tmux info &>/dev/null; then
  tmux source-file "$TMUX_CONF_PATH"
fi

# Configure the firewall (ufw)
sudo apt install ufw -y
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 443/tcp
sudo ufw allow 4444/tcp
sudo ufw allow OpenSSH
sudo ufw enable

# Output successful completion
echo "The script has completed successfully! The system will now reboot."

# Reboot the system
sudo reboot
