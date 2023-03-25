#!/bin/bash

# We need to provide the following params when calling this script:
# Param 1 - code branch
# Param 2 - speed limit

# Install pip
sudo apt install python3-pip -y

# Clone the repo
git clone --branch $1 https://github.com/ekiczek/raspberry-pi-speed-radar.git

# pip install requirements
pip install -r /raspberry-pi-speed-radar/requirements.txt

# Setup service to run the speed radar now and on every reboot
# Reference: https://medium.com/@Tankado95/how-to-run-a-python-code-as-a-service-using-systemctl-4f6ad1835bf2

cat >> /lib/systemd/system/speed-radar.service <<EOL
[Unit]
Description=speed-radar
After=multi-user.target

[Service]
WorkingDirectory=/raspberry-pi-speed-radar
User=root
Type=idle
ExecStart=python3 /raspberry-pi-speed-radar/main.py $2 &> /dev/null
Restart=always

[Install]
WantedBy=multi-user.target
EOL

sudo systemctl daemon-reload
sudo systemctl enable speed-radar
sudo systemctl start speed-radar
