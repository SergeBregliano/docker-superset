#!/bin/bash

# Script de sauvegarde et restauration pour PostgreSQL
# Utilise le conteneur prodrigestivill/postgres-backup-local
# Compatible Debian
# Usage: ./backup-restore.sh

# Vérifier que le script est exécuté avec bash et se relancer si nécessaire
if [ -z "${BASH_VERSION:-}" ]; then
    # Essayer de trouver bash dans le PATH
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    else
        echo "Erreur: Ce script doit être exécuté avec bash, pas avec sh"
        echo "bash n'a pas été trouvé dans le PATH"
        echo "Veuillez installer bash ou utiliser: /bin/bash ./backup-restore.sh"
        exit 1
    fi
fi

set -eu
# pipefail n'est supporté que par bash, pas par sh/dash
set -o pipefail 2>/dev/null || true

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction d'affichage avec couleur
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Charger les variables d'environnement depuis .env
load_env() {
    if [ -f .env ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' 2>/dev/null || echo "")
            case "$line" in
                ''|\#*)
                    continue
                    ;;
            esac
            if ! echo "$line" | grep -q '='; then
                continue
            fi
            var_name=$(echo "$line" | cut -d '=' -f 1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' 2>/dev/null || echo "")
            var_value=$(echo "$line" | cut -d '=' -f 2- 2>/dev/null || echo "")
            var_value=$(echo "$var_value" | sed "s/^[[:space:]]*['\"]//; s/['\"][[:space:]]*$//" 2>/dev/null || echo "$var_value")
            if echo "$var_name" | grep -qE '^[a-zA-Z_][a-zA-Z0-9_]*$' 2>/dev/null; then
                {
                    export "${var_name}=${var_value}" 2>&1
                } >/dev/null 2>&1 || true
            fi
        done < .env
        info "Variables d'environnement chargées depuis .env"
    else
        warning "Fichier .env non trouvé, utilisation des valeurs par défaut"
    fi
}

# Variables avec valeurs par défaut
DATA_PATH=${DATA_PATH:-./appData}
MAIN_CONTAINER_NAME=${MAIN_CONTAINER_NAME:-superset}
POSTGRES_DB=${POSTGRES_DB:-superset}
POSTGRES_USER=${POSTGRES_USER:-superset}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-}
POSTGRES_USERDATA_DB=${POSTGRES_USERDATA_DB:-user_data}

BACKUP_DIR="${DATA_PATH}/backups"
BACKUP_CONTAINER="${MAIN_CONTAINER_NAME}_backup"
DATABASE_CONTAINER="${MAIN_CONTAINER_NAME}_database"

# Vérifier que Docker est disponible
check_docker() {
    if ! command -v docker &> /dev/null; then
        error "Docker n'est pas installé ou n'est pas dans le PATH"
        exit 1
    fi
}

# Vérifier que les conteneurs sont en cours d'exécution
check_containers() {
    if ! docker ps --format '{{.Names}}' | grep -q "^${BACKUP_CONTAINER}$"; then
        error "Le conteneur de backup '${BACKUP_CONTAINER}' n'est pas en cours d'exécution"
        info "Démarrez-le avec: docker-compose up -d backup"
        exit 1
    fi
    
    if ! docker ps --format '{{.Names}}' | grep -q "^${DATABASE_CONTAINER}$"; then
        error "Le conteneur de base de données '${DATABASE_CONTAINER}' n'est pas en cours d'exécution"
        info "Démarrez-le avec: docker-compose up -d database"
        exit 1
    fi
}

# Vérifier que le répertoire de sauvegarde existe
check_backup_dir() {
    if [ ! -d "${BACKUP_DIR}" ]; then
        warning "Le répertoire de sauvegarde '${BACKUP_DIR}' n'existe pas, création..."
        mkdir -p "${BACKUP_DIR}"
        success "Répertoire créé: ${BACKUP_DIR}"
    fi
}

# Fonction pour vérifier et corriger les permissions du répertoire de backup
fix_backup_permissions() {
    info "Vérification des permissions du répertoire de backup..."
    
    # Vérifier que le répertoire existe
    if [ ! -d "${BACKUP_DIR}" ]; then
        warning "Le répertoire de sauvegarde '${BACKUP_DIR}' n'existe pas, création..."
        mkdir -p "${BACKUP_DIR}"
    fi
    
    # Corriger les permissions du répertoire principal
    chmod 777 "${BACKUP_DIR}" 2>/dev/null || {
        warning "Impossible de modifier les permissions de ${BACKUP_DIR}"
        warning "Vous devrez peut-être exécuter: sudo chmod -R 777 ${BACKUP_DIR}"
    }
    
    # Créer les sous-répertoires s'ils n'existent pas
    mkdir -p "${BACKUP_DIR}/last" "${BACKUP_DIR}/daily" "${BACKUP_DIR}/weekly" "${BACKUP_DIR}/monthly" 2>/dev/null || true
    
    # Corriger les permissions de tous les sous-répertoires
    find "${BACKUP_DIR}" -type d -exec chmod 777 {} \; 2>/dev/null || true
    
    # Vérifier que le conteneur peut écrire
    if ! docker exec "${BACKUP_CONTAINER}" test -w /backups 2>/dev/null; then
        warning "Le conteneur ne peut toujours pas écrire dans /backups"
        warning "Tentative de redémarrage du conteneur..."
        docker-compose restart backup 2>/dev/null || docker compose restart backup 2>/dev/null || true
        sleep 2
    fi
    
    # Vérification finale
    if docker exec "${BACKUP_CONTAINER}" test -w /backups 2>/dev/null; then
        success "Permissions du répertoire de backup correctes"
    else
        error "Le conteneur ne peut toujours pas écrire dans /backups"
        error "Vérifiez les permissions manuellement: ls -la ${BACKUP_DIR}"
        return 1
    fi
}

# Fonction pour effectuer une sauvegarde manuelle
perform_backup() {
    info "Démarrage de la sauvegarde manuelle..."
    
    # Vérifier et corriger les permissions avant de commencer
    if ! fix_backup_permissions; then
        error "Impossible de corriger les permissions. Veuillez les vérifier manuellement."
        exit 1
    fi
    
    info "Utilisation du script de backup intégré du conteneur..."
    
    # Exécuter le script de backup du conteneur
    docker exec "${BACKUP_CONTAINER}" /backup.sh
    
    success "Sauvegarde terminée!"
    info "Les fichiers de sauvegarde sont disponibles dans: ${BACKUP_DIR}"
    echo ""
    find "${BACKUP_DIR}" -type f -name "*.sql.gz" | sort -r | head -10
}

# Fonction pour lister les sauvegardes disponibles
list_backups() {
    local db_name=$1
    local backups=()
    local temp_file
    
    temp_file=$(mktemp)
    
    # Chercher récursivement les fichiers de sauvegarde pour cette base
    find "${BACKUP_DIR}" -type f \( \
        -name "${db_name}-*.sql.gz" \
        -o -name "${db_name}-*.sql" \
        -o -name "postgres_${db_name}_*.sql.gz" \
        -o -name "postgres_${db_name}_*.sql" \
    \) 2>/dev/null | sort -r > "${temp_file}"
    
    while IFS= read -r file; do
        if [ -f "${file}" ]; then
            backups+=("${file}")
        fi
    done < "${temp_file}"
    
    rm -f "${temp_file}"
    
    if [ ${#backups[@]} -eq 0 ]; then
        return 1
    fi
    
    echo "${backups[@]}"
    return 0
}

# Fonction pour restaurer une base de données
restore_database() {
    local db_name=$1
    local backup_file=$2
    
    info "Restauration de la base '${db_name}' depuis '${backup_file}'..."
    
    # Arrêter Superset si nécessaire
    if docker ps --format '{{.Names}}' | grep -q "^${MAIN_CONTAINER_NAME}$"; then
        warning "Arrêt de Superset pour la restauration..."
        docker-compose stop superset 2>/dev/null || docker compose stop superset 2>/dev/null || true
    fi
    
    # Supprimer la base si elle existe pour éviter les conflits
    if docker exec "${DATABASE_CONTAINER}" psql -U "${POSTGRES_USER}" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${db_name}'" 2>/dev/null | grep -q 1; then
        warning "Suppression de la base de données existante '${db_name}'..."
        # Déconnecter toutes les sessions actives
        docker exec "${DATABASE_CONTAINER}" sh -c \
            "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d postgres -c \"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${db_name}' AND pid <> pg_backend_pid();\"" 2>/dev/null || true
        # Supprimer la base
        docker exec "${DATABASE_CONTAINER}" sh -c \
            "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d postgres -c 'DROP DATABASE \"${db_name}\";'" 2>/dev/null || true
    fi
    
    # Créer la base de données
    info "Création de la base de données '${db_name}'..."
    docker exec "${DATABASE_CONTAINER}" sh -c \
        "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d postgres -c 'CREATE DATABASE \"${db_name}\";'" 2>/dev/null || true
    
    # Restauration simple avec gunzip et psql
    info "Restauration en cours..."
    gunzip -c "${backup_file}" | \
        docker exec -i "${DATABASE_CONTAINER}" sh -c \
        "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${db_name}'" 2>&1 | \
        grep -v "ERROR:.*unrecognized configuration parameter" || true
    
    success "Restauration de '${db_name}' terminée!"
}

# Fonction pour extraire le timestamp d'un nom de fichier
extract_timestamp() {
    local filename=$1
    if [[ "${filename}" =~ -([0-9]{8}-[0-9]{6})\. ]]; then
        # Format avec heure: 20251128-183700
        echo "${BASH_REMATCH[1]}"
    elif [[ "${filename}" =~ -([0-9]{8})\. ]]; then
        # Format sans heure: 20251128
        echo "${BASH_REMATCH[1]}"
    elif [[ "${filename}" =~ -([0-9]{6})\. ]]; then
        # Format semaine: 202548
        echo "${BASH_REMATCH[1]}"
    fi
}

# Fonction pour effectuer une restauration
perform_restore() {
    info "Démarrage de la restauration..."
    
    # Lister toutes les sauvegardes disponibles
    info "Recherche des sauvegardes disponibles..."
    echo ""
    
    local all_backups
    all_backups=$(find "${BACKUP_DIR}" -type f \( -name "*.sql.gz" -o -name "*.sql" \) 2>/dev/null | sort -r)
    
    if [ -z "${all_backups}" ]; then
        error "Aucune sauvegarde trouvée dans ${BACKUP_DIR}"
        exit 1
    fi
    
    # Grouper les sauvegardes par timestamp (sans tableaux associatifs pour compatibilité sh)
    local temp_group_file=$(mktemp)
    local temp_timestamps_file=$(mktemp)
    local temp_all_backups=$(mktemp)
    
    # Écrire toutes les sauvegardes dans un fichier temporaire
    echo "${all_backups}" > "${temp_all_backups}"
    
    while IFS= read -r file; do
        if [ -f "${file}" ]; then
            local filename=$(basename "${file}")
            local timestamp=$(extract_timestamp "${filename}")
            
            if [ -n "${timestamp}" ]; then
                # Vérifier si ce timestamp existe déjà
                if ! grep -q "^${timestamp}:" "${temp_group_file}" 2>/dev/null; then
                    echo "${timestamp}:${file}" >> "${temp_group_file}"
                    echo "${timestamp}" >> "${temp_timestamps_file}"
                else
                    # Ajouter le fichier au groupe existant
                    local existing=$(grep "^${timestamp}:" "${temp_group_file}" | cut -d: -f2-)
                    local new_line="${timestamp}:${existing} ${file}"
                    sed "s|^${timestamp}:.*|${new_line}|" "${temp_group_file}" > "${temp_group_file}.tmp" && mv "${temp_group_file}.tmp" "${temp_group_file}"
                fi
            fi
        fi
    done < "${temp_all_backups}"
    
    # Nettoyer les fichiers temporaires
    rm -f "${temp_all_backups}" "${temp_group_file}.tmp" 2>/dev/null || true
    
    # Chercher les sauvegardes "latest" (liens symboliques ou fichiers)
    local latest_backups=$(find "${BACKUP_DIR}" -type f -o -type l \( -name "*latest*.sql.gz" -o -name "*latest*.sql" \) 2>/dev/null | sort)
    local superset_latest=""
    local user_data_latest=""
    
    for latest_file in ${latest_backups}; do
        local latest_filename=$(basename "${latest_file}")
        # Résoudre le lien symbolique si c'est un lien
        local real_file=$(readlink -f "${latest_file}" 2>/dev/null || echo "${latest_file}")
        if [ -f "${real_file}" ] || [ -L "${latest_file}" ]; then
            if [[ "${latest_filename}" == *"${POSTGRES_DB}"* ]]; then
                superset_latest="${real_file}"
            elif [[ "${latest_filename}" == *"${POSTGRES_USERDATA_DB}"* ]]; then
                user_data_latest="${real_file}"
            fi
        fi
    done
    
    # Afficher les sauvegardes groupées
    echo "=== Sauvegardes disponibles ==="
    echo ""
    
    local index=1
    local temp_selected_file=$(mktemp)
    local temp_sorted_timestamps=$(mktemp)
    
    # Afficher d'abord les sauvegardes "latest" si elles existent
    if [ -n "${superset_latest}" ] || [ -n "${user_data_latest}" ]; then
        local latest_date=""
        local latest_superset_size=""
        local latest_user_data_size=""
        
        if [ -n "${superset_latest}" ]; then
            latest_date=$(stat -c %y "${superset_latest}" 2>/dev/null || stat -f "%Sm" "${superset_latest}" 2>/dev/null || echo "Date inconnue")
            latest_superset_size=$(du -h "${superset_latest}" | cut -f1)
        fi
        if [ -n "${user_data_latest}" ]; then
            if [ -z "${latest_date}" ]; then
                latest_date=$(stat -c %y "${user_data_latest}" 2>/dev/null || stat -f "%Sm" "${user_data_latest}" 2>/dev/null || echo "Date inconnue")
            fi
            latest_user_data_size=$(du -h "${user_data_latest}" | cut -f1)
        fi
        
        echo "[$index] Sauvegarde LATEST (${latest_date})"
        if [ -n "${superset_latest}" ]; then
            echo "     - ${POSTGRES_DB}: $(basename "${superset_latest}") (${latest_superset_size})"
        fi
        if [ -n "${user_data_latest}" ]; then
            echo "     - ${POSTGRES_USERDATA_DB}: $(basename "${user_data_latest}") (${latest_user_data_size})"
        fi
        
        # Stocker les fichiers latest
        echo "${superset_latest}|${user_data_latest}|latest" >> "${temp_selected_file}"
        index=$((index + 1))
        echo ""
    fi
    
    # Trier les timestamps (plus récents en premier) dans un fichier
    sort -r "${temp_timestamps_file}" > "${temp_sorted_timestamps}"
    
    # Lire le fichier trié (pas de pipe pour éviter les problèmes de scope)
    while IFS= read -r timestamp; do
        local group_line=$(grep "^${timestamp}:" "${temp_group_file}" | cut -d: -f2-)
        local files="${group_line}"
        local superset_file=""
        local user_data_file=""
        local superset_size=""
        local user_data_size=""
        local date_str=""
        
        # Séparer les fichiers par base
        for file in ${files}; do
            local filename=$(basename "${file}")
            # Ignorer les fichiers latest déjà affichés
            if [[ "${filename}" == *"latest"* ]]; then
                continue
            fi
            if [[ "${filename}" == *"${POSTGRES_DB}"* ]]; then
                superset_file="${file}"
                superset_size=$(du -h "${file}" | cut -f1)
                date_str=$(stat -c %y "${file}" 2>/dev/null || stat -f "%Sm" "${file}" 2>/dev/null || echo "Date inconnue")
            elif [[ "${filename}" == *"${POSTGRES_USERDATA_DB}"* ]]; then
                user_data_file="${file}"
                user_data_size=$(du -h "${file}" | cut -f1)
                if [ -z "${date_str}" ]; then
                    date_str=$(stat -c %y "${file}" 2>/dev/null || stat -f "%Sm" "${file}" 2>/dev/null || echo "Date inconnue")
                fi
            fi
        done
        
        # Afficher la sauvegarde groupée seulement si elle contient des fichiers (non latest)
        if [ -n "${superset_file}" ] || [ -n "${user_data_file}" ]; then
            echo "[$index] Sauvegarde du ${date_str}"
            if [ -n "${superset_file}" ]; then
                echo "     - ${POSTGRES_DB}: $(basename "${superset_file}") (${superset_size})"
            fi
            if [ -n "${user_data_file}" ]; then
                echo "     - ${POSTGRES_USERDATA_DB}: $(basename "${user_data_file}") (${user_data_size})"
            fi
            
            # Stocker les fichiers pour ce groupe
            echo "${superset_file}|${user_data_file}|${timestamp}" >> "${temp_selected_file}"
            index=$((index + 1))
        fi
    done < "${temp_sorted_timestamps}"
    
    local total_backups=$((index - 1))
    rm -f "${temp_sorted_timestamps}"
    
    echo ""
    
    # Demander à l'utilisateur de choisir
    echo ""
    echo "Quelle sauvegarde souhaitez-vous restaurer ?"
    read -p "Entrez le numéro de la sauvegarde: " choice
    
    if ! [[ "${choice}" =~ ^[0-9]+$ ]] || [ "${choice}" -lt 1 ] || [ "${choice}" -gt "${total_backups}" ]; then
        error "Choix invalide"
        rm -f "${temp_group_file}" "${temp_timestamps_file}" "${temp_selected_file}"
        exit 1
    fi
    
    local selected_group=$(sed -n "${choice}p" "${temp_selected_file}")
    local superset_file=$(echo "${selected_group}" | cut -d'|' -f1)
    local user_data_file=$(echo "${selected_group}" | cut -d'|' -f2)
    
    # Nettoyer les fichiers temporaires
    rm -f "${temp_group_file}" "${temp_timestamps_file}" "${temp_selected_file}" 2>/dev/null || true
    
    # Déterminer ce qui doit être restauré
    local restore_superset=false
    local restore_user_data=false
    
    if [ -n "${superset_file}" ] && [ "${superset_file}" != "" ]; then
        restore_superset=true
    fi
    
    if [ -n "${user_data_file}" ] && [ "${user_data_file}" != "" ]; then
        restore_user_data=true
    fi
    
    if [ "${restore_superset}" = false ] && [ "${restore_user_data}" = false ]; then
        error "Aucune sauvegarde valide trouvée"
        exit 1
    fi
    
    # Afficher les informations de restauration
    echo ""
    info "Restauration planifiée:"
    if [ "${restore_superset}" = true ]; then
        echo "  - Base '${POSTGRES_DB}' depuis: $(basename "${superset_file}")"
    fi
    if [ "${restore_user_data}" = true ]; then
        echo "  - Base '${POSTGRES_USERDATA_DB}' depuis: $(basename "${user_data_file}")"
    fi
    
    echo ""
    warning "ATTENTION: Cette opération va écraser les bases de données sélectionnées!"
    read -p "Êtes-vous sûr de vouloir continuer ? (oui/non): " confirm
    
    if [ "${confirm}" != "oui" ] && [ "${confirm}" != "OUI" ] && [ "${confirm}" != "o" ] && [ "${confirm}" != "O" ]; then
        info "Restauration annulée"
        exit 0
    fi
    
    # Effectuer les restaurations
    if [ "${restore_superset}" = true ]; then
        restore_database "${POSTGRES_DB}" "${superset_file}"
    fi
    
    if [ "${restore_user_data}" = true ]; then
        restore_database "${POSTGRES_USERDATA_DB}" "${user_data_file}"
    fi
    
    # Redémarrer Superset si nécessaire
    if docker ps -a --format '{{.Names}}' | grep -q "^${MAIN_CONTAINER_NAME}$"; then
        info "Redémarrage de Superset..."
        docker-compose start superset 2>/dev/null || docker compose start superset 2>/dev/null || true
    fi
    
    success "Restauration terminée!"
}

# Menu principal
show_menu() {
    echo ""
    echo "=========================================="
    echo "  Gestionnaire de sauvegarde PostgreSQL"
    echo "=========================================="
    echo ""
    echo "Que souhaitez-vous faire ?"
    echo ""
    echo "  1) Effectuer une sauvegarde"
    echo "  2) Restaurer une sauvegarde"
    echo "  3) Quitter"
    echo ""
    read -p "Votre choix [1-3]: " choice
    
    case "${choice}" in
        1)
            perform_backup
            ;;
        2)
            perform_restore
            ;;
        3)
            info "Au revoir!"
            exit 0
            ;;
        *)
            error "Choix invalide"
            exit 1
            ;;
    esac
}

# Fonction principale
main() {
    load_env
    check_docker
    check_containers
    check_backup_dir
    show_menu
}

# Exécuter le script
main "$@"
