#!/bin/bash
# Oracle Cloud Always Free - InsightFace Server Setup
# Run as: curl -sSL https://your-url.sh | bash
# Or: bash server_setup.sh

set -e

echo "=========================================="
echo "InsightFace Server Setup on Oracle Cloud"
echo "=========================================="

# Update system
echo "Updating system packages..."
sudo apt-get update
sudo apt-get upgrade -y

# Install Docker
echo "Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
rm get-docker.sh

# Add current user to docker group
sudo usermod -aG docker $USER
newgrp docker

# Install Docker Compose
echo "Installing Docker Compose..."
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Create app directory
echo "Creating application directory..."
mkdir -p ~/insightface-server
cd ~/insightface-server

# Enable swap (improves memory management on 24GB RAM)
echo "Configuring swap..."
sudo dd if=/dev/zero of=/swapfile bs=1G count=8
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null

# Configure firewall
echo "Configuring firewall..."
sudo firewall-cmd --permanent --add-port=8000/tcp || true
sudo firewall-cmd --reload || true

# Alternative for ufw
ufw allow 8000/tcp || true

echo "=========================================="
echo "Setup complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Copy Dockerfile, requirements.txt, docker-compose.yml, and app.py to ~/insightface-server/"
echo "2. Run: cd ~/insightface-server && docker-compose up -d"
echo "3. Check status: docker-compose logs -f"
echo "4. API will be available at: http://YOUR_VM_IP:8000"
echo "5. View API docs: http://YOUR_VM_IP:8000/docs"
echo ""
echo "To get your VM's IP:"
echo "  hostname -I"
echo ""
