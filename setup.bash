#!/bin/bash

# 現在のユーザー名とグループを取得
CURRENT_USER=$(whoami)
CURRENT_GROUP=$(id -gn)

# 作業ディレクトリと仮想環境パスを設定
INSTALL_DIR="/opt/iASL_telemetry"
VENV_PATH="$INSTALL_DIR/telem_venv"

echo "Setting up telemetry service for user: $CURRENT_USER"

# 必要なディレクトリの権限確認と修正
if [ ! -w "$INSTALL_DIR" ]; then
    echo "Ensuring write permissions to $INSTALL_DIR..."
    sudo chown -R $CURRENT_USER:$CURRENT_GROUP "$INSTALL_DIR"
fi

# 必要なパッケージのインストール確認
echo "Checking for required packages..."
command -v python3 >/dev/null 2>&1 || { echo "Python3 is required but not installed. Aborting."; exit 1; }
command -v python3-venv >/dev/null 2>&1 || sudo apt-get install -y python3-venv

# 仮想環境の作成
echo "Creating Python virtual environment at $VENV_PATH..."
python3 -m venv "$VENV_PATH"

# 仮想環境を有効化して必要なパッケージをインストール
echo "Installing required Python packages..."
source "$VENV_PATH/bin/activate"
pip install --upgrade pip
# テレメトリーに必要なパッケージをインストール
pip install psutil influxdb_client
# GPUがあれば関連パッケージもインストール
if command -v nvidia-smi >/dev/null 2>&1; then
    echo "NVIDIA GPU detected, installing pynvml..."
    pip install pynvml
fi
deactivate

# サービスファイルのテンプレート
echo "Creating service file..."
cat > telem.service << EOF
[Unit]
Description=Server Telemetry Service
After=network.target

[Service]
Type=simple
ExecStart=$VENV_PATH/bin/python $INSTALL_DIR/telem.py
WorkingDirectory=$INSTALL_DIR
Restart=on-failure
User=$CURRENT_USER
Group=$CURRENT_GROUP

[Install]
WantedBy=multi-user.target
EOF

# サービスファイルをシステムの場所にコピー
echo "Installing service file..."
sudo cp telem.service /etc/systemd/system/

# systemd に新しいサービスファイルを読み込ませる
echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

# サービスを有効化して起動
echo "Enabling and starting telemetry service..."
sudo systemctl enable telem.service
sudo systemctl start telem.service

echo "Telemetry service setup complete!"
echo "Service running as: $CURRENT_USER"
echo "Using Python environment: $VENV_PATH"
echo "Working directory: $INSTALL_DIR"
