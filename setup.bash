#!/bin/bash

# 現在のユーザー名とグループを取得
CURRENT_USER=$(whoami)
CURRENT_GROUP=$(id -gn)

# 作業ディレクトリと仮想環境パスを設定
INSTALL_DIR="/opt/server_telemetry"
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
cat > server_telemetry.service << EOF
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
sudo cp server_telemetry.service /etc/systemd/system/

# systemd に新しいサービスファイルを読み込ませる
echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

# サービスを有効化して起動
echo "Enabling and starting telemetry service..."
sudo systemctl enable server_telemetry.service
sudo systemctl start server_telemetry.service

echo "Telemetry service setup complete!"
echo "Service running as: $CURRENT_USER"
echo "Using Python environment: $VENV_PATH"
echo "Working directory: $INSTALL_DIR"


# Crontabの設定
echo "Setting up crontab for daily updates..."

# 一時ファイルにcrontabの内容を出力
crontab -l > /tmp/mycron 2>/dev/null || true

# 既存のdaily_update.shエントリーを削除
sed -i '/daily_update.sh/d' /tmp/mycron

# telemetry updateのコメント行も削除
sed -i '/# Everyday telemetry update/d' /tmp/mycron
sed -i '/# Daily telemetry update/d' /tmp/mycron

# 新しい設定を追加
echo "# Everyday telemetry update" >> /tmp/mycron
echo "0 4 * * * /opt/server_telemetry/daily_update.sh" >> /tmp/mycron

# 新しいcrontabを設定
crontab /tmp/mycron
echo "Crontab entry updated successfully."

# 一時ファイルを削除
rm /tmp/mycron

# 確認
echo "Current crontab:"
crontab -l


  
# Sudoers設定を追加（パスワードなしでのsudo実行を許可）
echo "Setting up sudoers configuration..."

# 現在のユーザー名を取得
CURRENT_USER=$(whoami)

# sudoersファイルが既に存在するか確認
if [ ! -f "/etc/sudoers.d/server_telemetry" ]; then
    # sudoersファイルを作成
    sudo tee /etc/sudoers.d/server_telemetry > /dev/null << EOF
# Allow $CURRENT_USER to manage server_telemetry service without password
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl start server_telemetry.service
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop server_telemetry.service
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart server_telemetry.service
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl status server_telemetry.service

# Allow $CURRENT_USER to write to the log file
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/tee -a /var/log/server_telemetry_update.log
EOF

    # 適切な権限を設定
    sudo chmod 440 /etc/sudoers.d/server_telemetry
    echo "Sudoers configuration added successfully for user: $CURRENT_USER"
else
    echo "Sudoers configuration already exists."
fi
