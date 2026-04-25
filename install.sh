echo installing docker
sudo curl -fsSL https://get.docker.com | sh
echo creating dirs
mkdir /opt/remnanode && cd /opt/remnanode
echo WARNING!
echo copy ur docker-compose.yml from remnawave panel, paste, and click ctrl + x, then y, then enter
cd /opt/remnanode && nano docker-compose.yml
echo starting vpn...
docker compose up -d && docker compose logs -f -t
