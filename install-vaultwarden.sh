#!/bin/bash

#######################################################
# Script d'installation de Vaultwarden sur Debian 13
# Auteur: Tiago Matias
# Date: 2025-11-01
#######################################################

set -euo pipefail

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

LOGFILE="/var/log/vaultwarden-install.log"

# Fonction d'affichage
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOGFILE"
}

error() {
    echo -e "${RED}[ERREUR]${NC} $1" | tee -a "$LOGFILE" >&2
}

warning() {
    echo -e "${YELLOW}[ATTENTION]${NC} $1" | tee -a "$LOGFILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOGFILE"
}

# Fonction d'aide
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Installation automatisée de Vaultwarden (gestionnaire de mots de passe self-hosted)

OPTIONS:
    --domain DOMAIN          Nom de domaine pour Vaultwarden (défaut: vault.local)
    --email EMAIL            Email de l'administrateur (défaut: admin@localhost)
    --reverse-proxy          Activer le mode reverse proxy (écoute sur 127.0.0.1:PORT)
    --bind-address IP        Adresse IP d'écoute (défaut: 0.0.0.0 ou 127.0.0.1 si --reverse-proxy)
    --port PORT              Port d'écoute (défaut: 8080)
    --smtp-host HOST         Serveur SMTP pour notifications email
    --smtp-port PORT         Port SMTP (défaut: 587)
    --smtp-from EMAIL        Email expéditeur pour SMTP
    --smtp-user USER         Utilisateur SMTP
    --smtp-pass PASS         Mot de passe SMTP
    --smtp-ssl               Activer SSL explicite pour SMTP (défaut: true)
    --admin-token            Générer un token pour le panel d'administration
    -h, --help               Afficher cette aide

EXEMPLES:
    # Installation basique
    $0 --domain vault.example.com --email admin@example.com

    # Installation avec reverse proxy (Nginx/Caddy)
    $0 --domain vault.example.com --email admin@example.com --reverse-proxy

    # Installation complète avec SMTP
    $0 \\
      --domain vault.example.com \\
      --email admin@example.com \\
      --reverse-proxy \\
      --smtp-host smtp.gmail.com \\
      --smtp-port 587 \\
      --smtp-from vault@example.com \\
      --smtp-user vault@example.com \\
      --admin-token

VARIABLES D'ENVIRONNEMENT:
    DOMAIN_NAME              Équivalent à --domain
    ADMIN_EMAIL              Équivalent à --email
    BEHIND_REVERSE_PROXY     Équivalent à --reverse-proxy (true/false)
    BIND_ADDRESS             Équivalent à --bind-address
    VAULTWARDEN_PORT         Équivalent à --port
    SMTP_HOST                Équivalent à --smtp-host
    SMTP_PORT                Équivalent à --smtp-port
    SMTP_FROM                Équivalent à --smtp-from
    SMTP_USER                Équivalent à --smtp-user
    SMTP_PASSWORD            Équivalent à --smtp-pass
    SMTP_SSL                 Équivalent à --smtp-ssl (true/false)

Ordre de priorité: Arguments CLI > Variables d'env > Valeurs par défaut

EOF
}

# Valeurs par défaut
DOMAIN_NAME="${DOMAIN_NAME:-vault.local}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@localhost}"
BEHIND_REVERSE_PROXY="${BEHIND_REVERSE_PROXY:-false}"
BIND_ADDRESS="${BIND_ADDRESS:-}"
VAULTWARDEN_PORT="${VAULTWARDEN_PORT:-8080}"
SMTP_HOST="${SMTP_HOST:-}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_FROM="${SMTP_FROM:-}"
SMTP_USER="${SMTP_USER:-}"
SMTP_PASSWORD="${SMTP_PASSWORD:-}"
SMTP_SSL="${SMTP_SSL:-true}"
GENERATE_ADMIN_TOKEN="false"

# Parser les arguments CLI
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)
            DOMAIN_NAME="$2"
            shift 2
            ;;
        --email)
            ADMIN_EMAIL="$2"
            shift 2
            ;;
        --reverse-proxy)
            BEHIND_REVERSE_PROXY="true"
            shift
            ;;
        --bind-address)
            BIND_ADDRESS="$2"
            shift 2
            ;;
        --port)
            VAULTWARDEN_PORT="$2"
            shift 2
            ;;
        --smtp-host)
            SMTP_HOST="$2"
            shift 2
            ;;
        --smtp-port)
            SMTP_PORT="$2"
            shift 2
            ;;
        --smtp-from)
            SMTP_FROM="$2"
            shift 2
            ;;
        --smtp-user)
            SMTP_USER="$2"
            shift 2
            ;;
        --smtp-pass)
            SMTP_PASSWORD="$2"
            shift 2
            ;;
        --smtp-ssl)
            SMTP_SSL="true"
            shift
            ;;
        --admin-token)
            GENERATE_ADMIN_TOKEN="true"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Option inconnue: $1"
            show_help
            exit 1
            ;;
    esac
done

# Déterminer l'adresse de bind si non spécifiée
if [ -z "$BIND_ADDRESS" ]; then
    if [ "$BEHIND_REVERSE_PROXY" = "true" ]; then
        BIND_ADDRESS="127.0.0.1"
    else
        BIND_ADDRESS="0.0.0.0"
    fi
fi

# Vérification root
if [ "$EUID" -ne 0 ]; then
    error "Ce script doit être exécuté en tant que root"
    exit 1
fi

log "============================================"
log "  Installation de Vaultwarden"
log "============================================"
info "Domaine: $DOMAIN_NAME"
info "Email: $ADMIN_EMAIL"
info "Reverse proxy: $BEHIND_REVERSE_PROXY"
info "Bind address: $BIND_ADDRESS"
info "Port: $VAULTWARDEN_PORT"
if [ -n "$SMTP_HOST" ]; then
    info "SMTP: $SMTP_HOST:$SMTP_PORT"
fi
log ""

# Mise à jour du système
log "Mise à jour du système..."
apt-get update >> "$LOGFILE" 2>&1
apt-get install -y curl ca-certificates gnupg lsb-release >> "$LOGFILE" 2>&1

# Installation de Docker
if ! command -v docker &> /dev/null; then
    log "Installation de Docker..."

    # Ajouter la clé GPG officielle de Docker
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    # Ajouter le dépôt Docker
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update >> "$LOGFILE" 2>&1
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >> "$LOGFILE" 2>&1

    systemctl enable docker >> "$LOGFILE" 2>&1
    systemctl start docker >> "$LOGFILE" 2>&1

    log "Docker installé avec succès"
else
    info "Docker est déjà installé"
fi

# Vérifier que Docker fonctionne
if ! docker info > /dev/null 2>&1; then
    error "Docker n'est pas correctement installé ou démarré"
    exit 1
fi

# Créer le répertoire de travail
log "Création de la structure de fichiers..."
INSTALL_DIR="/opt/vaultwarden"
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/data"

# Générer le token admin si demandé
ADMIN_TOKEN=""
if [ "$GENERATE_ADMIN_TOKEN" = "true" ]; then
    log "Génération du token d'administration..."
    # Utiliser Docker pour générer un hash Argon2
    ADMIN_TOKEN=$(openssl rand -base64 48)
    info "Token admin généré (voir /root/vaultwarden-info.txt)"
fi

# Créer le fichier docker-compose.yml
log "Création du fichier docker-compose.yml..."
cat > "$INSTALL_DIR/docker-compose.yml" << EOF
version: '3'

services:
  vaultwarden:
    container_name: vaultwarden
    image: vaultwarden/server:latest
    restart: unless-stopped
    ports:
      - "${BIND_ADDRESS}:${VAULTWARDEN_PORT}:80"
    volumes:
      - ./data:/data
    environment:
      - DOMAIN=https://${DOMAIN_NAME}
      - SIGNUPS_ALLOWED=true
      - INVITATIONS_ALLOWED=true
      - WEBSOCKET_ENABLED=true
      - WEB_VAULT_ENABLED=true
      - LOG_FILE=/data/vaultwarden.log
      - LOG_LEVEL=info
      - EXTENDED_LOGGING=true
EOF

# Ajouter la configuration SMTP si fournie
if [ -n "$SMTP_HOST" ]; then
    cat >> "$INSTALL_DIR/docker-compose.yml" << EOF
      - SMTP_HOST=${SMTP_HOST}
      - SMTP_FROM=${SMTP_FROM}
      - SMTP_PORT=${SMTP_PORT}
      - SMTP_SECURITY=starttls
      - SMTP_USERNAME=${SMTP_USER}
      - SMTP_PASSWORD=${SMTP_PASSWORD}
EOF
    if [ "$SMTP_SSL" = "true" ]; then
        echo "      - SMTP_EXPLICIT_TLS=true" >> "$INSTALL_DIR/docker-compose.yml"
    fi
fi

# Ajouter le token admin si généré
if [ -n "$ADMIN_TOKEN" ]; then
    echo "      - ADMIN_TOKEN=${ADMIN_TOKEN}" >> "$INSTALL_DIR/docker-compose.yml"
fi

# Créer le service systemd
log "Création du service systemd..."
cat > /etc/systemd/system/vaultwarden.service << EOF
[Unit]
Description=Vaultwarden (Bitwarden-compatible password manager)
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

# Recharger systemd
systemctl daemon-reload

# Démarrer Vaultwarden
log "Démarrage de Vaultwarden..."
cd "$INSTALL_DIR"
systemctl enable vaultwarden >> "$LOGFILE" 2>&1
systemctl start vaultwarden >> "$LOGFILE" 2>&1

# Attendre que le container démarre
log "Attente du démarrage du container..."
for i in {1..30}; do
    if docker ps | grep -q vaultwarden; then
        break
    fi
    sleep 1
done

# Vérifier que le service est actif
sleep 3
if systemctl is-active --quiet vaultwarden; then
    log "Service Vaultwarden démarré avec succès"
else
    error "Le service Vaultwarden n'a pas démarré correctement"
    systemctl status vaultwarden
    exit 1
fi

# Tester l'accès à l'API
log "Vérification de l'accès à l'API..."
for i in {1..15}; do
    if curl -sf "http://${BIND_ADDRESS}:${VAULTWARDEN_PORT}" > /dev/null 2>&1; then
        log "API Vaultwarden accessible"
        break
    fi
    if [ $i -eq 15 ]; then
        warning "L'API Vaultwarden n'est pas encore accessible (cela peut être normal au premier démarrage)"
    fi
    sleep 2
done

# Créer le fichier d'informations
log "Création du fichier d'informations..."
INFO_FILE="/root/vaultwarden-info.txt"
cat > "$INFO_FILE" << EOF
================================================================================
                      VAULTWARDEN - INFORMATIONS D'INSTALLATION
================================================================================

Date d'installation : $(date)
Hostname : $(hostname -f)
Adresse IP : $(hostname -I | awk '{print $1}')

CONFIGURATION
=============

Domaine : ${DOMAIN_NAME}
Email administrateur : ${ADMIN_EMAIL}
Mode reverse proxy : ${BEHIND_REVERSE_PROXY}
Adresse d'écoute : ${BIND_ADDRESS}:${VAULTWARDEN_PORT}

ACCÈS WEB
=========

EOF

if [ "$BEHIND_REVERSE_PROXY" = "true" ]; then
    cat >> "$INFO_FILE" << EOF
URL d'accès : https://${DOMAIN_NAME}
(Nécessite la configuration d'un reverse proxy Nginx/Caddy/Traefik)

Backend local : http://${BIND_ADDRESS}:${VAULTWARDEN_PORT}

EOF
else
    cat >> "$INFO_FILE" << EOF
URL d'accès : http://$(hostname -I | awk '{print $1}'):${VAULTWARDEN_PORT}

ATTENTION : HTTPS est OBLIGATOIRE pour utiliser les clients Bitwarden.
Configurez un reverse proxy avec Let's Encrypt (voir REVERSE_PROXY.md)

EOF
fi

cat >> "$INFO_FILE" << EOF
PREMIÈRE CONNEXION
==================

1. Accéder à l'interface web (URL ci-dessus)
2. Créer un compte (le premier compte créé est administrateur)
3. Activer la 2FA dans les paramètres du compte
4. Télécharger les clients Bitwarden : https://bitwarden.com/download/

EOF

if [ -n "$SMTP_HOST" ]; then
    cat >> "$INFO_FILE" << EOF
CONFIGURATION SMTP
==================

Serveur : ${SMTP_HOST}:${SMTP_PORT}
Expéditeur : ${SMTP_FROM}
Utilisateur : ${SMTP_USER}
SSL/TLS : ${SMTP_SSL}

EOF
fi

if [ -n "$ADMIN_TOKEN" ]; then
    cat >> "$INFO_FILE" << EOF
PANEL D'ADMINISTRATION
======================

URL : https://${DOMAIN_NAME}/admin
Token : ${ADMIN_TOKEN}

IMPORTANT : Conservez ce token en sécurité !

EOF
fi

cat >> "$INFO_FILE" << EOF
GESTION DU SERVICE
==================

Statut : systemctl status vaultwarden
Démarrer : systemctl start vaultwarden
Arrêter : systemctl stop vaultwarden
Redémarrer : systemctl restart vaultwarden
Logs Docker : docker logs vaultwarden
Logs en temps réel : docker logs -f vaultwarden

FICHIERS IMPORTANTS
===================

Configuration : ${INSTALL_DIR}/docker-compose.yml
Données : ${INSTALL_DIR}/data/
Service systemd : /etc/systemd/system/vaultwarden.service
Logs d'installation : ${LOGFILE}

BACKUP
======

Arrêter : systemctl stop vaultwarden
Backup : tar -czf vaultwarden-backup-\$(date +%Y%m%d).tar.gz ${INSTALL_DIR}/data
Démarrer : systemctl start vaultwarden

MISE À JOUR
===========

cd ${INSTALL_DIR}
docker compose pull
systemctl restart vaultwarden

SÉCURITÉ
========

- HTTPS OBLIGATOIRE pour les clients Bitwarden
- Activer la 2FA sur tous les comptes
- Sauvegarder régulièrement ${INSTALL_DIR}/data
- Utiliser un mot de passe maître fort et unique
- Configurer le firewall (autoriser uniquement 80/443 si reverse proxy)

RESSOURCES
==========

Documentation : https://github.com/dani-garcia/vaultwarden/wiki
Clients Bitwarden : https://bitwarden.com/download/
Support : https://github.com/dani-garcia/vaultwarden/discussions

================================================================================
EOF

chmod 600 "$INFO_FILE"

log ""
log "============================================"
log "  Installation terminée avec succès !"
log "============================================"
log ""
info "Fichier d'informations : $INFO_FILE"
log ""

if [ "$BEHIND_REVERSE_PROXY" = "true" ]; then
    info "Vaultwarden écoute sur http://${BIND_ADDRESS}:${VAULTWARDEN_PORT}"
    warning "Configurez votre reverse proxy pour exposer https://${DOMAIN_NAME}"
    info "Voir REVERSE_PROXY.md pour des exemples de configuration"
else
    info "Accès web : http://$(hostname -I | awk '{print $1}'):${VAULTWARDEN_PORT}"
    warning "HTTPS est OBLIGATOIRE pour les clients Bitwarden !"
    warning "Configurez un reverse proxy avec Let's Encrypt"
fi

log ""
log "Prochaines étapes :"
log "1. Configurer le reverse proxy avec HTTPS (obligatoire)"
log "2. Accéder à l'interface web"
log "3. Créer le premier compte administrateur"
log "4. Activer la 2FA"
log "5. Installer les clients Bitwarden sur vos appareils"
log ""

cat "$INFO_FILE"

exit 0
