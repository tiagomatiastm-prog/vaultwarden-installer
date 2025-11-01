# Configuration Reverse Proxy pour Vaultwarden

**IMPORTANT** : Les clients Bitwarden (web, mobile, desktop, extensions) **nécessitent HTTPS**. Un reverse proxy avec Let's Encrypt est donc **obligatoire** pour une utilisation réelle.

Ce guide couvre la configuration pour Nginx, Caddy, Traefik et HAProxy.

---

## Prérequis

- Nom de domaine pointant vers votre serveur (ex: `vault.example.com`)
- Port 80 et 443 ouverts dans le firewall
- Vaultwarden installé avec `--reverse-proxy` (écoute sur 127.0.0.1:8080)

---

## Option 1 : Nginx + Let's Encrypt (Recommandé)

### Installation

```bash
sudo apt update
sudo apt install -y nginx certbot python3-certbot-nginx
```

### Configuration

Créer `/etc/nginx/sites-available/vaultwarden` :

```nginx
# Redirection HTTP vers HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name vault.example.com;

    # Validation Let's Encrypt
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # Redirection tout le reste
    location / {
        return 301 https://$server_name$request_uri;
    }
}

# Configuration HTTPS
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name vault.example.com;

    # Certificats Let's Encrypt (seront ajoutés par certbot)
    ssl_certificate /etc/letsencrypt/live/vault.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/vault.example.com/privkey.pem;

    # Paramètres SSL modernes
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Headers de sécurité
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Logs
    access_log /var/log/nginx/vaultwarden-access.log;
    error_log /var/log/nginx/vaultwarden-error.log;

    # Taille maximale des uploads (pièces jointes)
    client_max_body_size 525M;

    # Proxy vers Vaultwarden
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
    }

    # Support WebSocket pour les notifications
    location /notifications/hub {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Support pour les pièces jointes volumineuses
    location /api/sends {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 525M;
    }
}
```

### Activation

```bash
# Créer le lien symbolique
sudo ln -s /etc/nginx/sites-available/vaultwarden /etc/nginx/sites-enabled/

# Tester la configuration
sudo nginx -t

# Obtenir le certificat Let's Encrypt
sudo certbot --nginx -d vault.example.com

# Redémarrer Nginx
sudo systemctl restart nginx

# Vérifier le statut
sudo systemctl status nginx
```

### Renouvellement automatique

Le renouvellement est automatique avec certbot. Vérifier :

```bash
sudo certbot renew --dry-run
```

---

## Option 2 : Caddy (Le plus simple)

Caddy gère automatiquement HTTPS et Let's Encrypt !

### Installation

```bash
sudo apt update
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install caddy
```

### Configuration

Éditer `/etc/caddy/Caddyfile` :

```caddy
vault.example.com {
    # HTTPS automatique avec Let's Encrypt

    # Headers de sécurité
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        X-XSS-Protection "1; mode=block"
    }

    # Proxy vers Vaultwarden
    reverse_proxy 127.0.0.1:8080 {
        # Support WebSocket
        header_up X-Real-IP {remote_host}
    }

    # Taille maximale des uploads
    request_body {
        max_size 525MB
    }
}
```

### Activation

```bash
# Redémarrer Caddy
sudo systemctl restart caddy

# Vérifier le statut
sudo systemctl status caddy

# Voir les logs
sudo journalctl -u caddy -f
```

**C'est tout !** Caddy obtient automatiquement le certificat Let's Encrypt.

---

## Option 3 : Traefik (Docker)

Parfait si vous utilisez déjà Traefik pour d'autres services.

### docker-compose.yml complet avec Traefik

```yaml
version: '3'

services:
  traefik:
    image: traefik:v3.0
    container_name: traefik
    restart: unless-stopped
    command:
      - --api.dashboard=true
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --certificatesresolvers.letsencrypt.acme.email=admin@example.com
      - --certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json
      - --certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./letsencrypt:/letsencrypt

  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: unless-stopped
    volumes:
      - ./vaultwarden-data:/data
    environment:
      - DOMAIN=https://vault.example.com
      - WEBSOCKET_ENABLED=true
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.vaultwarden.rule=Host(`vault.example.com`)"
      - "traefik.http.routers.vaultwarden.entrypoints=websecure"
      - "traefik.http.routers.vaultwarden.tls.certresolver=letsencrypt"
      - "traefik.http.services.vaultwarden.loadbalancer.server.port=80"
      # Redirection HTTP vers HTTPS
      - "traefik.http.middlewares.redirect-to-https.redirectscheme.scheme=https"
      - "traefik.http.routers.vaultwarden-http.rule=Host(`vault.example.com`)"
      - "traefik.http.routers.vaultwarden-http.entrypoints=web"
      - "traefik.http.routers.vaultwarden-http.middlewares=redirect-to-https"
```

---

## Option 4 : HAProxy

### Installation

```bash
sudo apt update
sudo apt install -y haproxy certbot
```

### Obtenir le certificat

```bash
# Arrêter HAProxy temporairement
sudo systemctl stop haproxy

# Obtenir le certificat
sudo certbot certonly --standalone -d vault.example.com

# Créer le certificat combiné pour HAProxy
sudo cat /etc/letsencrypt/live/vault.example.com/fullchain.pem \
         /etc/letsencrypt/live/vault.example.com/privkey.pem \
         | sudo tee /etc/haproxy/certs/vault.example.com.pem

# Permissions
sudo chmod 600 /etc/haproxy/certs/vault.example.com.pem
```

### Configuration

Éditer `/etc/haproxy/haproxy.cfg` :

```haproxy
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

    # Paramètres SSL modernes
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

defaults
    log global
    mode http
    option httplog
    option dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000

# Frontend HTTP (redirection vers HTTPS)
frontend http_front
    bind *:80
    redirect scheme https code 301 if !{ ssl_fc }

# Frontend HTTPS
frontend https_front
    bind *:443 ssl crt /etc/haproxy/certs/vault.example.com.pem

    # Headers de sécurité
    http-response set-header Strict-Transport-Security "max-age=31536000; includeSubDomains"
    http-response set-header X-Frame-Options "SAMEORIGIN"
    http-response set-header X-Content-Type-Options "nosniff"

    # Headers pour le backend
    http-request set-header X-Forwarded-Proto https
    http-request set-header X-Forwarded-Host %[req.hdr(host)]

    default_backend vaultwarden_backend

# Backend Vaultwarden
backend vaultwarden_backend
    balance roundrobin
    server vaultwarden1 127.0.0.1:8080 check
```

### Activation

```bash
# Tester la configuration
sudo haproxy -c -f /etc/haproxy/haproxy.cfg

# Redémarrer HAProxy
sudo systemctl restart haproxy

# Vérifier le statut
sudo systemctl status haproxy
```

### Renouvellement automatique

Créer `/etc/letsencrypt/renewal-hooks/deploy/haproxy-deploy.sh` :

```bash
#!/bin/bash
cat /etc/letsencrypt/live/vault.example.com/fullchain.pem \
    /etc/letsencrypt/live/vault.example.com/privkey.pem \
    > /etc/haproxy/certs/vault.example.com.pem
chmod 600 /etc/haproxy/certs/vault.example.com.pem
systemctl reload haproxy
```

```bash
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/haproxy-deploy.sh
```

---

## Vérification

### Test du certificat SSL

```bash
# Vérifier le certificat
openssl s_client -connect vault.example.com:443 -servername vault.example.com < /dev/null

# Test avec curl
curl -I https://vault.example.com
```

### Test de sécurité SSL

Tester sur : https://www.ssllabs.com/ssltest/analyze.html?d=vault.example.com

Objectif : **Note A ou A+**

### Vérifier les WebSockets

```bash
# Tester la connexion WebSocket
curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" \
     -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: test" \
     https://vault.example.com/notifications/hub
```

---

## Firewall

Ouvrir uniquement les ports nécessaires :

```bash
# UFW (Ubuntu/Debian)
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable

# Firewalld (RHEL/CentOS)
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload

# iptables
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
```

**Important** : Ne PAS ouvrir le port 8080 (Vaultwarden doit être accessible uniquement via le reverse proxy).

---

## Troubleshooting

### Erreur "HTTPS required"

- Vérifier que le domaine est accessible en HTTPS
- Vérifier la variable `DOMAIN=https://...` dans docker-compose.yml
- Vérifier les headers `X-Forwarded-Proto` dans la config du reverse proxy

### WebSocket ne fonctionne pas

- Vérifier la configuration WebSocket du reverse proxy
- Vérifier que `WEBSOCKET_ENABLED=true` dans docker-compose.yml
- Tester avec : `curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" ...`

### Certificat non valide

```bash
# Nginx
sudo certbot renew

# Caddy (automatique)
sudo systemctl restart caddy

# HAProxy
sudo certbot renew
sudo /etc/letsencrypt/renewal-hooks/deploy/haproxy-deploy.sh
```

### Logs

```bash
# Vaultwarden
docker logs vaultwarden

# Nginx
sudo tail -f /var/log/nginx/vaultwarden-error.log

# Caddy
sudo journalctl -u caddy -f

# Traefik
docker logs traefik

# HAProxy
sudo tail -f /var/log/haproxy.log
```

---

## Recommandations

1. **Caddy** : Le plus simple, HTTPS automatique, parfait pour débutants
2. **Nginx** : Le plus utilisé, très performant, documentation abondante
3. **Traefik** : Idéal si vous avez déjà une infrastructure Docker
4. **HAProxy** : Pour les infrastructures complexes avec load balancing

Pour Vaultwarden, **Caddy** est le choix le plus simple et recommandé !
