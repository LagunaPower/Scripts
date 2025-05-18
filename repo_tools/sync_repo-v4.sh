#!/bin/bash
set -e

DEST_DIR="/mnt/hgfs/repo/Alma8"
ARCH="x86_64,noarch"
LOG_FILE="/var/log/reposync-$(date +%F).log"

# === Gestion des options ===
DOWNLOAD_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --downloadonly)
            DOWNLOAD_ONLY=1
            shift
            ;;
        *)
            echo "Usage: $0 [--downloadonly]"
            exit 1
            ;;
    esac
done

# === Logging ===
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "📅 Lancement de la synchronisation : $(date)"
echo "📂 Répertoire cible : $DEST_DIR"
echo "🧱 Architectures : $ARCH"
echo "🗒️  Journal : $LOG_FILE"
if [[ $DOWNLOAD_ONLY -eq 1 ]]; then
    echo "⚠️ Mode téléchargement uniquement : createrepo sera désactivé"
fi
echo
readarray -t REPOS < <(dnf repolist -q enabled | awk 'NR>1 {print $1}')
echo "Liste complète des dépôts à synchroniser :"
for r in "${REPOS[@]}"; do
    echo " - $r"
done
echo

TOTAL_SUCCESS=0
TOTAL_FAIL=0

for repo in "${REPOS[@]}"; do
    REPO_PATH="$DEST_DIR/$repo"
    GPG_PATH="$REPO_PATH/gpg"
    mkdir -p "$REPO_PATH" "$GPG_PATH"

    echo "🔄 Synchronisation du dépôt : $repo"
    dnf makecache --repo "$repo" --quiet

    if dnf reposync \
        --repoid="$repo" \
        --download-path="$REPO_PATH" \
        --download-metadata \
        --arch="$ARCH" \
        --newest-only \
        --downloadcomps \
        --delete \
        --norepopath \
		--quiet; then

        echo "✅ Dépôt $repo synchronisé avec succès."
		
        if [[ $DOWNLOAD_ONLY -eq 0 ]]; then
            if createrepo --update --quiet --workers 20 "$REPO_PATH"; then
				echo "ℹ️ createrepo correctement terminé"
			else
				echo "❌ Échec pendant createrepo"
			fi
        else
            echo "ℹ️ createrepo désactivé en mode --downloadonly"
        fi

        # Supprimer metalink.xml s'il existe
		find "$REPO_PATH" -type f -name "metalink.xml" -exec sh -c 'echo "🗑️ Suppression de {}"; rm -f "{}"' \;

        # Récupération des clés GPG
        GPG_KEYS_LINE=$(dnf config-manager --dump "$repo" | grep -E '^gpgkey\s*=' | cut -d= -f2-)
        if [[ -n "$GPG_KEYS_LINE" ]]; then
            echo "📥 Téléchargement des clés GPG pour $repo"
            IFS=', ' read -r -a GPG_URLS <<< "$GPG_KEYS_LINE"
            i=1
            for url in "${GPG_URLS[@]}"; do
                url=$(echo "$url" | xargs)
                if [[ -n "$url" ]]; then
                    FILENAME="RPM-GPG-KEY-$i"
                    if curl -fsSL -o "$GPG_PATH/$FILENAME" "$url"; then
                        echo "  ➤ Clé $i téléchargée"
                    else
                        echo "  ❌ Échec du téléchargement : $url"
                    fi
                    ((i++))
                fi
            done
        else
            echo "⚠️  Pas de clé GPG déclarée pour $repo"
        fi

        PACKAGE_COUNT=$(find "$REPO_PATH" -type f -name "*.rpm" | wc -l)
        if (( PACKAGE_COUNT == 0 )); then
            echo "⚠️  Aucun paquet téléchargé pour $repo (répertoire vide)."
        else
            SIZE=$(du -sh "$REPO_PATH" | cut -f1)
            echo "📦 Taille du dépôt $repo : $SIZE ($PACKAGE_COUNT paquets)"
        fi

        TOTAL_SUCCESS=$((TOTAL_SUCCESS + 1))
    else
        echo "❌ Échec de la synchronisation du dépôt $repo"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi

    echo
done

echo "=== ✅ Résumé de la synchronisation ==="
echo "✔️ Dépôts OK    : $TOTAL_SUCCESS"
echo "❌ Dépôts en échec : $TOTAL_FAIL"
echo "🕒 Fin : $(date)"

