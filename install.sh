#!/usr/bin/env bash

readonly NC=$(tput sgr0)
readonly RED=$(tput setaf 1)
readonly GREEN=$(tput setaf 2)
readonly YELLOW=$(tput setaf 3)
readonly BLUE=$(tput setaf 4)

readonly TMP_D="$(mktemp -d)"
trap "rm -rf '${TMP_D}'" EXIT

log_info()  { echo -e "[$(date '+%H:%M:%S')] ${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "[$(date '+%H:%M:%S')] ${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "[$(date '+%H:%M:%S')] ${RED}[ERROR]${NC} $*"; }

main() {
  if ! sudo -v; then
    log_error "Must run as root"
    return
  fi
  
  log_info "Updating packages"
  sudo apt update

  set_display_resolution 1920 1080
  set_keymap "hr"
  set_theme "Kali-Green-Dark"
  set_icons "Flat-Remix-Green-Dark"
  set_bg
  set_font

  install_nvim
  install_kitty
  install_polybar
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

set_theme() {
  local theme=$1

  log_info "Setting theme ${theme}..."
  xfconf-query -c xsettings -p /Net/ThemeName -s "${theme}"

  log_info "Set theme ${theme}"
}

set_icons() {
  local icons=$1

  log_info "Setting icons ${icons}..."
  xfconf-query -c xsettings -p /Net/IconThemeName -s "${icons}"

  log_info "Set icons ${icons}"

}

set_bg() {
  local artifact="green-kali-2025-2-3840x2160.png"
  local url="https://www.kali.org/wallpapers/community/images/community/${artifact}"
  local bg_d="${HOME}/.local/share/backgrounds"

  mkdir -p "${bg_d}"

  log_info "Downloading ${artifact} image..."
  if ! curl -fLo "${TMP_D}/${artifact}" "${url}"; then
    log_warn "Download failed"
    return
  fi

  log_info "Copying to ${bg_d}..."
  cp "${TMP_D}/${artifact}" "${bg_d}/${artifact}"
  
  log_info "Setting as background image..."

  # apply to all workspaces
  xfconf-query \
    -c xfce4-desktop \
    -p /backdrop/single-workspace-mode \
    -s true

  # set background
  xfconf-query \
    -c xfce4-desktop \
    -p /backdrop/screen0/monitorVirtual-1/workspace0/last-image \
    -s "${bg_d}/${artifact}"

  # style stretched (3)
  xfconf-query \
    -c xfce4-desktop \
    -p /backdrop/screen0/monitorVirtual-1/workspace0/image-style\
    -s 3

  log_info "Set background ${artifact}"
}

set_font() {
  local font="Gohu"
  local artifact="${font}.zip"
  local version="v3.4.0"
  local url="https://github.com/ryanoasis/nerd-fonts/releases/download/${version}/${artifact}"
  local fonts_d="${HOME}/.local/share/fonts"

  mkdir -p "${fonts_d}"

  log_info "Downloading ${font} font..."
  if ! curl -fLo "${TMP_D}/${artifact}" "${url}"; then
    log_warn "Download failed"
    return
  fi
 
  log_info "Extracting to ${fonts_d}..."
  if ! unzip -o -d "${fonts_d}" "${TMP_D}/${artifact}"; then
    log_warn "Extraction failed"
    return
  fi

  log_info "Refreshing font cache..."
  fc-cache -f
  
  log_info "Setting ${font} as default font..."
  xfconf-query -c xsettings -p /Gtk/FontName -s "GohuFont 11 Nerd Font Medium 11"
  xfconf-query -c xsettings -p /Gtk/FontName -s "GohuFont 11 Nerd Font Mono Medium 10"

  log_info "${font} font installed successfully"
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

  log_info "Registering kitty as terminal alternative..."
  sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/kitty 30

  log_info "Setting kitty as default terminal..."
  sudo update-alternatives --set x-terminal-emulator /usr/bin/kitty
  sudo sed -i 's/^TerminalEmulator=.*/TerminalEmulator=kitty/' /etc/xdg/xfce4/helpers.rc

  log_info "Kitty installed successfully"
}

install_polybar() {
  local artifact="polybar"

  sudo apt install -y "${artifact}"
}

main "$@"
