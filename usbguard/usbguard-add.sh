#!/bin/bash
# usbguard-add

# Ce script permet de lister les périphériques USB bloqués et d’en autoriser un
# en mettant à jour de manière persistante le fichier de règles utilisé par USBGuard,
# avec un commentaire incluant la date, l’ID et une justification obligatoire.

if [ $(id -u) -ne 0 ]
then
echo -e "/!\ Cette commande doit être lancée avec les privilèges super-utilisateur.\n" 
exit 1
fi

DEFAULT_RULES="/etc/usbguard/rules.conf"
CONFIG_FILE="/etc/usbguard/usbguard-daemon.conf"
AUTH_USB_FILE="99-auth_usb.conf"

# Détection du fichier de règles depuis la conf principale
if [ -f "$CONFIG_FILE" ]; then
    RULES_PATH=$(awk -F '=' -v file="$AUTH_USB_FILE" '/^RuleFolder\s*=/{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2 "/" file}' "$CONFIG_FILE")
    RULES_PATH="${RULES_PATH:-$DEFAULT_RULES}"
else
    RULES_PATH="$DEFAULT_RULES"
fi

echo "[INFO] Périphériques USB actuellement bloqués :"
usbguard list-devices -b | sed 's/ hash .*//'
echo

read -p "Entrez l'ID du périphérique à autoriser (ex: 2) : " id
if [ -z "$id" ]; then
    echo "[ERREUR] Aucun ID saisi. Opération annulée."
    exit 1
fi

if ! usbguard list-devices -b | awk -v id="$id" '$1 == id":" && $2 == "block"' | grep -q .; then
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
    echo
    echo "# Autorisé le $(date '+%F %T')"
    echo "# Raison : $reason"
    echo "$rule"
} >> "$RULES_PATH"

chmod 600 "$RULES_PATH"

# Rechargement des règles
echo "[INFO] Rechargement des règles USBGUARD"
systemctl restart usbguard
echo "[OK] Périphérique USB autorisé."
