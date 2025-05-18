#!/bin/bash
set -e

REPO_BASE_DIR="/mnt/hgfs/repo/Alma8"

# Couleurs (avec séquences échappées au bon format)
GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
YELLOW=$'\033[0;33m'
NC=$'\033[0m' # No Color

cols=$(tput cols)

echo -e "🔎 Vérification des signatures des RPM dans les dépôts sous $REPO_BASE_DIR"

for repo_path in "$REPO_BASE_DIR"/*; do
    [[ -d "$repo_path" ]] || continue
    repo_name=$(basename "$repo_path")

    if [[ ! -f "$repo_path/repodata/repomd.xml" ]]; then
        echo -e "${YELLOW}⚠️  Dépôt $repo_name ignoré : repodata/repomd.xml absent.${NC}"
        continue
    fi

    echo -e "${YELLOW}📁 Dépôt : $repo_name${NC}"

    rpm_files=$(find "$repo_path" -type f -name '*.rpm')
    if [[ -z "$rpm_files" ]]; then
        echo -e "${YELLOW}⚠️  Aucun RPM trouvé dans $repo_name${NC}"
        continue
    fi

    for rpmfile in $rpm_files; do
        msg="Vérification $rpmfile"
        output=$(rpm -K "$rpmfile" 2>&1)
        if echo "$output" | grep -q "digests signatures OK"; then
            result="${GREEN}Signature OK${NC}"
        elif echo "$output" | grep -q "NOT OK"; then
            result="${RED}Signature NON valide${NC}"
        else
            result="${YELLOW}Signature inconnue ou absente${NC}"
        fi

        # Supprimer les séquences ANSI pour calcul de longueur
        plain_msg=$(echo -e "$msg" | sed 's/\x1b\[[0-9;]*m//g')
        plain_result=$(echo -e "$result" | sed 's/\x1b\[[0-9;]*m//g')
        space=$(( cols - ${#plain_msg} - ${#plain_result} ))
        (( space < 1 )) && space=1

        # Affichage avec printf, la chaîne contient les vraies séquences ANSI grâce à $''
        printf "%s%*s%s\n" "$msg" "$space" "" "$result"
    done
done

echo -e "${GREEN}✅ Vérification terminée.${NC}"

