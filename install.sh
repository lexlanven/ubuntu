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
    fail2ban \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    iproute2 \
    git \
    nftables \
    netplan.io

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
TMUX_BIND_KEYS="bind '-' split-window -v
bind '\' split-window -h"

if [ ! -f "$TMUX_CONF_PATH" ]; then
  {
    echo "$TMUX_MOUSE_CONFIG"
    echo "$TMUX_PREFIX_CONFIG"
    echo "$TMUX_STATUS_INTERVAL"
    echo "$TMUX_STATUS_LEFT"
    echo "$TMUX_STATUS_RIGHT"
    echo "$TMUX_NO_WINDOW_NAME"
    echo "$TMUX_NO_WINDOW_NAME_CUR"
    echo "$TMUX_BIND_KEYS"
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
  grep -Fxq "bind '\"' split-window -v" "$TMUX_CONF_PATH" || echo "$TMUX_BIND_KEYS" >> "$TMUX_CONF_PATH"
fi

if tmux info &>/dev/null; then
  tmux source-file "$TMUX_CONF_PATH"
fi

###############################################################################
# Configure Fail2Ban
###############################################################################

sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

###############################################################################
# Configure Firewall (nftables; disable UFW if active)
###############################################################################

if command -v ufw &>/dev/null; then
  if sudo ufw status | grep -q "Status: active"; then
    echo "⚠️  UFW активен — выключаю..."
    sudo ufw --force disable
  fi
fi

sudo systemctl enable nftables
sudo systemctl start nftables

sudo tee /etc/nftables.conf > /dev/null << 'EOF'
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0;

        iif lo accept
        ct state established,related accept
        tcp dport 22 accept

        drop
    }

    chain forward {
        type filter hook forward priority 0;
        drop
    }

    chain output {
        type filter hook output priority 0;
        accept
    }
}
EOF

sudo nft -f /etc/nftables.conf
sudo systemctl restart nftables

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

" YAML
autocmd FileType yaml setlocal tabstop=2 shiftwidth=2 expandtab

" Load vim-vscode-style theme
packadd vim-vscode-style
colorscheme vscode-style

" In Vim use termcap sequences to change cursor shape
if !has('nvim')
  let &t_SI = "\<Esc>[6 q"   " INSERT — vertical bar
  let &t_EI = "\<Esc>[2 q"   " NORMAL — block
endif
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
# Configure Netplan (detect WAN iface via route to 8.8.8.8)
###############################################################################

DEFAULT_IF="$(ip route get 8.8.8.8 2>/dev/null | awk '/ dev / {for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"
if [ -z "$DEFAULT_IF" ]; then
  DEFAULT_IF="$(ip route show default 2>/dev/null | awk '/^default/ {print $5; exit}')"
fi

if [ -z "$DEFAULT_IF" ] || [ ! -d "/sys/class/net/$DEFAULT_IF" ]; then
  echo "❌ Не удалось определить интерфейс с интернетом. Пропускаю настройку Netplan."
else
  MAC_ADDR="$(cat "/sys/class/net/$DEFAULT_IF/address" | tr 'A-Z' 'a-z')"

  echo "🌐 Обнаружен интерфейс с интернетом: $DEFAULT_IF (MAC: $MAC_ADDR)"

  TS="$(date +%Y%m%d%H%M%S)"
  sudo mkdir -p "/etc/netplan/backup-$TS"
  if ls /etc/netplan/*.yaml >/dev/null 2>&1; then
    sudo mv /etc/netplan/*.yaml "/etc/netplan/backup-$TS"/
  fi

  sudo tee /etc/netplan/01-main.yaml > /dev/null <<EOF
network:
  version: 2
  ethernets:
    ${DEFAULT_IF}:
      dhcp4: true
      dhcp6: false
      accept-ra: false
      link-local: [ ipv4 ]
      dhcp4-overrides:
        use-dns: false
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
EOF

  sudo netplan generate
  sudo netplan apply || true
fi

###############################################################################
# Final cleanup and reboot
###############################################################################

sudo rm -rf ./install.sh

echo "✅ Setup completed successfully! System will now reboot..."
sleep 3
sudo reboot
