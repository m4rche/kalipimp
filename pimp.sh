#!/usr/bin/env bash

readonly NC=$(tput sgr0)
readonly RED=$(tput setaf 1)
readonly GREEN=$(tput setaf 2)
readonly YELLOW=$(tput setaf 3)
readonly BLUE=$(tput setaf 4)

readonly TMP_D="$(mktemp -d)"
trap "rm -rf '${TMP_D}'" EXIT

readonly GREETER_CONF="/etc/lightdm/lightdm-gtk-greeter.conf"
readonly REPO_ROOT="$(git rev-parse --show-toplevel)"
readonly STATIC_DIR="${REPO_ROOT}/static"

log_info()  { echo -e "[$(date '+%H:%M:%S')] ${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "[$(date '+%H:%M:%S')] ${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "[$(date '+%H:%M:%S')] ${RED}[ERROR]${NC} $*"; }

main() {
  if ! sudo -v; then
    log_error "Must run with sudo"
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
  set_pfp
  set_grub_theme
	set_plymouth_theme

  install_nvim
  install_kitty
  install_polybar
	install_rofi

  replicate_dotfiles
}

set_display_resolution() {
  local xorg_conf_d="/etc/X11/xorg.conf.d"

  local x=$1
  local y=$2
  local resolution="${x}x${y}"

  log_info "Setting display resolution ${resolution}"

  local screen=$(xrandr | grep ' connected' | awk '{printf $1}')
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
	xfconf-query -c xfwm4 -p /general/theme -s "${theme}"
  sudo sed -i "s/^theme-name\\s*=\\s*.*/theme-name = ${theme}/" "${GREETER_CONF}"

  log_info "Set theme ${theme}"
}

set_icons() {
  local icons=$1

  log_info "Setting icons ${icons}..."
  xfconf-query -c xsettings -p /Net/IconThemeName -s "${icons}"
  sudo sed -i "s/^icon-theme-name\\s*=\\s*.*/icon-theme-name = ${icons}/" "${GREETER_CONF}"

  log_info "Set icons ${icons}"

}

set_bg() {
  local artifact="kali-green.png"
  local bg_d="${HOME}/.local/share/backgrounds"

  mkdir -p "${bg_d}"

  log_info "Copying ${artifact} to ${bg_d}..."
  if ! cp "${STATIC_DIR}/${artifact}" "${bg_d}/${artifact}"; then
    log_warn "Copy failed"
    return
  fi

  log_info "Setting as background image..."

  # apply to all workspaces
  xfconf-query \
    -c xfce4-desktop \
    -p /backdrop/single-workspace-mode \
    -s true

  # set background
  props=$(xfconf-query -c xfce4-desktop -l | grep 'last-image')
  for prop in $props; do
    xfconf-query \
      -c xfce4-desktop \
      -p "${prop}" \
      -s "${bg_d}/${artifact}"
  done

  # style stretched (3)
  local props=$(xfconf-query -c xfce4-desktop -l | grep 'image-style')
  for prop in $props; do
    xfconf-query \
      -c xfce4-desktop \
      -p "${prop}" \
      -s 3
  done

  log_info "Applying blur before setting as login screen background image..."
  convert "${bg_d}/${artifact}" -blur 0x8 "${bg_d}/blurred-${artifact}"

  sudo cp "${bg_d}/blurred-${artifact}" "/usr/share/backgrounds/blurred-${artifact}"
  sudo sed -i "s|^background\\s*=\\s*.*|background = /usr/share/backgrounds/blurred-${artifact}|" "${GREETER_CONF}"

  log_info "Set background ${artifact}"
}

set_font() {
  local font="Gohu"
  local artifact="font.zip"
  local fonts_d="${HOME}/.local/share/fonts"

  mkdir -p "${fonts_d}"

  log_info "Extracting ${font} to ${fonts_d}..."
  if ! unzip -o -d "${fonts_d}" "${STATIC_DIR}/${artifact}"; then
    log_warn "Extraction failed"
    return
  fi

  log_info "Refreshing font cache..."
  fc-cache -f
  
  log_info "Setting ${font} as default font..."
  xfconf-query -c xsettings -p /Gtk/FontName -s "GohuFont 11 Nerd Font Medium 11"
  xfconf-query -c xsettings -p /Gtk/MonospaceFontName -s "GohuFont 11 Nerd Font Mono Medium 10"

  log_info "Extracting to /usr/share/fonts/truetype/${font}"
  if ! sudo unzip -o -d "/usr/share/fonts/truetype/${font}" "${STATIC_DIR}/${artifact}"; then
    log_warn "Extraction failed"
    return
  fi

  log_info "Refreshing system font cache..."
  sudo fc-cache -f 

  log_info "Applying ${font} to LightDM GTK Greeter..."
  sudo sed -i "s/^font-name\\s*=\\s*.*/font-name = GohuFont 11 Nerd Font Medium 11/" "${GREETER_CONF}"

  log_info "${font} font installed successfully"
}

set_pfp() {
  local artifact="pfp.png"

	log_info "Setting pfp..."
  cp "${STATIC_DIR}/${artifact}" "${HOME}/.face"

  log_info "Copying pfp to world-readable system path..."
  if ! sudo cp "${STATIC_DIR}/${artifact}" "/usr/share/pixmaps/${artifact}"; then
    log_warn "Copy failed"
    return
  fi
  sudo sed -i "s|^default-user-image\\s*=\\s*.*|default-user-image = /usr/share/pixmaps/${artifact}|" "${GREETER_CONF}"

  log_info "Set pfp ${artifact}"
}

set_grub_theme() {
  local artifact="darkmatter.zip"
  local theme_dir="/boot/grub/themes/darkmatter"
  local grub_cfg="/etc/default/grub"

  log_info "Setting grub theme..."

  log_info "Extracting theme..."
  if ! sudo unzip -o -d "${theme_dir}" "${STATIC_DIR}/${artifact}"; then
    log_warn "Extraction failed"
    return
  fi

  log_info "Configuring GRUB..."
  sudo sed -i 's/^GRUB_TERMINAL_OUTPUT/#GRUB_TERMINAL_OUTPUT/' "${grub_cfg}"
  sudo sed -i 's/^GRUB_TIMEOUT_STYLE/#GRUB_TIMEOUT_STYLE/' "${grub_cfg}"

  if grep -q '^GRUB_GFXMODE' "${grub_cfg}"; then
    sudo sed -i 's/^GRUB_GFXMODE.*/GRUB_GFXMODE=1920x1080/' "${grub_cfg}"
  else
    echo 'GRUB_GFXMODE=1920x1080' | sudo tee -a "${grub_cfg}" > /dev/null
  fi

  if grep -q '^GRUB_ENABLE_BLSCFG' "${grub_cfg}"; then
    sudo sed -i 's/^GRUB_ENABLE_BLSCFG.*/GRUB_ENABLE_BLSCFG=false/' "${grub_cfg}"
  else
    echo 'GRUB_ENABLE_BLSCFG=false' | sudo tee -a "${grub_cfg}" > /dev/null
  fi

  if grep -q '^GRUB_THEME' "${grub_cfg}"; then
    sudo sed -i "s|^GRUB_THEME=.*|GRUB_THEME=\"${theme_dir}/theme.txt\"|" "${grub_cfg}"
  else
    echo "GRUB_THEME=\"${theme_dir}/theme.txt\"" | sudo tee -a "${grub_cfg}" > /dev/null
  fi

  if grep -q '^GRUB_BACKGROUND' "${grub_cfg}"; then
    sudo sed -i 's|^GRUB_BACKGROUND=.*|GRUB_BACKGROUND="/boot/grub/themes/darkmatter/background.png"|' "${grub_cfg}"
  else
    echo 'GRUB_BACKGROUND="/boot/grub/themes/darkmatter/background.png"' | sudo tee -a "${grub_cfg}" > /dev/null
  fi

	local override
	override=$(grep -l 'GRUB_THEME' /etc/default/grub.d/*.cfg 2>/dev/null | head -1)
	if [[ -n "${override}" ]]; then
		sudo rm "${override}"
	fi

  log_info "Updating GRUB..."
  sudo grub-mkconfig -o /boot/grub/grub.cfg

  log_info "Dark Matter GRUB Theme installed successfully"
}

set_plymouth_theme() {
	local artifact="owl.zip"
	local theme_dir="/usr/share/plymouth/themes"

	log_info "Setting plymouth theme..."

	log_info "Extracting theme..."
	if ! sudo unzip -o -d "${theme_dir}/owl" "${STATIC_DIR}/${artifact}"; then
		log_warn "Extraction failed"
		return
	fi

	sudo plymouth-set-default-theme -R owl

	log_info "Plymouth theme set"
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

install_rofi() {
	local artifact="rofi"

	sudo apt install -y "${artifact}"
	xfconf-query -c xfce4-keyboard-shortcuts -np '/commands/custom/<Shift>space' -t string -s 'rofi -show drun'
}

dotfiles() {
  git --git-dir="$HOME/.dotfiles/" --work-tree="$HOME" $@
}

replicate_dotfiles() {
  local url="https://github.com/m4rche/dotfiles.git"

  git clone --branch kali --bare "${url}" "${HOME}/.dotfiles"
  dotfiles config --local status.showUntrackedFiles no
  dotfiles checkout -f
}

main "$@"
