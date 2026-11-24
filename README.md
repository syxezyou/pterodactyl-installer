# Installateur Pterodactyl Panel & Wings

Script d’installation automatique pour **Pterodactyl Panel** et **Wings** sur Debian 12 (Bookworm) ou supérieur.

**Auteur :** SYX  
**Version :** 1.0

---

## Description

Ce script installe et configure de manière automatisée :

- Pterodactyl Panel (dernière version stable)
- Pterodactyl Wings
- Nginx + certificat SSL Let’s Encrypt (via Certbot)
- MariaDB 10.11
- Redis
- PHP 8.2 + Composer
- Node.js 20
- Docker (requis par Wings)
- Pare-feu UFW

L’installation est interactive uniquement pour le nom de domaine et l’adresse e-mail. Tous les mots de passe (administrateur, base de données, root MariaDB) sont générés aléatoirement et affichés à la fin du script.

---

## Prérequis

- Distribution : **Debian 12 (Bookworm)** ou version supérieure
- Accès **root** (ou sudo)
- Un nom de domaine (ou sous-domaine) pointant déjà vers l’adresse IP du serveur (requis pour le certificat SSL)
- Ports ouverts : 22 (SSH), 80 (HTTP), 443 (HTTPS), 8080 et 2022 (par défaut pour Wings / SFTP)

---

## Installation

Exécutez la commande suivante (remplacez l’URL par celle de votre fichier raw GitHub) :

```bash
curl -sL https://raw.githubusercontent.com/syxezyou/pterodactyl-installer/main/install.sh | sudo bash
```

Le script vous demandera :

1. Le nom de domaine du panel (exemple : `panel.votredomaine.com`)
2. Une adresse e-mail (utilisée pour le certificat Let’s Encrypt et le compte administrateur)

---

## Étapes post-installation (obligatoires)

Après l’exécution du script, une configuration manuelle de Wings est nécessaire :

1. Connectez-vous au panel à l’adresse `https://votre-domaine`
2. Allez dans **Admin** → **Locations** et créez une localisation
3. Allez dans **Admin** → **Nodes** et créez un nouveau Node
4. Dans l’onglet **Configuration** du Node, copiez le bloc de configuration YAML
5. Sur le serveur, créez/éditez le fichier :
   ```bash
   nano /etc/pterodactyl/config.yml
   ```
6. Collez la configuration et sauvegardez
7. Redémarrez Wings :
   ```bash
   systemctl restart wings
   ```

---

## Informations affichées à la fin de l’installation

Le script affiche :

- URL du panel
- Identifiants administrateur (email, username `admin`, mot de passe généré)
- Identifiants de la base de données
- Mot de passe root MariaDB

**Conservez ces informations en lieu sûr.** Les mots de passe ne sont pas stockés ailleurs.

---

## Services installés

| Service       | Description                     | Commande de redémarrage          |
|---------------|---------------------------------|----------------------------------|
| `pteroq`      | Queue worker du panel           | `systemctl restart pteroq`      |
| `nginx`       | Serveur web                     | `systemctl restart nginx`       |
| `wings`       | Daemon Wings                    | `systemctl restart wings`       |
| `mariadb`     | Base de données                 | `systemctl restart mariadb`     |
| `redis-server`| Cache / sessions / queues       | `systemctl restart redis-server`|
| `docker`      | Conteneurs des serveurs de jeu  | `systemctl restart docker`      |

---

## Avertissements

- Ce script est destiné à une installation sur un serveur dédié ou VPS propre.
- Les mots de passe sont générés aléatoirement et affichés uniquement dans la console. Notez-les immédiatement.
- Le certificat SSL est généré automatiquement via Certbot. Assurez-vous que le domaine pointe bien vers le serveur avant de lancer le script.
- Une étape manuelle reste nécessaire pour configurer le Node Wings (voir section ci-dessus).

---

## Licence

Ce script est fourni tel quel, sans garantie. Utilisez-le à vos propres risques.

**Script créé par SYX**

---

## Auteur et maintenance

**Développé par SYX** — [GitHub @syxezyou](https://github.com/syxezyou).

Pour signaler un problème, indiquez la version utilisée, les étapes de reproduction et les messages d’erreur pertinents. Ne publiez jamais de clés privées, de mots de passe ou de jetons.
