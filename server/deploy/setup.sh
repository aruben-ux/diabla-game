#!/bin/bash
# Diabla Server Setup Script for Hetzner VPS (Ubuntu 22.04+)
# Run as root on a fresh VPS.

set -e

echo "=== Diabla Server Setup ==="

# --- System packages ---
apt-get update
apt-get install -y python3 python3-pip python3-venv postgresql postgresql-contrib ufw

# --- Firewall ---
ufw allow OpenSSH
ufw allow 8080/tcp   # Lobby server API + WebSocket
ufw allow 9000:9099/udp  # Game server ports (ENet)
ufw --force enable

# --- PostgreSQL Setup ---
echo "Setting up PostgreSQL..."
sudo -u postgres psql -c "CREATE USER diabla WITH PASSWORD 'diabla';" || true
sudo -u postgres psql -c "CREATE DATABASE diabla OWNER diabla;" || true
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE diabla TO diabla;" || true

# --- Application directory ---
APP_DIR="/opt/diabla"
mkdir -p "$APP_DIR/server"
echo "Copy your server/ directory contents to $APP_DIR/server/"
echo "Copy your exported Godot .pck file to $APP_DIR/diabla.pck"

# --- Python virtual environment ---
cd "$APP_DIR/server"
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# --- Environment variables ---
cat > "$APP_DIR/server/.env" << 'EOF'
DIABLA_DATABASE_URL=postgresql+asyncpg://diabla:diabla@localhost:5432/diabla
DIABLA_JWT_SECRET=CHANGE-THIS-TO-A-RANDOM-SECRET
DIABLA_HOST=0.0.0.0
DIABLA_PORT=8080
DIABLA_GODOT_EXECUTABLE=/opt/diabla/godot-server
DIABLA_GODOT_PROJECT_PATH=/opt/diabla/diabla.pck
DIABLA_GAME_PORT_START=9000
DIABLA_GAME_PORT_END=9099
DIABLA_GAME_SERVER_SECRET=CHANGE-THIS-GAME-SECRET
EOF

echo "IMPORTANT: Edit $APP_DIR/server/.env and change the secrets!"

# --- Systemd service for lobby server ---
cat > /etc/systemd/system/diabla-lobby.service << EOF
[Unit]
Description=Diabla Lobby Server
After=network.target postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR/server
EnvironmentFile=$APP_DIR/server/.env
ExecStart=$APP_DIR/server/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8080
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable diabla-lobby

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Copy server/ files to $APP_DIR/server/"
echo "  2. Download Godot headless server binary to $APP_DIR/godot-server"
echo "     (https://godotengine.org/download/server/)"
echo "  3. Export your Godot project as a .pck and copy to $APP_DIR/diabla.pck"
echo "  4. Edit $APP_DIR/server/.env — change JWT_SECRET and GAME_SERVER_SECRET"
echo "  5. Run: systemctl start diabla-lobby"
echo "  6. Check: systemctl status diabla-lobby"
echo "  7. Check logs: journalctl -u diabla-lobby -f"
echo ""
echo "Database migration (first time only):"
echo "  sudo -u postgres psql -d diabla -f $APP_DIR/server/migrations/001_init.sql"
echo ""
echo "Or just start the lobby server — it auto-creates tables on startup."
