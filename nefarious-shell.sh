#!/usr/bin/env bash
#
# nefarious-installer.sh
# Interactive installer for a set of security / dev tools.
#
# Usage:
#   sudo ./nefarious-installer.sh
#
set -o errexit
set -o nounset
set -o pipefail

# -----------------------
# Visual / helpers
# -----------------------
PURPLE="\e[35m"
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
RESET="\e[0m"
BOLD="\e[1m"

log() { printf "%b\n" "${GREEN}[+][$(date +'%H:%M:%S')]${RESET} $*"; }
warn() { printf "%b\n" "${YELLOW}[!][$(date +'%H:%M:%S')]${RESET} $*"; }
err()  { printf "%b\n" "${RED}[-][$(date +'%H:%M:%S')]${RESET} $*"; }
die()  { err "$*"; exit 1; }

# Ensure script is run with sudo (we'll re-check when needed)
if [[ $EUID -ne 0 ]]; then
  warn "Not running as root. The script will use sudo for privileged operations."
fi

WORKDIR="$(mktemp -d /tmp/nefarious.XXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

# -----------------------
# ASCII logo
# -----------------------
print_logo() {
  cat <<'EOF'
                            ,                                                             
                            Et                                       :                    
 L.                     ,;  E#t                                     t#,    :             .
 EW:        ,ft       f#i   E##t                 j.         t      ;##W.   Ef           ;W
 E##;       t#E     .E#t    E#W#t             .. EW,        Ej    :#L:WE   E#t         f#E
 E###t      t#E    i#W,     E#tfL.           ;W, E##j       E#,  .KG  ,#D  E#t       .E#f 
 E#fE#f     t#E   L#D.      E#t             j##, E###D.     E#t  EE    ;#f E#t      iWW;  
 E#t D#G    t#E :K#Wfff; ,ffW#Dffj.        G###, E#jG#W;    E#t f#.     t#iE#t fi  L##Lffi
 E#t  f#E.  t#E i##WLLLLt ;LW#ELLLf.     :E####, E#t t##f   E#t :#G     GK E#t L#jtLLG##L 
 E#t   t#K: t#E  .E#L       E#t         ;W#DG##, E#t  :K#E: E#t  ;#L   LW. E#t L#L  ,W#i  
 E#t    ;#W,t#E    f#E:     E#t        j###DW##, E#KDDDD###iE#t   t#f f#:  E#tf#E: j#E.   
 E#t     :K#D#E     ,WW;    E#t       G##i,,G##, E#f,t#Wi,,,E#t    f#D#;   E###f .D#j     
 E#t      .E##E      .D#;   E#t     :K#K:   L##, E#t  ;#W:  E#t     G#t    E#K, ,WK,      
 ..         G#E        tt   E#t    ;##D.    L##, DWi   ,KK: E#t      t     EL   EG.       
             fE             ;#t    ,,,      .,,             ,;.            :    ,         
              ,              :;                                                           

EOF
}

# Print purple logo with small formatting (not relying on external figlet)
print_purple_logo() {
  printf "%b\n" "${PURPLE}"
  print_logo
  printf "%b\n" "${RESET}"
}

# -----------------------
# Utilities
# -----------------------
apt_update_if_needed() {
  # Run apt update only if list directory is empty or if last update > 1 hour
  if [ ! -d /var/lib/apt/lists ] || [ -z "$(ls -A /var/lib/apt/lists 2>/dev/null)" ]; then
    log "Running apt update..."
    sudo apt-get update -y
  else
    # Check timestamp of /var/lib/apt/periodic/update-success-stamp if available
    if [ -f /var/lib/apt/periodic/update-success-stamp ]; then
      last=$(stat -c %Y /var/lib/apt/periodic/update-success-stamp)
      now=$(date +%s)
      diff=$(( (now - last) / 60 ))
      if [ "$diff" -gt 60 ]; then
        log "apt lists older than 60 minutes; running apt-get update..."
        sudo apt-get update -y
      else
        log "apt lists fresh (updated ${diff} minutes ago)."
      fi
    else
      log "Running apt-get update..."
      sudo apt-get update -y
    fi
  fi
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

# -----------------------
# Individual installers
# -----------------------

install_ffuf() {
  if command_exists ffuf; then
    log "ffuf already installed; skipping."
    return
  fi
  apt_update_if_needed
  log "Installing ffuf..."
  sudo apt-get install -y ffuf || { warn "apt install ffuf failed; try manually"; }
}

install_dirsearch() {
  if command_exists dirsearch || [ -d /opt/dirsearch ]; then
    log "dirsearch already installed; skipping."
    return
  fi
  apt_update_if_needed
  log "Installing dirsearch (git clone to /opt/dirsearch)..."
  sudo apt-get install -y git python3 python3-pip || true
  sudo git clone https://github.com/maurosoria/dirsearch.git /opt/dirsearch
  sudo chown -R "$(logname):$(logname)" /opt/dirsearch || true
  pip3 install --user -r /opt/dirsearch/requirements.txt || true
}

install_gedit() {
  if command_exists gedit; then
    log "gedit already installed; skipping."
    return
  fi
  apt_update_if_needed
  log "Installing gedit..."
  sudo apt-get install -y gedit
}

install_vscode() {
  if command_exists code; then
    log "VS Code already installed (command: code); skipping."
    return
  fi
  cd "$WORKDIR"
  log "Downloading Visual Studio Code .deb..."
  wget -qO vscode.deb "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64" || die "Failed to download vscode"
  log "Installing vscode.deb..."
  sudo dpkg -i vscode.deb || sudo apt-get install -f -y
  rm -f vscode.deb
}

install_flask_unsign() {
  if python3 -c "import pkgutil,sys; sys.exit(0 if pkgutil.find_loader('flask_unsign') else 1)" 2>/dev/null; then
    log "flask-unsign already installed in python3 site-packages; skipping."
    return
  fi
  log "Installing flask-unsign via pip3..."
  python3 -m pip install --break-system-packages flask-unsign || die "pip install flask-unsign failed"
}

install_seclists() {
  if [ -d /opt/SecLists ]; then
    log "SecLists already present at /opt/SecLists; skipping."
    return
  fi
  apt_update_if_needed
  log "Cloning SecLists to /opt/SecLists..."
  sudo git clone https://github.com/danielmiessler/SecLists.git /opt/SecLists
  sudo chown -R "$(logname):$(logname)" /opt/SecLists || true
}

install_docker() {
  if command_exists docker; then
    log "Docker already installed; skipping."
    return
  fi
  apt_update_if_needed
  log "Installing Docker prerequisites..."
  sudo apt-get install -y ca-certificates curl gnupg lsb-release
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | sudo tee /etc/apt/keyrings/docker.gpg >/dev/null
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  arch=$(dpkg --print-architecture)
  distro="bookworm"
  # If /etc/os-release indicates ubuntu, adjust repo to ubuntu if desired; default to debian/bookworm
  if grep -qi ubuntu /etc/os-release 2>/dev/null; then
    distro="$(lsb_release -cs 2>/dev/null || echo focal)"
  fi
  echo \
    "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
    ${distro} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -y
  log "Installing Docker Engine..."
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || warn "docker apt install failed; try manual"
}

install_helm() {
  if command_exists helm; then
    log "helm already installed; skipping."
    return
  fi
  log "Installing Helm (script)..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash || warn "helm install script failed"
}

install_kubectl() {
  if command_exists kubectl; then
    log "kubectl already installed; skipping."
    return
  fi
  log "Installing kubectl (stable release)..."
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm -f kubectl
  log "kubectl installed to /usr/local/bin/kubectl"
}

install_minikube() {
  if command_exists minikube; then
    log "minikube already installed; skipping."
    return
  fi
  log "Installing minikube..."
  curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
  sudo install minikube-linux-amd64 /usr/local/bin/minikube
  rm -f minikube-linux-amd64
  log "minikube installed to /usr/local/bin/minikube"
}

install_terraform() {
  if command_exists terraform; then
    log "terraform already installed; skipping."
    return
  fi
  apt_update_if_needed
  log "Installing Terraform via apt (may pull from distro repos). If unavailable consider HashiCorp repo."
  sudo apt-get install -y terraform || warn "apt terraform failed; consider installing from HashiCorp official repo"
}

install_impacket() {
  if python3 -c "import impacket" >/dev/null 2>&1; then
    log "impacket python module present; skipping."
    return
  fi
  apt_update_if_needed
  log "Installing Impacket prerequisites..."
  sudo apt-get install -y python3-pip python3-dev build-essential git libssl-dev libffi-dev || true
  if [ -d /opt/impacket ]; then
    warn "/opt/impacket already exists — attempting upgrade in-place."
  else
    sudo git clone https://github.com/SecureAuthCorp/impacket.git /opt/impacket
    sudo chown -R "$(logname):$(logname)" /opt/impacket || true
  fi
  pushd /opt/impacket >/dev/null
  python3 -m pip install --upgrade pip --break-system-packages
  python3 -m pip install -r requirements.txt --break-system-packages || warn "Some requirements may have failed; continuing."
  sudo python3 setup.py install || warn "impacket setup.py install failed"
  popd >/dev/null
  log "Impacket installed (or attempted)."
}

install_neo4j_bloodhound() {
  apt_update_if_needed
  log "Installing Neo4j and BloodHound (if available in repos)..."
  sudo apt-get install -y neo4j bloodhound || warn "neo4j/bloodhound install may not be available in distro repos; consider manual installation"
}

unzip_rockyou() {
  if [ -f /usr/share/wordlists/rockyou.txt ]; then
    log "rockyou already exists at /usr/share/wordlists/rockyou.txt; skipping."
    return
  fi
  if [ -f rockyou.txt.gz ]; then
    log "gunzip rockyou.txt.gz..."
    sudo gunzip -k rockyou.txt.gz || warn "gunzip failed; ensure the file exists"
    # move if desired
    sudo mv -f rockyou.txt /usr/share/wordlists/rockyou.txt || true
  elif [ -f /usr/share/wordlists/rockyou.txt.gz ]; then
    log "Unpacking /usr/share/wordlists/rockyou.txt.gz..."
    sudo gunzip -k /usr/share/wordlists/rockyou.txt.gz || true
  else
    warn "rockyou.txt.gz not found in expected locations; skipping."
  fi
}

install_ngrok() {
  if command_exists ngrok; then
    log "ngrok already installed; skipping."
    return
  fi
  log "Installing ngrok (deb repository)..."
  curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
  echo "deb https://ngrok-agent.s3.amazonaws.com bookworm main" | sudo tee /etc/apt/sources.list.d/ngrok.list
  sudo apt-get update -y
  sudo apt-get install -y ngrok || warn "ngrok apt install failed"
  if command_exists ngrok; then
    read -rp "If you want to configure your ngrok authtoken now, enter it (or press Enter to skip): " NGROK_TOKEN
    if [ -n "${NGROK_TOKEN}" ]; then
      ngrok config add-authtoken "${NGROK_TOKEN}" || warn "ngrok config add-authtoken failed"
      log "ngrok authtoken configured."
    else
      warn "No ngrok token entered; you can configure later with: ngrok config add-authtoken <token>"
    fi
  fi
}

install_arjun() {
  if command_exists arjun; then
    log "arjun already installed; skipping."
    return
  fi
  log "Installing arjun via pip3..."
  python3 -m pip install --break-system-packages arjun || warn "pip install arjun failed"
}

install_ghidra() {
  if command_exists ghidra; then
    log "ghidra binary found; skipping."
    return
  fi
  log "Installing ghidra (attempt via apt)..."
  sudo apt-get update -y
  sudo apt-get install -y ghidra || warn "ghidra not found in repos; consider manual download from official site"
}

install_hyper() {
  if command_exists hyper; then
    log "hyper already installed; skipping."
    return
  fi
  log "Installing Hyper terminal..."
  mkdir -p "$WORKDIR/downloads"
  cd "$WORKDIR/downloads"
  wget -qO hyper.deb https://releases.hyper.is/download/deb || warn "Failed to fetch hyper.deb"
  sudo apt-get update -y
  sudo apt-get install -y ./hyper.deb || sudo apt-get install -f -y || warn "hyper install failed"
  rm -f hyper.deb
  # Attempt to install hyper package/theme if hyper CLI is present
  if command_exists hyper; then
    log "Attempting to install hyper-aura-theme (may require hyper plugins)"
    # run as normal user if possible
    if [ -n "${SUDO_USER:-}" ]; then
      su - "$SUDO_USER" -c "hyper i hyper-aura-theme || true"
    else
      hyper i hyper-aura-theme || true
    fi
  fi
  cd - >/dev/null || true
}

install_rustscan() {
  if command_exists rustscan; then
    log "RustScan already installed; skipping."
    return
  fi
  log "Installing RustScan (fetching latest release)..."
  cd "$WORKDIR"
  # Query GitHub API for latest release tag (numbers)
  LATEST_TAG=$(curl -s https://api.github.com/repos/bee-san/RustScan/releases/latest | grep -Po '"tag_name": "\K[^"]+' || true)
  if [ -z "$LATEST_TAG" ]; then
    warn "Could not fetch latest RustScan tag; trying known url"
    # fall back: try latest release URL
    URL="https://github.com/bee-san/RustScan/releases/latest/download/rustscan.deb.zip"
  else
    URL="https://github.com/bee-san/RustScan/releases/download/${LATEST_TAG}/rustscan.deb.zip"
  fi
  log "Downloading from: $URL"
  curl -L -o rustscan.deb.zip "$URL" || die "Failed to download rustscan archive"
  # unzip and install
  sudo apt-get install -y unzip || true
  unzip -o rustscan.deb.zip -d "$WORKDIR" || die "unzip failed"
  # find .deb inside
  DEB_FILE=$(find "$WORKDIR" -maxdepth 2 -type f -name "*.deb" | head -n 1 || true)
  if [ -z "$DEB_FILE" ]; then
    die "No .deb found inside rustscan archive"
  fi
  log "Installing $DEB_FILE..."
  sudo dpkg -i "$DEB_FILE" || sudo apt-get install -f -y
  log "RustScan installation attempted."
  cd - >/dev/null || true
}

# -----------------------
# Menu & dispatch
# -----------------------
print_menu() {
  cat <<EOF

Choose what to install (comma separated allowed), or 'all' to install everything:
  1) rustscan
  2) gedit
  3) ffuf
  4) dirsearch
  5) vscode
  6) flask-unsign
  7) SecLists
  8) Docker
  9) Helm
 10) kubectl
 11) minikube
 12) terraform
 13) impacket
 14) neo4j & bloodhound
 15) unpack rockyou (gunzip)
 16) ngrok (will prompt for token)
 17) arjun
 18) ghidra
 19) hyper
 20) Install everything (alias to 'all')
  0) Exit
EOF
}

install_by_choice() {
  choice="$1"
  case "$choice" in
    1) install_rustscan ;;
    2) install_gedit ;;
    3) install_ffuf ;;
    4) install_dirsearch ;;
    5) install_vscode ;;
    6) install_flask_unsign ;;
    7) install_seclists ;;
    8) install_docker ;;
    9) install_helm ;;
   10) install_kubectl ;;
   11) install_minikube ;;
   12) install_terraform ;;
   13) install_impacket ;;
   14) install_neo4j_bloodhound ;;
   15) unzip_rockyou ;;
   16) install_ngrok ;;
   17) install_arjun ;;
   18) install_ghidra ;;
   19) install_hyper ;;
   20) install_all ;;
    all)
        install_all
        ;;
    0)
        log "Exiting."
        exit 0
        ;;
    *)
        warn "Unknown choice: $choice"
        ;;
  esac
}

install_all() {
  log "Starting full installation (this may take a while)..."
  install_ffuf
  install_dirsearch
  install_gedit
  install_vscode
  install_flask_unsign
  install_seclists
  install_docker
  install_helm
  install_kubectl
  install_minikube
  install_terraform
  install_impacket
  install_neo4j_bloodhound
  unzip_rockyou
  install_ngrok
  install_arjun
  install_ghidra
  install_hyper
  install_rustscan
  log "Full installation completed."
}

# -----------------------
# Entrypoint
# -----------------------
main() {
  print_purple_logo
  log "Welcome to the Nefarious installer."
  print_menu

  read -rp "Your choice (e.g. 1 or 1,3 or all): " RAW
  if [ -z "${RAW}" ]; then
    die "No input received. Exiting."
  fi

  # Normalize: allow "all" or "20" or "install everything"
  if echo "$RAW" | grep -Eiq '^(all|everything|20)$'; then
    install_all
    return
  fi

  # Split comma/space separated numbers
  IFS=', ' read -r -a tokens <<<"$RAW"
  for t in "${tokens[@]}"; do
    t_trimmed="$(echo "$t" | xargs)"
    install_by_choice "$t_trimmed"
  done

  log "Done. If you installed tools that require additional configuration (ngrok token, adding user to docker group, etc.), follow the printed hints."
  cat <<EOF

Post-install hints:
 - To allow your user to run docker without sudo:
     sudo usermod -aG docker ${SUDO_USER:-$(whoami)} && newgrp docker
 - ngrok: configure token if you skipped during install:
     ngrok config add-authtoken <your-token>
 - Some tools may need PATH adjustments; try logging out/in if a command is not found.
EOF
}

main "$@"

