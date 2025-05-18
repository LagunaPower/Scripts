#!/bin/bash

set -e

# Valeurs par défaut
ACTIVATE_ALL=0
OUTPUT_FILE="./generated-repos/local-repos-$(date +%F).repo"
REPO_BASE_DIR="/mnt/hgfs/repo/Alma8"
BASEURL="file://"

# Création du dossier de sortie si nécessaire
mkdir -p "$(dirname "$OUTPUT_FILE")"

usage() {
    echo "Usage: $0 [-a] [-o fichier.repo]"
    echo "  -a  : activer tous les dépôts (sinon seuls appstream, baseos, epel, extras sont activés)"
    echo "  -o  : définir le nom du fichier .repo généré"
    exit 1
}

while getopts "ao:" opt; do
    case "$opt" in
        a) ACTIVATE_ALL=1 ;;
        o) OUTPUT_FILE="$OPTARG" ;;
        *) usage ;;
    esac
done

echo "🛠️ Génération du fichier .repo : $OUTPUT_FILE"

if [[ -e "$OUTPUT_FILE" ]]; then
    read -rp "⚠️ Le fichier '$OUTPUT_FILE' existe déjà. Voulez-vous l'écraser ? [o/N] " answer
    case "$answer" in
        [oO]|[oO][uU][iI]) 
            echo "Écrasement du fichier."
            ;;
        *)
            echo "Abandon."
            exit 1
            ;;
    esac
fi

echo "# Fichier généré le $(date +%F)" > "$OUTPUT_FILE"

for repo_path in "$REPO_BASE_DIR"/*; do
    [[ -d "$repo_path" ]] || continue
    repo_name=$(basename "$repo_path")
    echo "🔍 Traitement du dépôt : $repo_name"

    # Vérifier la présence de repodata/repomd.xml
    if [[ ! -f "$repo_path/repodata/repomd.xml" ]]; then
        echo "⚠️  Dépôt $repo_name ignoré : repodata/repomd.xml absent."
        continue
    fi

    # Activation selon option -a ou liste restreinte
    if (( ACTIVATE_ALL == 1 )); then
        enabled=1
    else
        case "$repo_name" in
            appstream|baseos|epel|extras) enabled=1 ;;
            *) enabled=0 ;;
        esac
    fi

    # Construction du baseurl complet
    baseurl="${BASEURL}${repo_path}/"

    # Recherche des clés GPG
    gpg_dir="$repo_path/gpg"
    gpgkeys=()
    if [[ -d "$gpg_dir" ]]; then
        keys=( "$gpg_dir"/RPM-GPG-KEY-* )
        if [[ -e "${keys[0]}" ]]; then
            for keyfile in "${keys[@]}"; do
                gpgkeys+=( "${baseurl}gpg/$(basename "$keyfile")" )
            done
        fi
    fi

    # Écriture du dépôt dans le fichier .repo
    cat >> "$OUTPUT_FILE" <<EOF

[$repo_name]
name=Local repo - $repo_name
baseurl=$baseurl
enabled=$enabled
EOF

    # Gestion des clés GPG et des flags gpgcheck/repo_gpgcheck
    if (( ${#gpgkeys[@]} > 0 )); then
        echo "repo_gpgcheck=1" >> "$OUTPUT_FILE"
        echo "gpgcheck=1" >> "$OUTPUT_FILE"
        # Première clé sur la même ligne
        printf "gpgkey=%s\n" "${gpgkeys[0]}" >> "$OUTPUT_FILE"
        # Clés suivantes sur lignes indentées
        for ((i=1; i<${#gpgkeys[@]}; i++)); do
            printf "       %s\n" "${gpgkeys[i]}" >> "$OUTPUT_FILE"
        done
    else
        echo "repo_gpgcheck=0" >> "$OUTPUT_FILE"
        echo "gpgcheck=0" >> "$OUTPUT_FILE"
    fi
done

echo "✅ Fichier .repo généré avec succès."

