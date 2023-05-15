#!/bin/bash

# Enable ssh password authentication
echo "[TASK 1] Enable ssh password authentication"
sed -i 's/^PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
systemctl reload sshd
# update sudoers file for kubernetes admin account
echo 'kadmin    ALL=(ALL:ALL) NOPASSWD:ALL' >> /etc/sudoers

# Set Root password
echo "[TASK 2] Set root password"
echo -e "Admin123!\nAdmin123!" | passwd root >/dev/null 2>&1
