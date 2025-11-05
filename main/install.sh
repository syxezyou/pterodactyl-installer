#!/bin/bash

# ========================================================================================
# Script d'installation automatique pour Pterodactyl Panel & Wings
# Auteur: syxezyou
# Version: 1.0
# OS: Debian 12 (Bookworm) ou supérieur
# URL d'exécution : curl -sL https://VOTRE_URL_RAW_GITHUB | sudo bash
# ========================================================================================

# --- Configuration des couleurs pour les logs ---
COLOR_RESET='\033[0m'
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'

# --- Fonctions d'affichage ---
log_info() {
    echo -e "${COLOR_BLUE}[INFO] $1${COLOR_RESET}"
}

log_success() {
    echo -e "${COLOR_GREEN}[SUCCESS] $1${COLOR_RESET}"
}

log_warning() {
    echo -e "${COLOR_YELLOW}[WARNING] $1${COLOR_RESET}"
}

log_error() {
    echo -e "${COLOR_RED}[ERROR] $1${COLOR_RESET}"
}

# --- Vérification de l'utilisateur (doit être root) ---
if [ "$(id -u)" -ne 0 ]; then
  log_error "Ce script doit être exécuté en tant que root. Essayez avec : curl -sL URL | sudo bash"
  exit 1
fi

# --- Début du script ---
log_info "Lancement du script d'installation de Pterodactyl..."
sleep 2

# --- Demander les informations utilisateur ---
log_info "Veuillez fournir les informations suivantes :"
read -p "Entrez votre nom de domaine pour le panel (ex: panel.votredomaine.com): " FQDN
read -p "Entrez votre adresse e-mail (pour le certificat SSL Let's Encrypt): " EMAIL

if [ -z "$FQDN" ] || [ -z "$EMAIL" ]; then
    log_error "Le nom de domaine et l'e-mail ne peuvent pas être vides."
    exit 1
fi

# --- Étape 1: Mise à jour du système et installation des dépendances ---
log_info "Mise à jour du système et installation des dépendances..."
apt-get update
apt-get upgrade -y
apt-get install -y software-properties-common curl apt-transport-https ca-certificates gnupg2 dirmngr

# Ajout des dépôts nécessaires (PHP & NodeJS)
log_info "Configuration des dépôts pour PHP, NodeJS et MariaDB..."
curl -sS https://packages.sury.org/php/README.txt | bash -x
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
curl -o /etc/apt/keyrings/mariadb-keyring.pgp 'https://mariadb.org/mariadb_release_signing_key.pgp'
echo "deb [signed-by=/etc/apt/keyrings/mariadb-keyring.pgp] https://deb.mariadb.org/10.11/debian bookworm main" > /etc/apt/sources.list.d/mariadb.list

# Mise à jour après ajout des dépôts
apt-get update

# Installation des paquets
log_info "Installation de Nginx, MariaDB, Redis, PHP, NodeJS et autres outils..."
apt-get install -y nginx mariadb-server mariadb-client redis-server \
    php8.2 php8.2-cli php8.2-fpm php8.2-mysql php8.2-gd php8.2-mbstring \
    php8.2-curl php8.2-xml php8.2-zip php8.2-bcmath \
    nodejs git unzip tar curl wget certbot python3-certbot-nginx

log_success "Dépendances installées avec succès."

# --- Étape 2: Configuration de MariaDB ---
log_info "Configuration de la base de données MariaDB..."
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 24)
DB_PASSWORD=$(openssl rand -base64 24)

# Commandes SQL pour configurer la base de données
SQL_COMMANDS="
CREATE DATABASE IF NOT EXISTS pterodactyl;
CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON pterodactyl.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
"
# Exécution des commandes SQL
mysql -u root -e "$SQL_COMMANDS"

log_success "Base de données 'pterodactyl' et utilisateur créés."
log_warning "Le mot de passe root de MariaDB a été défini. Conservez-le en lieu sûr."

# --- Étape 3: Installation de Composer ---
log_info "Installation de Composer..."
if [ ! -f "/usr/local/bin/composer" ]; then
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    log_success "Composer a été installé."
else
    log_info "Composer est déjà installé."
fi

# --- Étape 4: Installation du Panel Pterodactyl ---
log_info "Installation du panel Pterodactyl dans /var/www/pterodactyl..."
mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl

# Téléchargement et décompression
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
rm panel.tar.gz

# Configuration des permissions
chown -R www-data:www-data /var/www/pterodactyl/*

# Installation des dépendances PHP
log_info "Installation des dépendances avec Composer..."
composer install --no-dev --optimize-autoloader

# Configuration du fichier .env
log_info "Configuration du fichier .env..."
cp .env.example .env
composer update
php artisan key:generate --force

# Configuration de l'environnement, de la base de données et de l'admin
APP_URL="https://$FQDN"
ADMIN_PASSWORD=$(openssl rand -base64 16)

php artisan p:environment:setup -n --author=$EMAIL --url=$APP_URL --timezone=UTC --cache=redis --session=redis --queue=redis --redis-host=127.0.0.1 --redis-pass= --redis-port=6379
php artisan p:database:setup -n --database=pterodactyl --username=pterodactyl --password=$DB_PASSWORD
php artisan migrate --seed --force
php artisan p:user:make -n --email=$EMAIL --username=admin --name-first=Admin --name-last=User --password=$ADMIN_PASSWORD --admin=1

log_success "Panel Pterodactyl configuré."

# --- Étape 5: Configuration du service de file d'attente (pteroq) ---
log_info "Configuration du service systemd 'pteroq'..."
cat > /etc/systemd/system/pteroq.service << EOL
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOL

# Configuration du cronjob
(crontab -l 2>/dev/null; echo "* * * * * /usr/bin/php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | crontab -

# --- Étape 6: Configuration de Nginx et SSL ---
log_info "Configuration de Nginx pour le domaine $FQDN..."
cat > /etc/nginx/sites-available/pterodactyl.conf << EOL
server {
    listen 80;
    server_name $FQDN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $FQDN;

    root /var/www/pterodactyl/public;
    index index.php;

    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    # La configuration SSL sera gérée par Certbot
    
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag "noindex, nofollow";
    add_header Content-Security-Policy "frame-ancestors 'self'";
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy "same-origin";

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOL

ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf

# Génération du certificat SSL
log_info "Génération du certificat SSL avec Certbot..."
certbot --nginx --agree-tos --redirect --hsts --staple-ocsp --email $EMAIL -d $FQDN -n

log_success "Nginx et SSL configurés."

# --- Étape 7: Installation de Pterodactyl Wings ---
log_info "Installation de Pterodactyl Wings..."
mkdir -p /etc/pterodactyl
curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64"
chmod +x /usr/local/bin/wings

# Création du service systemd pour Wings
log_info "Configuration du service systemd 'wings'..."
cat > /etc/systemd/system/wings.service << EOL
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=600

[Install]
WantedBy=multi-user.target
EOL

# Installation de Docker
log_info "Installation de Docker pour Wings..."
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
log_success "Docker installé et activé."

# --- Étape 8: Activation des services et configuration du pare-feu ---
log_info "Activation et démarrage des services..."
systemctl enable --now redis-server
systemctl enable --now mariadb
systemctl enable --now nginx
systemctl enable --now pteroq
systemctl enable --now wings

# Configuration du pare-feu UFW
log_info "Configuration du pare-feu (UFW)..."
apt-get install -y ufw
ufw allow ssh
ufw allow 80/tcp   # HTTP
ufw allow 443/tcp  # HTTPS
ufw allow 8080/tcp # Port par défaut pour les serveurs de jeu
ufw allow 2022/tcp # Port par défaut pour le SFTP des serveurs
ufw enable

log_success "Services activés et pare-feu configuré."

# --- Étape 9: Finalisation et affichage des informations ---
log_info "L'installation est presque terminée !"
log_warning "Une dernière étape manuelle est requise :"
echo "1. Connectez-vous au panel Pterodactyl à l'adresse https://$FQDN"
echo "2. Allez dans l'interface d'administration (icône en haut à droite)."
echo "3. Allez dans 'Locations' et créez une nouvelle localisation (ex: 'France')."
echo "4. Allez dans 'Nodes' et créez un nouveau 'Node'."
echo "5. Dans l'onglet 'Configuration' du nouveau node, copiez le contenu du bloc de configuration."
echo "6. Collez ce contenu dans le fichier /etc/pterodactyl/config.yml sur votre serveur."
echo "7. Une fois le fichier sauvegardé, redémarrez Wings avec la commande : systemctl restart wings"
echo ""

log_success "--- Informations de connexion ---"
echo -e "URL du Panel:      ${COLOR_YELLOW}https://$FQDN${COLOR_RESET}"
echo -e "Email Admin:       ${COLOR_YELLOW}$EMAIL${COLOR_RESET}"
echo -e "Utilisateur Admin: ${COLOR_YELLOW}admin${COLOR_RESET}"
echo -e "Mot de passe Admin:${COLOR_RED} $ADMIN_PASSWORD${COLOR_RESET}"
echo ""
log_success "--- Identifiants Base de Données (pour référence) ---"
echo -e "Utilisateur DB:    ${COLOR_YELLOW}pterodactyl${COLOR_RESET}"
echo -e "Mot de passe DB:   ${COLOR_RED}$DB_PASSWORD${COLOR_RESET}"
echo -e "Mot de passe root MariaDB: ${COLOR_RED}$MYSQL_ROOT_PASSWORD${COLOR_RESET}"
echo ""
log_success "--- Commandes utiles ---"
echo -e "Redémarrer le Panel (queue worker): ${COLOR_YELLOW}systemctl restart pteroq${COLOR_RESET}"
echo -e "Redémarrer Nginx:                 ${COLOR_YELLOW}systemctl restart nginx${COLOR_RESET}"
echo -e "Redémarrer Wings:                 ${COLOR_YELLOW}systemctl restart wings${COLOR_RESET}"
echo ""
log_success "Installation terminée !"
log_success "Script Created By syxezyou"
log_success "Script Created By syxezyou"
