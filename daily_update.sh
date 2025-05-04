#!/bin/bash
# ログファイルの設定
LOG_FILE="/var/log/server_telemetry_update.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')
# ログファイルに書き込み権限を追加
echo "[$DATE] Starting update process..." | sudo tee -a "$LOG_FILE"

# Systemdサービスの停止
if sudo systemctl stop server_telemetry.service 2>&1 | sudo tee -a "$LOG_FILE"; then
    echo "[$DATE] Service stopped successfully" | sudo tee -a "$LOG_FILE"
    
    # Git pull
    cd /opt/server_telemetry
    if git pull 2>&1 | sudo tee -a "$LOG_FILE"; then
        echo "[$DATE] Git update successful" | sudo tee -a "$LOG_FILE"
        
        # setup.bashの実行
        if bash setup.bash 2>&1 | sudo tee -a "$LOG_FILE"; then
            echo "[$DATE] Setup script successful" | sudo tee -a "$LOG_FILE"
            
            # Systemdサービスの起動
            if sudo systemctl start server_telemetry.service 2>&1 | sudo tee -a "$LOG_FILE"; then
                echo "[$DATE] Service started successfully" | sudo tee -a "$LOG_FILE"
            else
                echo "[$DATE] Error: Service start failed" | sudo tee -a "$LOG_FILE"
            fi
        else
            echo "[$DATE] Error: Setup script failed" | sudo tee -a "$LOG_FILE"
            # セットアップが失敗してもサービスを起動
            sudo systemctl start server_telemetry.service 2>&1 | sudo tee -a "$LOG_FILE"
        fi
    else
        echo "[$DATE] Error: Git update failed" | sudo tee -a "$LOG_FILE"
        # Git pullが失敗してもサービスを起動
        sudo systemctl start server_telemetry.service 2>&1 | sudo tee -a "$LOG_FILE"
    fi
else
    echo "[$DATE] Error: Service stop failed" | sudo tee -a "$LOG_FILE"
fi

echo "[$DATE] Update process completed" | sudo tee -a "$LOG_FILE"
echo "----------------------------------------" | sudo tee -a "$LOG_FILE"
