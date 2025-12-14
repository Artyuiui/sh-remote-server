#!/usr/bin/env bash
set -euo pipefail

APP_NAME="sh-shortcut"
VERSION="1.0.0"

BIN_DIR="$HOME/bin"
BIN_PATH="$BIN_DIR/sh"
CONF_MAIN="$HOME/.ssh/config"
CONF_DIR="$HOME/.ssh/config.d"
CONF_SH="$CONF_DIR/sh_hosts"
META_DIR="$HOME/.config/sh-shortcut"
META_FILE="$META_DIR/meta.env"
COMPL_DIR="$HOME/.config/sh-shortcut/completions"

detect_shell() {
  # best-effort
  if [ -n "${SHELL:-}" ]; then basename "$SHELL"; else echo "bash"; fi
}

ensure_paths() {
  mkdir -p "$BIN_DIR" "$CONF_DIR" "$META_DIR" "$COMPL_DIR"
  touch "$CONF_SH"
  chmod 700 "$BIN_DIR" || true
  chmod 600 "$CONF_SH" || true

  if [ ! -f "$CONF_MAIN" ]; then
    touch "$CONF_MAIN"
    chmod 600 "$CONF_MAIN"
  fi

  # Ensure Include is present (safe + idempotent)
  if ! grep -qE '^\s*Include\s+~/.ssh/config\.d/\*' "$CONF_MAIN"; then
    {
      echo ""
      echo "# Added by $APP_NAME"
      echo "Include ~/.ssh/config.d/*"
    } >> "$CONF_MAIN"
  fi
}

write_binary() {
cat > "$BIN_PATH" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

CONF_MAIN="$HOME/.ssh/config"
CONF_DIR="$HOME/.ssh/config.d"
CONF_SH="$CONF_DIR/sh_hosts"
META_FILE="$HOME/.config/sh-shortcut/meta.env"

ensure() {
  mkdir -p "$CONF_DIR" "$HOME/.config/sh-shortcut"
  touch "$CONF_SH"
  chmod 600 "$CONF_SH" || true
  if [ ! -f "$CONF_MAIN" ]; then
    touch "$CONF_MAIN"
    chmod 600 "$CONF_MAIN"
  fi
  if ! grep -qE '^\s*Include\s+~/.ssh/config\.d/\*' "$CONF_MAIN"; then
    echo "Include ~/.ssh/config.d/*" >> "$CONF_MAIN"
  fi
}

get_version() {
  if [ -f "$META_FILE" ]; then
    # shellcheck disable=SC1090
    source "$META_FILE"
    echo "${SH_SHORTCUT_VERSION:-unknown}"
  else
    echo "unknown"
  fi
}

usage() {
  cat <<EOF
sh-shortcut (v$(get_version))

Commands:
  sh cr                 Create SSH shortcut (UI)
  sh <name>             SSH connect by shortcut name
  sh ls                 List shortcuts
  sh show <name>        Show shortcut details
  sh rm <name>          Remove shortcut
  sh key <name>         Create SSH key and guide upload
  sh --version          Show version
  sh --help             Help
EOF
}

ui_create() {
  ensure
  echo "****************"
  read -rp "Name remote : " NAME
  read -rp "Server ip : " HOST
  read -rp "Port : " PORT
  read -rp "user : (ถ้าไม่มีก็ไม่ต้องใส่) " USER
  read -rp "password : (ถ้าไม่มีก็ไม่ต้องใส่) " PASS
  echo "****************"

  NAME="$(echo "$NAME" | xargs)"
  HOST="$(echo "$HOST" | xargs)"
  PORT="$(echo "$PORT" | xargs)"
  USER="$(echo "$USER" | xargs)"
  PASS="$(echo "$PASS" | xargs)"

  if [ -z "$NAME" ] || [ -z "$HOST" ] || [ -z "$PORT" ]; then
    echo "❌ ต้องมี Name remote, Server ip, Port"
    exit 1
  fi

  if grep -qE "^Host[[:space:]]+$NAME([[:space:]]|\$)" "$CONF_SH"; then
    echo "❌ ชื่อนี้มีอยู่แล้ว: $NAME"
    echo "   ใช้: sh rm $NAME แล้วค่อยสร้างใหม่"
    exit 1
  fi

  {
    echo ""
    echo "Host $NAME"
    echo "  HostName $HOST"
    echo "  Port $PORT"
    [ -n "$USER" ] && echo "  User $USER"
    echo "  ServerAliveInterval 30"
    echo "  ServerAliveCountMax 3"
  } >> "$CONF_SH"

  if [ -n "$PASS" ]; then
    echo "⚠️  SSH ปกติไม่รองรับเก็บ password ใน config อย่างปลอดภัย"
    echo "    แนะนำใช้ SSH Key: sh key $NAME"
  fi

  echo "✅ สร้างคีย์ลัดแล้ว: $NAME"
  echo "➡️  ใช้เข้าเครื่อง: sh $NAME"
}

list_hosts() {
  ensure
  if ! grep -qE "^Host[[:space:]]+" "$CONF_SH"; then
    echo "(ยังไม่มีรายการ)"
    return
  fi
  awk '
    $1=="Host"{name=$2}
    $1=="HostName"{host=$2}
    $1=="Port"{port=$2}
    $1=="User"{user=$2}
    $1=="" && name!=""{
      printf " - %-16s %s:%s%s\n", name, host, port, (user!=""?("  user="+user):"")
      name=host=port=user=""
    }
    END{
      if(name!=""){
        printf " - %-16s %s:%s%s\n", name, host, port, (user!=""?("  user="+user):"")
      }
    }
  ' "$CONF_SH"
}

show_host() {
  ensure
  local NAME="${1:-}"
  [ -n "$NAME" ] || { echo "ใช้: sh show <name>"; exit 1; }
  awk -v n="$NAME" '
    $1=="Host" && $2==n {p=1}
    $1=="Host" && $2!=n {if(p==1) exit; p=0}
    p==1 {print}
  ' "$CONF_SH" || true
}

remove_host() {
  ensure
  local NAME="${1:-}"
  [ -n "$NAME" ] || { echo "ใช้: sh rm <name>"; exit 1; }

  if ! grep -qE "^Host[[:space:]]+$NAME([[:space:]]|\$)" "$CONF_SH"; then
    echo "❌ ไม่พบชื่อ: $NAME"
    exit 1
  fi

  awk -v n="$NAME" '
    BEGIN{del=0}
    $1=="Host" && $2==n {del=1; next}
    $1=="Host" && $2!=n {del=0}
    del==0 {print}
  ' "$CONF_SH" > "$CONF_SH.tmp"

  mv "$CONF_SH.tmp" "$CONF_SH"
  chmod 600 "$CONF_SH" || true
  echo "🗑️  ลบแล้ว: $NAME"
}

make_key() {
  ensure
  local NAME="${1:-}"
  [ -n "$NAME" ] || { echo "ใช้: sh key <name>"; exit 1; }

  local KEY="$HOME/.ssh/sh_${NAME}_ed25519"
  if [ -f "$KEY" ]; then
    echo "✅ มี key อยู่แล้ว: $KEY"
  else
    ssh-keygen -t ed25519 -f "$KEY" -C "sh:$NAME"
  fi

  echo "➡️  ส่ง public key ไปที่ server:"
  echo "    ssh-copy-id -i ${KEY}.pub $NAME"
  echo "    (ถ้าไม่มี ssh-copy-id: cat ${KEY}.pub แล้วเพิ่มใน ~/.ssh/authorized_keys ฝั่ง server)"
}

connect_host() {
  ensure
  local NAME="${1:-}"
  [ -n "$NAME" ] || { usage; exit 0; }
  exec ssh "$NAME"
}

ensure
cmd="${1:-}"
case "$cmd" in
  cr) ui_create ;;
  ls) list_hosts ;;
  show) shift; show_host "${1:-}" ;;
  rm) shift; remove_host "${1:-}" ;;
  key) shift; make_key "${1:-}" ;;
  --version|-v) get_version ;;
  --help|-h|help|"") usage ;;
  *) connect_host "$cmd" ;;
esac
SCRIPT
  chmod +x "$BIN_PATH"
}

write_meta() {
cat > "$META_FILE" <<EOF
SH_SHORTCUT_VERSION="$VERSION"
EOF
}

install_completions_files() {
  # bash
  cat > "$COMPL_DIR/sh.bash" <<'EOF'
_sh_shortcut_hosts() {
  local conf="$HOME/.ssh/config.d/sh_hosts"
  [ -f "$conf" ] || return 0
  awk '$1=="Host"{print $2}' "$conf"
}
_sh_shortcut() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local cmds="cr ls show rm key --help --version"
  local hosts="$(_sh_shortcut_hosts)"
  COMPREPLY=( $(compgen -W "$cmds $hosts" -- "$cur") )
}
complete -F _sh_shortcut sh
EOF

  # zsh
  cat > "$COMPL_DIR/sh.zsh" <<'EOF'
#compdef sh
_sh_shortcut_hosts() {
  local conf="$HOME/.ssh/config.d/sh_hosts"
  [[ -f "$conf" ]] || return 0
  awk '$1=="Host"{print $2}' "$conf"
}
_arguments "1: :($(echo cr ls show rm key --help --version $(_sh_shortcut_hosts)))"
EOF

  # fish
  cat > "$COMPL_DIR/sh.fish" <<'EOF'
function __sh_shortcut_hosts
  set conf "$HOME/.ssh/config.d/sh_hosts"
  if test -f $conf
    awk '$1=="Host"{print $2}' $conf
  end
end

complete -c sh -f
complete -c sh -n "not __fish_seen_subcommand_from cr ls show rm key --help --version" -a "cr ls show rm key --help --version"
complete -c sh -n "not __fish_seen_subcommand_from cr ls show rm key --help --version" -a "(__sh_shortcut_hosts)"
EOF
}

activate_completions() {
  local shell_name
  shell_name="$(detect_shell)"

  case "$shell_name" in
    bash)
      # load completion automatically
      local bashrc="$HOME/.bashrc"
      grep -q 'sh-shortcut completions' "$bashrc" 2>/dev/null || {
        cat >> "$bashrc" <<EOF

# $APP_NAME completions
if [ -f "$COMPL_DIR/sh.bash" ]; then
  source "$COMPL_DIR/sh.bash"
fi
EOF
      }
      ;;
    zsh)
      local zshrc="$HOME/.zshrc"
      grep -q 'sh-shortcut completions' "$zshrc" 2>/dev/null || {
        cat >> "$zshrc" <<EOF

# $APP_NAME completions
if [ -f "$COMPL_DIR/sh.zsh" ]; then
  source "$COMPL_DIR/sh.zsh"
fi
EOF
      }
      ;;
    fish)
      mkdir -p "$HOME/.config/fish/completions"
      ln -sf "$COMPL_DIR/sh.fish" "$HOME/.config/fish/completions/sh.fish"
      ;;
    *)
      # unknown shell: do nothing
      ;;
  esac
}

ensure_path_export() {
  local shell_name; shell_name="$(detect_shell)"
  case "$shell_name" in
    bash)
      grep -q 'export PATH="$HOME/bin:$PATH"' "$HOME/.bashrc" 2>/dev/null || \
        echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
      ;;
    zsh)
      grep -q 'export PATH="$HOME/bin:$PATH"' "$HOME/.zshrc" 2>/dev/null || \
        echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.zshrc"
      ;;
    fish)
      # fish stores PATH differently; we avoid editing and rely on user having ~/bin in PATH
      # Many distros already add it. If not, user can: set -U fish_user_paths $HOME/bin $fish_user_paths
      ;;
  esac
}

echo "🚀 Installing $APP_NAME v$VERSION ..."
ensure_paths
write_binary
write_meta
install_completions_files
activate_completions
ensure_path_export

echo "✅ Done!"
echo "👉 Open a new terminal (or source your shell rc) then try:"
echo "   sh cr"
echo "   sh ls"
