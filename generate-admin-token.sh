#!/bin/bash

#######################################################
# Script pour générer et activer le token admin Vaultwarden
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

INSTALL_DIR="/opt/vaultwarden"
DOCKER_COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
INFO_FILE="/root/vaultwarden-info.txt"

# Fonction d'affichage
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo -e "${RED}[ERREUR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[ATTENTION]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Vérification root
if [ "$EUID" -ne 0 ]; then
    error "Ce script doit être exécuté en tant que root"
    exit 1
fi

# Vérifier que Vaultwarden est installé
if [ ! -d "$INSTALL_DIR" ] || [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
    error "Vaultwarden n'est pas installé dans $INSTALL_DIR"
    error "Veuillez d'abord installer Vaultwarden avec install-vaultwarden.sh"
    exit 1
fi

log "============================================"
log "  Génération du token admin Vaultwarden"
log "============================================"
echo ""

# Vérifier si un token existe déjà
if grep -q "ADMIN_TOKEN=" "$DOCKER_COMPOSE_FILE"; then
    warning "Un token admin existe déjà !"
    echo ""
    read -p "Voulez-vous le remplacer ? (o/N) : " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[OoYy]$ ]]; then
        info "Opération annulée"
        exit 0
    fi
fi

# Générer un nouveau token sécurisé (48 bytes en base64)
log "Génération d'un nouveau token sécurisé..."
ADMIN_TOKEN=$(openssl rand -base64 48)

# Récupérer le domaine depuis docker-compose.yml
DOMAIN=$(grep "DOMAIN=" "$DOCKER_COMPOSE_FILE" | head -1 | cut -d'=' -f2 | sed 's/https\?:\/\///')

# Sauvegarder le docker-compose.yml original
cp "$DOCKER_COMPOSE_FILE" "$DOCKER_COMPOSE_FILE.bak"
log "Backup créé : $DOCKER_COMPOSE_FILE.bak"

# Supprimer l'ancien token s'il existe
sed -i '/ADMIN_TOKEN=/d' "$DOCKER_COMPOSE_FILE"

# Ajouter le nouveau token avant la fin de la section environment
# Trouver la dernière ligne de environment et ajouter avant
awk -v token="      - ADMIN_TOKEN=$ADMIN_TOKEN" '
/^    environment:/ { in_env=1 }
in_env && /^[^ ]/ {
    print token
    in_env=0
}
in_env && /^    [a-z]/ {
    print token
    in_env=0
}
{ print }
' "$DOCKER_COMPOSE_FILE" > "$DOCKER_COMPOSE_FILE.tmp"

# Si le token n'a pas été ajouté (cas où environment est la dernière section)
if ! grep -q "ADMIN_TOKEN=" "$DOCKER_COMPOSE_FILE.tmp"; then
    # Ajouter à la fin de la section environment
    awk -v token="      - ADMIN_TOKEN=$ADMIN_TOKEN" '
    /^    environment:/ { in_env=1 }
    in_env && /^      - / { last_env=NR }
    {
        print
        if (NR == last_env && in_env) {
            print token
            in_env=0
        }
    }
    END {
        if (in_env) print token
    }
    ' "$DOCKER_COMPOSE_FILE.bak" > "$DOCKER_COMPOSE_FILE.tmp"
fi

mv "$DOCKER_COMPOSE_FILE.tmp" "$DOCKER_COMPOSE_FILE"

log "Token admin ajouté au fichier de configuration"

# Redémarrer le service
log "Redémarrage de Vaultwarden..."
cd "$INSTALL_DIR"
systemctl restart vaultwarden

# Attendre que le service redémarre
sleep 5

# Vérifier que le service est actif
if systemctl is-active --quiet vaultwarden; then
    log "Service Vaultwarden redémarré avec succès"
else
    error "Échec du redémarrage du service"
    error "Restauration du fichier de configuration..."
    mv "$DOCKER_COMPOSE_FILE.bak" "$DOCKER_COMPOSE_FILE"
    systemctl restart vaultwarden
    exit 1
fi

# Créer/Mettre à jour le fichier d'informations
log "Mise à jour du fichier d'informations..."

# Ajouter ou mettre à jour la section admin token
if [ -f "$INFO_FILE" ]; then
    # Supprimer l'ancienne section admin si elle existe
    sed -i '/^PANEL D'"'"'ADMINISTRATION$/,/^$/d' "$INFO_FILE"

    # Ajouter la nouvelle section avant "GESTION DU SERVICE"
    awk -v token="$ADMIN_TOKEN" -v domain="$DOMAIN" '
    /^GESTION DU SERVICE$/ {
        print "PANEL D'"'"'ADMINISTRATION"
        print "======================"
        print ""
        print "URL : https://" domain "/admin"
        print "Token : " token
        print ""
        print "IMPORTANT : Conservez ce token en sécurité !"
        print ""
    }
    { print }
    ' "$INFO_FILE" > "$INFO_FILE.tmp"
    mv "$INFO_FILE.tmp" "$INFO_FILE"
else
    warning "Fichier d'informations $INFO_FILE non trouvé"
fi

echo ""
log "============================================"
log "  Token admin généré avec succès !"
log "============================================"
echo ""

info "URL du panel admin : https://$DOMAIN/admin"
echo ""
echo -e "${GREEN}Token admin :${NC}"
echo -e "${YELLOW}$ADMIN_TOKEN${NC}"
echo ""
warning "IMPORTANT : Conservez ce token en lieu sûr !"
warning "Il permet l'accès complet à l'administration de Vaultwarden"
echo ""
info "Le token a été sauvegardé dans : $INFO_FILE"
info "Backup de la configuration : $DOCKER_COMPOSE_FILE.bak"
echo ""
log "Pour accéder au panel admin :"
log "1. Aller sur https://$DOMAIN/admin"
log "2. Entrer le token ci-dessus"
log "3. Vous pouvez désactiver l'enregistrement de nouveaux comptes"
log "4. Consulter les statistiques et gérer les utilisateurs"
echo ""

exit 0
