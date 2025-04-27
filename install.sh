#!/bin/bash

###############################################################################
# Update system and install basic tools
###############################################################################

sudo apt update && sudo apt upgrade -y

sudo apt install -y \
    zsh \
    tmux \
    neovim \
    zip \
    htop \
    ufw \
    fail2ban \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

###############################################################################
# Install and configure ZSH
###############################################################################

# Change the default shell to zsh
chsh -s "$(which zsh)"

# Configure prompt
PROMPT_CONFIG="PROMPT='%n@%m:%~ %# '"
if ! grep -Fxq "$PROMPT_CONFIG" ~/.zshrc; then
    echo "$PROMPT_CONFIG" >> ~/.zshrc
fi

# Add alias for ls
ALIAS_LS="alias ls='ls --color=auto'"
if ! grep -Fq "$ALIAS_LS" ~/.zshrc; then
    echo "$ALIAS_LS" >> ~/.zshrc
fi

###############################################################################
# Install Docker and Docker Compose
###############################################################################

# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine and Compose Plugin
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start and enable Docker
sudo systemctl start docker
sudo systemctl enable docker

# Check Docker Compose installation
docker compose version

###############################################################################
# Install .NET SDK 8.0 and dotnet-script
###############################################################################

# Add Microsoft package repository
sudo apt install -y dotnet-sdk-8.0

# Install dotnet-script tool
dotnet tool install -g dotnet-script || dotnet tool update -g dotnet-script

# Add .NET tools directory to PATH
DOTNET_TOOLS_PATH='export PATH="$PATH:$HOME/.dotnet/tools"'
if ! grep -Fq "$DOTNET_TOOLS_PATH" ~/.zshrc; then
    echo "$DOTNET_TOOLS_PATH" >> ~/.zshrc
fi

###############################################################################
# Configure Tmux
###############################################################################

# Auto-start tmux in zsh
read -r -d '' TMUX_CONFIG << 'EOF'
if command -v tmux &>/dev/null && [ -z "$TMUX" ]; then
  tmux new-session -A -s mysession
fi
EOF

if ! grep -Fq "tmux new-session -A -s mysession" ~/.zshrc; then
    echo -e "\n$TMUX_CONFIG" >> ~/.zshrc
fi

# Create tmux config file
TMUX_CONF_PATH="$HOME/.tmux.conf"
TMUX_MOUSE_CONFIG="set -g mouse on"
TMUX_PREFIX_CONFIG="set -g prefix C-a"
TMUX_STATUS_INTERVAL="set -g status-interval 1"
TMUX_STATUS_RIGHT="set -g status-right '#(/usr/local/bin/statusbar.csx)'"

if [ ! -f "$TMUX_CONF_PATH" ]; then
    {
        echo "$TMUX_MOUSE_CONFIG"
        echo "$TMUX_PREFIX_CONFIG"
        echo "$TMUX_STATUS_INTERVAL"
        echo "$TMUX_STATUS_RIGHT"
    } > "$TMUX_CONF_PATH"
else
    grep -Fxq "$TMUX_MOUSE_CONFIG" "$TMUX_CONF_PATH" || echo "$TMUX_MOUSE_CONFIG" >> "$TMUX_CONF_PATH"
    grep -Fxq "$TMUX_PREFIX_CONFIG" "$TMUX_CONF_PATH" || echo "$TMUX_PREFIX_CONFIG" >> "$TMUX_CONF_PATH"
    grep -Fxq "$TMUX_STATUS_INTERVAL" "$TMUX_CONF_PATH" || echo "$TMUX_STATUS_INTERVAL" >> "$TMUX_CONF_PATH"
    grep -Fxq "$TMUX_STATUS_RIGHT" "$TMUX_CONF_PATH" || echo "$TMUX_STATUS_RIGHT" >> "$TMUX_CONF_PATH"
fi

# Apply tmux configuration immediately if tmux is running
if tmux info &>/dev/null; then
    tmux source-file "$TMUX_CONF_PATH"
fi

###############################################################################
# Configure Firewall (UFW)
###############################################################################

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 443/tcp
sudo ufw allow 4444/tcp
sudo ufw allow OpenSSH
sudo ufw --force enable

###############################################################################
# Configure Fail2Ban
###############################################################################

sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

###############################################################################
# Create /usr/local/bin/statusbar.csx script
###############################################################################

sudo tee /usr/local/bin/statusbar.csx > /dev/null << 'EOF'
#!/usr/bin/env dotnet-script
using System;
using System.IO;
using System.Linq;
using System.Threading;

double GetCpuUsage(){
    var parts = File.ReadLines("/proc/stat").First(l => l.StartsWith("cpu "))
                     .Split(' ', StringSplitOptions.RemoveEmptyEntries)
                     .Skip(1)
                     .Select(double.Parse)
                     .ToArray();
    double idle = parts[3], total = parts.Sum();
    Thread.Sleep(500);
    parts = File.ReadLines("/proc/stat").First(l => l.StartsWith("cpu "))
                     .Split(' ', StringSplitOptions.RemoveEmptyEntries)
                     .Skip(1)
                     .Select(double.Parse)
                     .ToArray();
    double newIdle = parts[3], newTotal = parts.Sum();
    return 100 * (1 - ((newIdle - idle) / (newTotal - total)));
}

double GetMemUsage()
{
    var dict = File.ReadAllLines("/proc/meminfo")
                  .Select(line => line.Split(':'))
                  .ToDictionary(parts => parts[0].Trim(),
                                parts => double.Parse(parts[1].Trim().Split(' ')[0]));

    double total = dict["MemTotal"];
    double available = dict["MemAvailable"];
    double used = total - available;
    double percent = used * 100 / total;
    return percent;
}

while (true)
{
    Console.SetCursorPosition(0, 0);
    Console.WriteLine($"{GetCpuUsage():F1}% CPU | Mem {GetMemUsage():F1}% ");
    Thread.Sleep(1000);
}
EOF

# Make it executable
sudo chmod +x /usr/local/bin/statusbar.csx

###############################################################################
# Final cleanup and reboot
###############################################################################

# Remove temporary ubuntu directory if exists
sudo rm -rf ~/ubuntu

echo "✅ Setup completed successfully! System will now reboot..."
sleep 3
sudo reboot
