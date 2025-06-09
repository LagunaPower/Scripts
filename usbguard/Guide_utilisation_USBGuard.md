# Guide d'utilisation d'USBGuard

## Présentation

[USBGuard](https://usbguard.github.io/) est un outil permettant de contrôler les accès aux périphériques USB sur un système GNU/Linux via une politique de règles configurables.

---

## Lister les périphériques USB

Pour afficher tous les périphériques USB connus par USBGuard :

```bash
usbguard list-devices
```

Exemple de sortie :

```
1: allow id 1d6b:0002 ...
2: block id 0781:5567 ...
```

Chaque ligne affiche un ID unique, un état (`allow`, `block`, etc.), l’ID fournisseur:produit, et d’autres métadonnées.

---

## Ajouter un périphérique USB

1. Branchez la clé USB.
2. Listez les périphériques :

   ```bash
   usbguard list-devices
   ```

3. Autorisez temporairement le périphérique bloqué :

   ```bash
   usbguard allow-device <ID>
   ```
---

## Supprimer un périphérique USB

1. Éditez la configuration présente dans 

   * /etc/usbguard/rules.conf
   * /etc/usbguard/rules.d/monfichier.conf

2. Supprimez ou commentez la ligne correspondant au périphérique (identifiable via son ID, nom ou numéro de série).

3. Rechargez les règles :

   ```bash
   sudo systemctl reload usbguard
   ```

---

## Mode apprentissage

Pour générer une politique autorisant uniquement les périphériques actuellement connectés (utile en configuration initiale) :

```bash
usbguard generate-policy > /etc/usbguard/rules.conf
sudo systemctl restart usbguard
```

---

## Scripts de gestion
Les scripts `usbguard-add` et `usbguard-reset` permettent de gérer plus facilement USBGUARG et sont placés dans le répertoire `/usr/bin/`. Ces scripts sont automatiquement copiés si le master DPITM à été utilisé.

### usbguard-add : Autoriser automatiquement un périphérique bloqué

```bash
#!/bin/bash
# usbguard-add

# Ce script permet de lister les périphériques USB bloqués et d’en autoriser un
# en mettant à jour de manière persistante le fichier de règles utilisé par USBGuard,
# avec un commentaire incluant la date, l’ID et une justification obligatoire.

DEFAULT_RULES="/etc/usbguard/rules.conf"
CONFIG_FILE="/etc/usbguard/usbguard-daemon.conf"
AUTH_USB_FILE="usbguard_auth-usb.conf"

# Détection du fichier de règles depuis la conf principale
if [ -f "$CONFIG_FILE" ]; then
    RULES_PATH=$(awk -F '=' -v file="$AUTH_USB_FILE" '/^RuleFolder\s*=/{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2 "/" file}' "$CONFIG_FILE")
    RULES_PATH="${RULES_PATH:-$DEFAULT_RULES}"
else
    RULES_PATH="$DEFAULT_RULES"
fi

echo "[INFO] Périphériques USB actuellement bloqués :"
usbguard list-devices -b
echo

read -p "Entrez l'ID du périphérique à autoriser (ex: 2) : " id
if [ -z "$id" ]; then
    echo "[ERREUR] Aucun ID saisi. Opération annulée."
    exit 1
fi

if ! usbguard list-devices -b | awk -v id="$id" '$1 == id && $2 == "block"' | grep -q .; then
    echo "[ERREUR] L’ID $id n’existe pas ou n’est pas bloqué."
    exit 1
fi


# Nettoyage de l'ID
id=$(echo "$id" | sed 's/://')

# Justification obligatoire avec relance jusqu’à saisie
while true; do
    read -p "Entrez une raison (obligatoire) pour l'autorisation de ce périphérique : " reason
    if [ -n "$reason" ]; then
        break
    fi
    echo "[ERREUR] La justification est obligatoire. Veuillez réessayer."
done

echo "[INFO] Autorisation du périphérique ID $id"
usbguard allow-device "$id"

# Génération de la règle
raw_line=$(usbguard list-devices -b | grep -E "^$id")

device_id=$(echo "$raw_line" | cut -d " " -f 4)
device_serial=$(echo "$raw_line" | cut -d " " -f 6)

rule=$(usbguard generate-policy -PX | awk -v id="$device_id" -v serial="$device_serial" '$0 ~ "id " id && $0 ~ "serial " serial { print; exit }')

if [ -z "$rule" ]; then
    echo "[ERREUR] Impossible de récupérer la règle complète pour ce périphérique."
    exit 1
fi

if [ ! -f "$RULES_PATH" ]; then
    touch "$RULES_PATH"
    chmod 600 "$RULES_PATH"
fi

# Ajout du commentaire + règle dans le fichier de  -configuration
{
    echo "# Autorisé le $(date '+%F %T')"
    echo "# Raison : $reason"
    echo "$rule"
} >> "$RULES_PATH"

chmod 600 "$RULES_PATH"

# Rechargement des règles
echo "[INFO] Rechargement des règles depuis $RULES_PATH"
systemctl reload usbguard
echo "[OK] Périphérique USB autorisé."
```

### usbguard-reset : Réinitialiser toutes les règles

```bash
#!/bin/bash
# usbguard-reset

USBGUARD_RULES="/etc/usbguard/rules.conf"

echo "[WARN] Réinitialisation des règles USBGuard..."
mv "${USBGUARD_RULES}" "${USBGUARD_RULES}.bak.$(date +%F_%T)"

shopt -s nullglob
for f in /etc/usbguard/rules.d/*.conf; do
    mv "$f" "$f.bak.$(date +%F_%T)"
done
shopt -u nullglob

cat << INNER_EOF > "${USBGUARD_RULES}"
# Allow keyboards
allow with-interface one-of { 03:00:01 03:01:01 }

# Allow mouses
allow with-interface one-of { 03:00:02 03:01:02 }

# Reject devices with suspicious combination of interfaces
reject with-interface all-of { 08:*:* 03:00:* }
reject with-interface all-of { 08:*:* 03:01:* }
reject with-interface all-of { 08:*:* e0:*:* }
reject with-interface all-of { 08:*:* 02:*:* }
INNER_EOF

chmod 600 "${USBGUARD_RULES}"

systemctl reload usbguard
echo "[OK] Toutes les règles USBGuard ont été réinitialisées."
```

---

## Logs

Pour afficher les événements liés à USBGuard :

```bash
journalctl -u usbguard
```

---

## Précautions

- **Attention à ne pas bloquer clavier/souris** si ce sont vos seuls moyens d’accès (ex : USB uniquement).
- **Toujours tester les règles sur une session avec accès root ou console** pour éviter de se verrouiller hors du système.
- **Sauvegardez toujours `/etc/usbguard/rules.conf`** avant toute modification.
