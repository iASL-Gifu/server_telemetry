# InfluxDB接続情報
INFLUXDB_URL = "http://192.168.11.3:8086"
INFLUXDB_TOKEN = "kUM-45ZbLCp4EtXiJ3bv7LfagMqhBDlWguKL70Zv4wJil1orh-JFktCDoPjrhcXsGqNEJamnnolZqW6Vgfpe6w=="
INFLUXDB_ORG = "my-orgs"
INFLUXDB_BUCKET = "server-telemetry"

import shutil
import os
import socket
import platform
import cpuinfo
import psutil
import time
from influxdb_client import InfluxDBClient, Point
from datetime import datetime

# nvidia-smiコマンド存在チェック
nvidia_smi_exists = shutil.which("nvidia-smi") is not None

# pynvml(GPU情報用)インポート
nvml_available = False
if nvidia_smi_exists:
    from pynvml import (
        nvmlInit,
        nvmlDeviceGetHandleByIndex,
        nvmlDeviceGetMemoryInfo,
        nvmlDeviceGetName,
        nvmlDeviceGetPowerUsage,
        nvmlDeviceGetCount,
        nvmlDeviceGetUtilizationRates,
        nvmlDeviceGetTemperature,
        NVML_TEMPERATURE_GPU
    )
    nvmlInit()
    nvml_available = True
else:
    print("[Info] nvidia-smi not found. Skipping GPU telemetry.")


# ホスト基本情報
hostname = socket.gethostname()
cpu_model = cpuinfo.get_cpu_info()["brand_raw"]
logical_cores = psutil.cpu_count(logical=True)
physical_cores = psutil.cpu_count(logical=False)
core_info_str = f"{physical_cores} / {logical_cores}"
# ネットワーク速度計測用
last_net = psutil.net_io_counters()
last_time = time.time()

def get_network_speed():
    global last_net, last_time
    current_net = psutil.net_io_counters()
    current_time = time.time()

    elapsed = current_time - last_time
    if elapsed == 0:
        return 0.0, 0.0

    rx_bytes = current_net.bytes_recv - last_net.bytes_recv
    tx_bytes = current_net.bytes_sent - last_net.bytes_sent

    rx_kbps = (rx_bytes * 8) / elapsed / 1000  # kbps
    tx_kbps = (tx_bytes * 8) / elapsed / 1000

    last_net = current_net
    last_time = current_time

    return rx_kbps, tx_kbps

# CPU温度取得
def get_cpu_temp():
    try:
        temps = psutil.sensors_temperatures()
        print(temps)
        if 'coretemp' in temps:
            for core in temps['coretemp']:
                if "Package" in core.label:
                    return core.current
            return temps['coretemp'][0].current
        elif 'k10temp' in temps:
            for entry in temps['k10temp']:
                if entry.label == 'Tctl':
                    return entry.current
            # フォールバック：一番目の値を使う
            return temps['k10temp'][0].current
    except Exception:
        pass
    return None

# GPU温度取得
def get_gpu_temp(handle):
    try:
        return nvmlDeviceGetTemperature(handle, NVML_TEMPERATURE_GPU)
    except Exception:
        return None

# InfluxDBクライアント
client = InfluxDBClient(url=INFLUXDB_URL, token=INFLUXDB_TOKEN, org=INFLUXDB_ORG)
write_api = client.write_api()

def collect_and_send():
    points = []

    # CPU/メモリ/ネットワーク情報 → 1回だけ
    cpu_usage = psutil.cpu_percent(interval=1)
    cpu_temp = get_cpu_temp()
    mem = psutil.virtual_memory()
    mem_total_gb = mem.total / (1024 ** 3)
    mem_used_gb = mem.used / (1024 ** 3)
    mem_used_percent = mem.percent
    rx_kbps, tx_kbps = get_network_speed()

    cpu_point = (
        Point("server_telemetry")
        .tag("hostname", hostname)
        .field("cpu_model", cpu_model)
        .field("cpu_core_info", core_info_str) 
        .field("cpu_usage", round(cpu_usage, 2))
        .field("cpu_temp", round(cpu_temp, 2))
        .field("mem_total_gb", round(mem_total_gb, 2))
        .field("mem_used_percent", round(mem_used_percent, 2))
        .field("mem_used_gb", round(mem_used_gb, 2))
        .field("rx_kbps", round(rx_kbps, 2))
        .field("tx_kbps", round(tx_kbps, 2))
    )
    print(cpu_point.to_line_protocol())  # 書き込むデータを確認
    points.append(cpu_point)

    # GPU情報 → GPUごとに1行ずつ
    if nvml_available:
        gpu_count = nvmlDeviceGetCount()
        for i in range(gpu_count):
            handle = nvmlDeviceGetHandleByIndex(i)
            gpu_name = nvmlDeviceGetName(handle)
            gpu_util = nvmlDeviceGetUtilizationRates(handle).gpu
            gpu_temp = nvmlDeviceGetTemperature(handle, NVML_TEMPERATURE_GPU)
            gpu_mem = nvmlDeviceGetMemoryInfo(handle)
            gpu_mem_used = gpu_mem.used / (1024 ** 3)  # GB単位
            gpu_mem_total = gpu_mem.total / (1024 ** 3)
            gpu_mem_util = (gpu_mem.used / gpu_mem.total) * 100  # 利用率[%]
            power_watt = nvmlDeviceGetPowerUsage(handle) / 1000

            gpu_point = (
                Point("server_telemetry")
                .tag("hostname", hostname)
                .tag("gpu_index", str(i))
                .tag("gpu_model", gpu_name)
                .field("gpu_usage", round(gpu_util, 2))
                .field("gpu_temp", round(gpu_temp, 2))
                .field("gpu_mem_used_gb", round(gpu_mem_used, 2))
                .field("gpu_mem_util", round(gpu_mem_util, 2))
                .field("gpu_mem_total", round(gpu_mem_total, 2))
                .field("gpu_power_watt", round(power_watt, 2))
            )
            print(gpu_point.to_line_protocol())  # 書き込むデータを確認
            points.append(gpu_point)

    # 一括書き込み
    write_api.write(bucket=INFLUXDB_BUCKET, record=points)

if __name__ == "__main__":
    while True:
        collect_and_send()
        time.sleep(10)


if __name__ == "__main__":
    while True:
        collect_and_send()
        time.sleep(60)  # 60秒ごとに送信

