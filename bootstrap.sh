#!/bin/bash

# We need to provide the following params when calling this script:
# Param 1 - code branch
# Param 2 - speed limit
# Param 3 - AWS IoT Core API endpoint
# Param 4 - AWS IoT Core ca_file
# Param 5 - AWS IoT Core cert
# Param 6 - AWS IoT Core key
# Param 7 - AWS IoT Core client_id
# Param 8 - AWS IoT Core topic

# Install pip
sudo apt install python3-pip -y

# Clone the repo
git clone --branch $1 https://github.com/ekiczek/raspberry-pi-speed-radar.git

# pip install requirements
pip install -r /raspberry-pi-speed-radar/requirements.txt


# Setup AWS IoT stuff, beginning with downloading the AWS IoT Root CA
if [ ! -f ./root-CA.crt ]; then
  printf "\nDownloading AWS IoT Root CA certificate from AWS...\n"
  curl https://www.amazontrust.com/repository/AmazonRootCA1.pem > root-CA.crt
fi

# Check to see if AWS Device SDK for Python exists, download if not
if [ ! -d ./aws-iot-device-sdk-python-v2 ]; then
  printf "\nCloning the AWS SDK...\n"
  git clone https://github.com/aws/aws-iot-device-sdk-python-v2.git --recursive
fi

# Check to see if AWS Device SDK for Python is already installed, install if not
if ! python3 -c "import awsiot" &> /dev/null; then
  printf "\nInstalling AWS SDK...\n"
  python3 -m pip install ./aws-iot-device-sdk-python-v2
  result=$?
  if [ $result -ne 0 ]; then
    printf "\nERROR: Failed to install SDK.\n"
    exit $result
  fi
fi

# The script needs to access the AWS SDK command line utilities, so copy it to the same directory as the script.
cp aws-iot-device-sdk-python-v2/samples/utils/command_line_utils.py /raspberry-pi-speed-radar/.

# Move root CA (installed during pip install above) to the repo directory
mv root-CA.crt /raspberry-pi-speed-radar/.

# Move all of the AWS IoT files defined in user-data to our repo for injestion
mv /aws_iot_thing_connect/* /raspberry-pi-speed-radar/.

rmdir /aws_iot_thing_connect
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
ExecStart=python3 /raspberry-pi-speed-radar/main.py --speed_limit $2 --endpoint $3 --ca_file $4 --cert $5 --key $6 --client_id $7 --topic $8
Restart=always

[Install]
WantedBy=multi-user.target
EOL

sudo systemctl daemon-reload
sudo systemctl enable speed-radar
sudo systemctl start speed-radar
