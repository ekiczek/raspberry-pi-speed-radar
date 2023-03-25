#!/bin/bash

# We need to provide the following params when calling this script:
# Param 1 - code branch
# Param 2 - speed limit

# Install pip
sudo apt install python3-pip -y

# Clone the repo
git clone --branch $1 https://github.com/ekiczek/raspberry-pi-speed-radar.git

# pip install requirements
pip install -r raspberry-pi-speed-radar/requirements.txt

# Setup service to run the speed radar now and on every reboot
# Reference: https://medium.com/@Tankado95/how-to-run-a-python-code-as-a-service-using-systemctl-4f6ad1835bf2

cat >> /lib/systemd/system/speed-radar.service <<EOL
[Unit]
Description=speed-radar
After=multi-user.target

[Service]
WorkingDirectory=/home/ubuntu/raspberry-pi-speed-radar
User=root
Type=idle
ExecStart=python3 /home/ubuntu/raspberry-pi-speed-radar/main.py $2 &> /dev/null
Restart=always

[Install]
WantedBy=multi-user.target
EOL

sudo systemctl daemon-reload
sudo systemctl enable speed-radar
sudo systemctl start speed-radar








> /home/pi/speed.log


# Install Dockah
sudo apt install -y docker.io

# Fixing a problem with flannel, solution discussed at https://www.learnlinux.tv/quick-fix-crashloopbackoff-while-building-a-kubernetes-cluster-with-ubuntu-22-04-on-the-raspberry-pi/
sudo apt update && sudo apt install -y linux-modules-extra-raspi

# Add the packages.cloud.google.com atp key
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

# Add the Kubernetes repo
sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"

# Update the apt cache and install kubelet, kubeadm, and kubectl
# (Output omitted)
sudo apt update && sudo apt install -y kubelet=1.23.17-00 kubeadm=1.23.17-00 kubectl=1.23.17-00

# Disable (mark as held) updates for the Kubernetes packages
sudo apt-mark hold kubelet kubeadm kubectl

# -------------------------------------------------
# Setup post-reboot script
# -------------------------------------------------

if [ $(hostname -I | awk '{print $1;}') == $1 ] # master
then

  # K8s can't have all nodes called ubuntu, must have unique names, so set master to "master"
  sudo hostnamectl set-hostname master

  # Write a startup script for next boot
  sudo cat > /home/ubuntu/startup.sh <<EOF
sudo kubeadm init --token=$2 --pod-network-cidr=10.244.0.0/16

mkdir -p /root/.kube
sudo cp -i /etc/kubernetes/admin.conf /root/.kube/config
sudo chown $(id -u):$(id -g) /root/.kube/config

# Setup .kube/config for ubuntu user too, for troubleshooting
mkdir -p /home/ubuntu/.kube
sudo cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
sudo chown ubuntu:ubuntu /home/ubuntu/.kube
sudo chown ubuntu:ubuntu /home/ubuntu/.kube/config

# Download the Flannel YAML data and apply it
curl -sSL https://raw.githubusercontent.com/coreos/flannel/v0.21.3/Documentation/kube-flannel.yml | kubectl apply -f -

# Remove startup script after this run
sudo rm -f /home/ubuntu/startup.sh
sudo rm /etc/cron.d/run_setup
EOF
  sudo chmod 755 /home/ubuntu/startup.sh

  # Set cron to run startup.sh on next boot
  sudo chmod 757 /etc/cron.d
  sudo cat > /etc/cron.d/run_setup <<EOF
@reboot root sleep 60 && /home/ubuntu/startup.sh
EOF
  sudo chmod 755 /etc/cron.d

  # Enable promiscuous mode if ENABLE_PROMISCUOUS_MODE is set
  if [ ! -z "${ENABLE_PROMISCUOUS_MODE}" ]
  then

    # Enable promiscuous mode and enable on every boot
    sudo ip link set wlan0 promisc on
    sudo chmod 757 /etc/cron.d
    sudo cat > /etc/cron.d/enable_promiscuous_mode <<EOF
@reboot root sudo ip link set wlan0 promisc on
EOF
    sudo chmod 755 /etc/cron.d
  fi
else
  # K8s can't have all nodes called ubuntu, must have unique names, so set worker node names to
  # "node" plus last octet of the wifi IP address
  sudo hostnamectl set-hostname $(echo "node"$(hostname -I | awk '{print $1;}' | cut -d"." -f4))

  # Write a startup script for next boot
  sudo cat > /home/ubuntu/startup.sh <<EOF
# Wait 5 minutes for the master to come up
sleep 600

# This allows us to pre-configure a token and then skip the CA cert hash (less secure, but good enough for our requirements):
sudo kubeadm join $1:6443 --token $2 --discovery-token-unsafe-skip-ca-verification

# Remove startup script after this run
sudo rm -f /home/ubuntu/startup.sh
sudo rm /etc/cron.d/run_setup
EOF
  sudo chmod 755 /home/ubuntu/startup.sh

  # Set cron to run startup.sh on next boot
  sudo chmod 757 /etc/cron.d
  sudo cat > /etc/cron.d/run_setup <<EOF
@reboot root sleep 60 && /home/ubuntu/startup.sh
EOF
  sudo chmod 755 /etc/cron.d

  # Enable promiscuous mode if ENABLE_PROMISCUOUS_MODE is set
  if [ ! -z "${ENABLE_PROMISCUOUS_MODE}" ]
  then

    # Enable promiscuous mode and enable on every boot
    sudo ip link set wlan0 promisc on
    sudo chmod 757 /etc/cron.d
    sudo cat > /etc/cron.d/enable_promiscuous_mode <<EOF
@reboot root sudo ip link set wlan0 promisc on
EOF
    sudo chmod 755 /etc/cron.d
  fi
fi

# Cleanup after this script
rm -f /home/ubuntu/bootstrap.sh

sudo shutdown now -r
