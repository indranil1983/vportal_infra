sudo systemctl enable --now ssh
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo apt update
sudo apt install -y curl

curl --location "https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh" | sudo bash

sudo GITLAB_ROOT_EMAIL="vplatform@gmail.com" GITLAB_ROOT_PASSWORD="Vplatform123" EXTERNAL_URL="http://gitlab.vplatform.com" apt install gitlab-ce