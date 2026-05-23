#!/usr/bin/env bash

readonly NC=$(tput sgr0)
readonly RED=$(tput setaf 1)
readonly GREEN=$(tput setaf 2)
readonly YELLOW=$(tput setaf 3)
readonly BLUE=$(tput setaf 4)

readonly TMP_D="$(mktemp -d)"
trap "rm -rf '${TMP}'" EXIT

log_info()  { echo -e "[$(date '+%H:%M:%S')] ${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "[$(date '+%H:%M:%S')] ${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "[$(date '+%H:%M:%S')] ${RED}[ERROR]${NC} $*"; }

main() {
  sudo -v 

  mkdir -p "${TMP_D}"

  set_display_resolution 1920 1080
  set_keymap "hr"

  install_nvim
  install_kitty
}

set_display_resolution() {
  local xorg_conf_d="/etc/X11/xorg.conf.d"

  local x=$1
  local y=$2
  local resolution="${x}x${y}"

  log_info "Setting display resolution ${resolution}"

  local screen=$(xrandr | sed -n 2p | awk '{printf $1}')
  log_info "Detected screen: ${screen}"

  if ! xrandr --output "$screen" --mode "${resolution}"; then
    log_warn "Failed to set resolution ${resolution} in active session"
    return
  fi

  sudo tee "${xorg_conf_d}/10-resolution.conf" > /dev/null << EOF
  Section "Device"
    Identifier  "Card0"
    Driver      "modesetting"
  EndSection
  Section "Monitor"
      Identifier  "${screen}"
      Option      "PreferredMode" "${resolution}"
  EndSection
  Section "Screen"
      Identifier  "Screen0"
      Device      "Card0"
      Monitor     "${screen}"
      SubSection  "Display"
          Depth   24
          Modes   "${resolution}"
      EndSubSection
  EndSection
  Section "ServerLayout"
      Identifier  "Layout0"
      Screen      "Screen0"
  EndSection
EOF

  log_info "Resolution ${resolution} persisted in ${xorg_conf_d}/10-resolution.conf"
}

set_keymap() {
  local kbd_conf="/etc/default/keyboard"

  local keymap=$1

  if ! keymap_exists "${keymap}"; then
    log_warn "Keymap ${keymap} not found. Skipping step..."
    return
  fi

  setxkbmap "${keymap}"
  log_info "Set keymap ${keymap}"
  
  sudo sed -i "s/^XKBLAYOUT=.*/XKBLAYOUT=\"${keymap}\"/" "${kbd_conf}"
  log_info "Keymap ${keymap} persisted in ${kbd_conf}"
}

keymap_exists() {
  local keymap=$1

  awk -v k="${keymap}" '$1 == k {found=1} END {exit !found}' /usr/share/X11/xkb/rules/xorg.lst
}

install_nvim() {
  local artifact="nvim-linux-x86_64"
  local tarball="${artifact}.tar.gz"
  local url="https://github.com/neovim/neovim/releases/latest/download/${tarball}"

  log_info "Downloading neovim..."
  if ! curl -fLo "${TMP_D}/${tarball}" "${url}"; then
    log_warn "Download failed"
    return
  fi

  log_info "Extracting to /opt/${artifact}..."
  sudo rm -rf "/opt/${artifact}"
  if ! sudo tar -C /opt -xzf "${TMP_D}/${tarball}"; then
    log_warn "Extraction failed"
    return
  fi

  log_info "Creating symlink /usr/bin/nvim..."
  sudo ln -sf "/opt/${artifact}/bin/nvim" /usr/bin/nvim

  log_info "Neovim installed successfully"
}

install_kitty() {
  local installer="kitty-installer.sh"
  local url="https://sw.kovidgoyal.net/kitty/installer.sh"

  log_info "Downloading kitty installer..."
  if ! curl -fLo "${TMP_D}/${installer}" "${url}"; then
    log_warn "Download failed"
    return
  fi

  log_info "Running kitty installer..."
  if ! sh "${TMP_D}/${installer}"; then
    log_warn "Installation failed"
    return
  fi

  log_info "Creating symlink /usr/bin/kitty..."
  sudo ln -sf "${HOME}/.local/kitty.app/bin/kitty" /usr/bin/kitty

  log_info "Creating symlink /usr/bin/kitten..."
  sudo ln -sf "${HOME}/.local/kitty.app/bin/kitten" /usr/bin/kitten

  log_info "Kitty installed successfully"
}

main "$@"
