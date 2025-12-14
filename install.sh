#!/usr/bin/env bash
set -e

echo "🚀 Installing sh-shortcut..."

mkdir -p ~/bin ~/.ssh/config.d

cat > ~/bin/sh <<'SCRIPT'
#!/usr/bin/env bash
CONF_MAIN="$HOME/.ssh/config"
CONF_DIR="$HOME/.ssh/config.d"
CONF_SH="$CONF_DIR/sh_hosts"

mkdir -p "$CONF_DIR"
touch "$CONF_SH"
chmod 600 "$CONF_SH"

if [ ! -f "$CONF_MAIN" ]; then
  touch "$CONF_MAIN"
  chmod 600 "$CONF_MAIN"
fi

if ! grep -q 'Include ~/.ssh/config.d/*' "$CONF_MAIN"; then
  echo 'Include ~/.ssh/config.d/*' >> "$CONF_MAIN"
fi

case "$1" in
  cr)
    echo "****************"
    read -p "Name remote : " name
    read -p "Server ip : " host
    read -p "Port : " port
    read -p "user : " user
    echo "****************"

    {
      echo ""
      echo "Host $name"
      echo "  HostName $host"
      echo "  Port $port"
      [ -n "$user" ] && echo "  User $user"
    } >> "$CONF_SH"

    echo "✅ Created shortcut: $name"
    ;;
  ls)
    grep "^Host " "$CONF_SH" | awk '{print " - "$2}'
    ;;
  rm)
    sed -i.bak "/^Host $2$/,/^$/d" "$CONF_SH"
    echo "🗑 Removed: $2"
    ;;
  *)
    ssh "$1"
    ;;
esac
SCRIPT

chmod +x ~/bin/sh

if ! echo "$PATH" | grep -q "$HOME/bin"; then
  echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc 2>/dev/null || true
  echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc 2>/dev/null || true
fi

echo "🎉 Installed! Restart terminal or run: source ~/.bashrc"
echo "👉 Use: sh cr"
