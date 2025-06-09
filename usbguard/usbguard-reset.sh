#!/bin/bash
# usbguard-reset

if [ $(id -u) -ne 0 ]
then
   echo -e "/!\ Cette commande doit être lancée avec les privilèges super-utilisateur.\n" 
   exit 1
fi

USBGUARD_RULES="/etc/usbguard/rules.conf"

echo "[WARN] Réinitialisation des règles USBGuard..."
mv "${USBGUARD_RULES}" "${USBGUARD_RULES}.bak.$(date +%F_%T)"

timestamp=$(date +%F_%T)

find /etc/usbguard/rules.d/ -maxdepth 1 -type f -name '*.conf' \
  -exec mv {} {}.bak.$timestamp \;

cat << EOF > "${USBGUARD_RULES}"
# Allow keyboards
allow with-interface one-of { 03:00:01 03:01:01 }

# Allow mouses
allow with-interface one-of { 03:00:02 03:01:02 }

# Reject devices with suspicious combination of interfaces
reject with-interface all-of { 08:*:* 03:00:* }
reject with-interface all-of { 08:*:* 03:01:* }
reject with-interface all-of { 08:*:* e0:*:* }
reject with-interface all-of { 08:*:* 02:*:* }
EOF

chmod 600 "${USBGUARD_RULES}"

systemctl restart usbguard
echo "[OK] Toutes les règles USBGuard ont été réinitialisées."
