# Vaultwarden Installer

Installation automatisée de **Vaultwarden** (gestionnaire de mots de passe self-hosted compatible Bitwarden) sur Debian 13 via Docker.

## Présentation

Vaultwarden est une implémentation alternative du serveur Bitwarden, écrite en Rust. Elle est :
- **Légère** : consomme beaucoup moins de ressources que Bitwarden officiel
- **Compatible** : fonctionne avec tous les clients Bitwarden (web, mobile, desktop, extensions navigateur)
- **Complète** : support de toutes les fonctionnalités premium gratuitement (2FA, partage, collections, etc.)
- **Sécurisée** : chiffrement end-to-end, backup automatique

## Caractéristiques

- **Installation via Docker Compose** avec volumes persistants
- **HTTPS obligatoire** pour l'accès web (reverse proxy recommandé)
- **Base de données SQLite** (par défaut) avec backup automatique
- **Configuration SMTP** optionnelle pour notifications email
- **Support 2FA** (TOTP, Duo, YubiKey, WebAuthn)
- **Service systemd** pour démarrage automatique
- **Arguments CLI** ou variables d'environnement pour configuration
- **Déploiement Ansible** disponible

## Méthodes d'installation

### Méthode 1 : Installation rapide (recommandée)

```bash
curl -fsSL https://raw.githubusercontent.com/tiagomatiastm-prog/vaultwarden-installer/main/install-vaultwarden.sh | sudo bash -s -- \
  --domain vault.example.com \
  --email admin@example.com \
  --reverse-proxy \
  --smtp-host smtp.gmail.com \
  --smtp-port 587 \
  --smtp-from vault@example.com \
  --smtp-user vault@example.com
```

### Méthode 2 : Installation avec variables d'environnement

```bash
curl -fsSL https://raw.githubusercontent.com/tiagomatiastm-prog/vaultwarden-installer/main/install-vaultwarden.sh -o install-vaultwarden.sh
chmod +x install-vaultwarden.sh
sudo DOMAIN_NAME=vault.example.com ADMIN_EMAIL=admin@example.com BEHIND_REVERSE_PROXY=true ./install-vaultwarden.sh
```

### Méthode 3 : Installation manuelle

```bash
git clone https://github.com/tiagomatiastm-prog/vaultwarden-installer.git
cd vaultwarden-installer
sudo ./install-vaultwarden.sh --domain vault.example.com --email admin@example.com --reverse-proxy
```

## Options disponibles

| Option | Variable d'env | Description | Défaut |
|--------|---------------|-------------|---------|
| `--domain` | `DOMAIN_NAME` | Nom de domaine pour Vaultwarden | `vault.local` |
| `--email` | `ADMIN_EMAIL` | Email de l'administrateur | `admin@localhost` |
| `--reverse-proxy` | `BEHIND_REVERSE_PROXY=true` | Mode reverse proxy (écoute sur 127.0.0.1) | `false` (0.0.0.0) |
| `--bind-address` | `BIND_ADDRESS` | Adresse IP d'écoute | `0.0.0.0` ou `127.0.0.1` |
| `--port` | `VAULTWARDEN_PORT` | Port d'écoute | `8080` |
| `--smtp-host` | `SMTP_HOST` | Serveur SMTP | Désactivé |
| `--smtp-port` | `SMTP_PORT` | Port SMTP | `587` |
| `--smtp-from` | `SMTP_FROM` | Email expéditeur | - |
| `--smtp-user` | `SMTP_USER` | Utilisateur SMTP | - |
| `--smtp-ssl` | `SMTP_SSL=true` | Activer SSL explicite | `true` |
| `--admin-token` | - | Générer un token d'administration | Désactivé |

**Ordre de priorité** : Arguments CLI > Variables d'environnement > Valeurs par défaut

## Configuration post-installation

### 1. Accès à l'interface web

- **Sans reverse proxy** : `http://IP_SERVEUR:8080`
- **Avec reverse proxy** : `https://vault.example.com` (nécessite configuration Nginx/Caddy)

### 2. Configuration HTTPS (obligatoire pour clients web)

Voir [REVERSE_PROXY.md](REVERSE_PROXY.md) pour configurer Nginx, Caddy ou Traefik avec Let's Encrypt.

### 3. Créer le premier compte

- Aller sur `https://vault.example.com` ou `http://IP:8080`
- Cliquer sur "Créer un compte"
- **Important** : Le premier compte créé devient administrateur de l'organisation

### 4. Panel d'administration (optionnel)

Si `--admin-token` est utilisé, accéder au panel admin :
```
https://vault.example.com/admin
```

### 5. Configuration SMTP (notifications)

Si configuré, Vaultwarden peut envoyer :
- Emails de vérification
- Invitations d'organisation
- Notifications 2FA
- Alertes de sécurité

## Gestion du service

```bash
# Statut
sudo systemctl status vaultwarden

# Démarrer
sudo systemctl start vaultwarden

# Arrêter
sudo systemctl stop vaultwarden

# Redémarrer
sudo systemctl restart vaultwarden

# Logs Docker
sudo docker logs vaultwarden

# Logs en temps réel
sudo docker logs -f vaultwarden
```

## Backup et restauration

### Backup manuel

```bash
# Arrêter le service
sudo systemctl stop vaultwarden

# Backup du dossier data
sudo tar -czf vaultwarden-backup-$(date +%Y%m%d).tar.gz /opt/vaultwarden/data

# Redémarrer le service
sudo systemctl start vaultwarden
```

### Restauration

```bash
# Arrêter le service
sudo systemctl stop vaultwarden

# Restaurer les données
sudo tar -xzf vaultwarden-backup-YYYYMMDD.tar.gz -C /

# Redémarrer le service
sudo systemctl start vaultwarden
```

## Fichiers importants

- `/opt/vaultwarden/docker-compose.yml` - Configuration Docker
- `/opt/vaultwarden/data/` - Base de données et fichiers
- `/etc/systemd/system/vaultwarden.service` - Service systemd
- `/root/vaultwarden-info.txt` - Informations de connexion
- `/var/log/vaultwarden-install.log` - Log d'installation

## Sécurité

- **HTTPS obligatoire** : Les clients Bitwarden nécessitent HTTPS
- **Firewall** : Ouvrir uniquement le port du reverse proxy (80/443)
- **Backup régulier** : Sauvegarder `/opt/vaultwarden/data`
- **Mot de passe fort** : Utiliser un mot de passe maître robuste
- **2FA activé** : Activer l'authentification à deux facteurs
- **Admin token** : Protéger l'accès au panel admin

## Mise à jour

```bash
cd /opt/vaultwarden
sudo docker-compose pull
sudo systemctl restart vaultwarden
```

## Désinstallation

```bash
# Arrêter et supprimer le service
sudo systemctl stop vaultwarden
sudo systemctl disable vaultwarden
sudo rm /etc/systemd/system/vaultwarden.service
sudo systemctl daemon-reload

# Supprimer Docker et les données
sudo docker-compose -f /opt/vaultwarden/docker-compose.yml down -v
sudo rm -rf /opt/vaultwarden

# Supprimer les fichiers d'informations
sudo rm /root/vaultwarden-info.txt
```

## Déploiement Ansible

Voir [DEPLOYMENT.md](DEPLOYMENT.md) pour le déploiement automatisé via Ansible.

## Support

- **Documentation officielle** : https://github.com/dani-garcia/vaultwarden/wiki
- **Clients Bitwarden** : https://bitwarden.com/download/
- **Forum** : https://github.com/dani-garcia/vaultwarden/discussions

## License

Ce projet d'installation est fourni sous licence MIT. Vaultwarden est sous licence GPL-3.0.
