#!/bin/bash

###############################################################################
# Update system and install basic tools
###############################################################################

sudo apt update && sudo apt upgrade -y

sudo apt install -y \
    zsh \
    tmux \
    vim \
    zip \
    htop \
    ufw \
    fail2ban \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    iproute2 \
    git

###############################################################################
# Install and configure ZSH
###############################################################################

chsh -s "$(which zsh)"

PROMPT_CONFIG="PROMPT='%n@%m:%~ %# '"
if ! grep -Fxq "$PROMPT_CONFIG" ~/.zshrc; then
    echo "$PROMPT_CONFIG" >> ~/.zshrc
fi

ALIAS_LS="alias ls='ls --color=auto'"
if ! grep -Fq "$ALIAS_LS" ~/.zshrc; then
    echo "$ALIAS_LS" >> ~/.zshrc
fi

###############################################################################
# Install Docker and Docker Compose
###############################################################################

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo systemctl start docker
sudo systemctl enable docker

docker compose version

###############################################################################
# Install .NET SDK 8.0 and dotnet-script
###############################################################################

sudo apt install -y dotnet-sdk-8.0
dotnet tool install -g dotnet-script || dotnet tool update -g dotnet-script

DOTNET_TOOLS_PATH='export PATH="$PATH:$HOME/.dotnet/tools"'
if ! grep -Fq "$DOTNET_TOOLS_PATH" ~/.zshrc; then
    echo "$DOTNET_TOOLS_PATH" >> ~/.zshrc
fi

###############################################################################
# Configure Tmux
###############################################################################

read -r -d '' TMUX_CONFIG << 'EOF'
if command -v tmux &>/dev/null && [ -z "$TMUX" ]; then
  tmux new-session -A -s mysession
fi
EOF

if ! grep -Fq "tmux new-session -A -s mysession" ~/.zshrc; then
    echo -e "\n$TMUX_CONFIG" >> ~/.zshrc
fi

TMUX_CONF_PATH="$HOME/.tmux.conf"
TMUX_MOUSE_CONFIG="set -g mouse on"
TMUX_PREFIX_CONFIG="set -g prefix C-a"
TMUX_STATUS_INTERVAL="set -g status-interval 1"
TMUX_STATUS_LEFT="set -g status-left '#(/usr/local/bin/connections.csx)'"
TMUX_STATUS_RIGHT="set -g status-right '#(/usr/local/bin/statusbar.csx)'"
TMUX_NO_WINDOW_NAME="set -g window-status-format ''"
TMUX_NO_WINDOW_NAME_CUR="set -g window-status-current-format ''"

if [ ! -f "$TMUX_CONF_PATH" ]; then
  {
    echo "$TMUX_MOUSE_CONFIG"
    echo "$TMUX_PREFIX_CONFIG"
    echo "$TMUX_STATUS_INTERVAL"
    echo "$TMUX_STATUS_LEFT"
    echo "$TMUX_STATUS_RIGHT"
    echo "$TMUX_NO_WINDOW_NAME"
    echo "$TMUX_NO_WINDOW_NAME_CUR"
  } > "$TMUX_CONF_PATH"
else
  sed -i '/^set -g status-left/d' "$TMUX_CONF_PATH"
  sed -i '/^set -g status-right/d' "$TMUX_CONF_PATH"
  echo "$TMUX_STATUS_LEFT" >> "$TMUX_CONF_PATH"
  echo "$TMUX_STATUS_RIGHT" >> "$TMUX_CONF_PATH"
  grep -Fxq "$TMUX_MOUSE_CONFIG" "$TMUX_CONF_PATH" || echo "$TMUX_MOUSE_CONFIG" >> "$TMUX_CONF_PATH"
  grep -Fxq "$TMUX_PREFIX_CONFIG" "$TMUX_CONF_PATH" || echo "$TMUX_PREFIX_CONFIG" >> "$TMUX_CONF_PATH"
  grep -Fxq "$TMUX_STATUS_INTERVAL" "$TMUX_CONF_PATH" || echo "$TMUX_STATUS_INTERVAL" >> "$TMUX_CONF_PATH"
  grep -Fxq "$TMUX_NO_WINDOW_NAME" "$TMUX_CONF_PATH" || echo "$TMUX_NO_WINDOW_NAME" >> "$TMUX_CONF_PATH"
  grep -Fxq "$TMUX_NO_WINDOW_NAME_CUR" "$TMUX_CONF_PATH" || echo "$TMUX_NO_WINDOW_NAME_CUR" >> "$TMUX_CONF_PATH"
fi

if tmux info &>/dev/null; then
  tmux source-file "$TMUX_CONF_PATH"
fi

###############################################################################
# Configure Firewall (UFW)
###############################################################################

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw --force enable

###############################################################################
# Configure Fail2Ban
###############################################################################

sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

###############################################################################
# Create /usr/local/bin/statusbar.csx (CPU + MEM, right)
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
                     .Skip(1).Select(double.Parse).ToArray();
    double idle = parts[3], total = parts.Sum();
    Thread.Sleep(500);
    parts = File.ReadLines("/proc/stat").First(l => l.StartsWith("cpu "))
                     .Split(' ', StringSplitOptions.RemoveEmptyEntries)
                     .Skip(1).Select(double.Parse).ToArray();
    double newIdle = parts[3], newTotal = parts.Sum();
    return 100 * (1 - ((newIdle - idle) / (newTotal - total)));
}

double GetMemUsage(){
    var dict = File.ReadAllLines("/proc/meminfo")
                   .Select(line => line.Split(':'))
                   .ToDictionary(p => p[0].Trim(),
                                 p => double.Parse(p[1].Trim().Split(' ')[0]));
    double total = dict["MemTotal"];
    double available = dict["MemAvailable"];
    double used = total - available;
    return used * 100 / total;
}

while (true){
    Console.SetCursorPosition(0, 0);
    Console.WriteLine($"{GetCpuUsage():F1}% CPU | Mem {GetMemUsage():F1}% ");
    Thread.Sleep(1000);
}
EOF

sudo chmod +x /usr/local/bin/statusbar.csx

###############################################################################
# Create /usr/local/bin/connections.csx (HTTP connections, left)
###############################################################################

sudo tee /usr/local/bin/connections.csx > /dev/null << 'EOF'
#!/usr/bin/env dotnet-script
using System;
using System.Diagnostics;

int GetConnCount(int port){
    var proc = Process.Start(new ProcessStartInfo {
        FileName = "/bin/bash",
        Arguments = $"-c \"ss -H -t state established '( sport = :{port} or dport = :{port} )' | wc -l\"",
        RedirectStandardOutput = true,
        UseShellExecute = false
    })!;
    string result = proc.StandardOutput.ReadToEnd().Trim();
    proc.WaitForExit();
    return int.TryParse(result, out int count) ? count : 0;
}

while (true){
    int http = GetConnCount(80);
    int https = GetConnCount(443);
    int total = http + https;
    Console.SetCursorPosition(0, 0);
    Console.WriteLine($" 🌐 {total}");
    System.Threading.Thread.Sleep(1000);
}
EOF

sudo chmod +x /usr/local/bin/connections.csx

###############################################################################
# Create ~/.vimrc (use vim-vscode-style)
###############################################################################

cat > "$HOME/.vimrc" << 'EOF'
set clipboard=unnamedplus
syntax on
set number
set tabstop=4
set shiftwidth=4
set expandtab
set mouse=a

" Load vim-vscode-style theme
packadd vim-vscode-style
colorscheme vscode-style
EOF

###############################################################################
# Install vim-vscode-style theme (vim packages)
###############################################################################

mkdir -p "$HOME/.vim/pack/themes/start"
if [ ! -d "$HOME/.vim/pack/themes/start/vim-vscode-style/.git" ]; then
  git clone https://github.com/lexlanven/vim-vscode-style.git "$HOME/.vim/pack/themes/start/vim-vscode-style"
else
  git -C "$HOME/.vim/pack/themes/start/vim-vscode-style" pull --ff-only || true
fi

###############################################################################
# Final cleanup and reboot
###############################################################################

sudo rm -rf ./install.sh

echo "✅ Setup completed successfully! System will now reboot..."
sleep 3
sudo reboot
