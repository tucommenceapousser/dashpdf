# dashpdf

in use with https://github.com/tucommenceapousser/malicious-pdf

# Generer les pdf infectés

📌 Exemple d’utilisation

```bash
chmod +x genpdf.sh
./genpdf.sh 127.0.0.1 4545
```

Cela va :

générer les PDF avec http://127.0.0.1:4545 comme callback

déposer test1.pdf … test11.pdf directement dans ./dashpdf/

Exécution recommandée — rapide

1. Déposer listener.py et dashboard.py sur ton VPS (même dossier).


2. Exporter Token/Chat (si tu veux les notifications) :


```bash
export TELEGRAM_TOKEN="TON_TOKEN_ICI"
export TELEGRAM_CHAT_ID="TON_CHAT_ID_ICI"
```

3. Lancer le listener :


```bash
python3 listener.py --port 4545
```

ou si tu préfères passer en CLI :

```bash
python3 listener.py --port 4545 --tg-token "TON_TOKEN" --tg-chat "TON_CHAT_ID"
```

4. Lancer le dashboard :


```bash
python3 dashboard.py
```

### ouvrir http://<IP_VPS>:8080
### login: mot de passe = Trh@ckn0n

# SSL is optionnal :

# Générer un certificat auto-signé (rapide — pour tests)

Génère une clé RSA 4096 et un certificat auto-signé valide 1 an (remplace your.vps.domain si tu veux un CN spécifique) :

## dans /etc/ssl/private ou ton dossier de travail

```bash
mkdir -p ~/ssl && cd ~/ssl
```

### clé RSA 4096 sans passphrase (pratique pour services automatisés)

```bash
openssl genpkey -algorithm RSA -out key.pem -pkeyopt rsa_keygen_bits:4096
```
# certificat auto signé (CN = your.vps.domain)

```bash
openssl req -new -x509 -key key.pem -out cert.pem -days 365 \
  -subj "/C=FR/ST=IDF/L=Paris/O=MyLab/CN=your.vps.domain"
```

### Donne les fichiers key.pem (privée) et cert.pem (certificat public).

Protéger la clé :

```bash
chmod 600 key.pem
```


# Si tu veux un certificat public (Let's Encrypt)

> Nécessite : un nom de domaine pointant sur ton VPS (A/AAAA) et ports 80/443 accessibles.



# Installer certbot :

```bash
sudo apt update
sudo apt install certbot -y
```

## Obtenir un cert (mode standalone — arrêtera tout service sur le port 80 le temps du challenge) :

### Arrête / arrange ton listener si il écoute le port 80 (ou utilise nginx)

```bash
sudo systemctl stop listener.service  # si tu as mis en service, sinon arrête le processus
```

```bash
sudo certbot certonly --standalone -d your.vps.domain --agree-tos -m ton.email@example.com --non-interactive
```

Les fichiers seront dans /etc/letsencrypt/live/your.vps.domain/ :

```bash
/etc/letsencrypt/live/your.vps.domain/fullchain.pem (certificat)
```

```bash
/etc/letsencrypt/live/your.vps.domain/privkey.pem (clé privée)
```


## Configurer listener.py pour utiliser TLS

### Exemple de lancement du script avec tes fichiers :

### si auto-signé dans ~/ssl

```bash
python3 listener.py --port 4545 --ssl --cert ~/ssl/cert.pem --key ~/ssl/key.pem
```

# si Let's Encrypt

```bash
python3 listener.py --port 4545 --ssl --cert /etc/letsencrypt/live/your.vps.domain/fullchain.pem --key /etc/letsencrypt/live/your.vps.domain/privkey.pem
```
