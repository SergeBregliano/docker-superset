#!/bin/bash

# Script de sauvegarde et restauration pour PostgreSQL
# Utilise le conteneur prodrigestivill/postgres-backup-local
# Compatible Debian
# Usage: ./backup-restore.sh

# Vérifier que le script est exécuté avec bash
if [ -z "${BASH_VERSION:-}" ]; then
    echo "Erreur: Ce script doit être exécuté avec bash, pas avec sh"
    echo "Utilisez: bash ./backup-restore.sh"
    echo "Ou: ./backup-restore.sh (si le fichier est exécutable)"
    exit 1
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

# Fonction pour effectuer une sauvegarde manuelle
perform_backup() {
    info "Démarrage de la sauvegarde manuelle..."
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

# Fonction pour effectuer une restauration
perform_restore() {
    info "Démarrage de la restauration..."
    
    # Lister les sauvegardes disponibles
    info "Recherche des sauvegardes disponibles..."
    echo ""
    
    local superset_backups
    superset_backups=$(list_backups "${POSTGRES_DB}" 2>/dev/null || true)
    
    local user_data_backups
    user_data_backups=$(list_backups "${POSTGRES_USERDATA_DB}" 2>/dev/null || true)
    
    if [ -z "${superset_backups}" ] && [ -z "${user_data_backups}" ]; then
        error "Aucune sauvegarde trouvée dans ${BACKUP_DIR}"
        exit 1
    fi
    
    # Afficher les sauvegardes disponibles
    echo "=== Sauvegardes disponibles ==="
    echo ""
    
    local index=1
    declare -a backup_files
    
    if [ -n "${superset_backups}" ]; then
        echo "Base '${POSTGRES_DB}':"
        local temp_file
        temp_file=$(mktemp)
        echo "${superset_backups}" | tr ' ' '\n' > "${temp_file}"
        while IFS= read -r file; do
            if [ -f "${file}" ]; then
                local filename=$(basename "${file}")
                local size=$(du -h "${file}" | cut -f1)
                local date=$(stat -c %y "${file}" 2>/dev/null || stat -f "%Sm" "${file}" 2>/dev/null || echo "Date inconnue")
                echo "  [$index] ${filename} (${size}, ${date})"
                backup_files+=("${file}")
                ((index++))
            fi
        done < "${temp_file}"
        rm -f "${temp_file}"
        echo ""
    fi
    
    if [ -n "${user_data_backups}" ]; then
        echo "Base '${POSTGRES_USERDATA_DB}':"
        local temp_file
        temp_file=$(mktemp)
        echo "${user_data_backups}" | tr ' ' '\n' > "${temp_file}"
        while IFS= read -r file; do
            if [ -f "${file}" ]; then
                local filename=$(basename "${file}")
                local size=$(du -h "${file}" | cut -f1)
                local date=$(stat -c %y "${file}" 2>/dev/null || stat -f "%Sm" "${file}" 2>/dev/null || echo "Date inconnue")
                echo "  [$index] ${filename} (${size}, ${date})"
                backup_files+=("${file}")
                ((index++))
            fi
        done < "${temp_file}"
        rm -f "${temp_file}"
        echo ""
    fi
    
    # Demander à l'utilisateur de choisir
    echo "Quelle sauvegarde souhaitez-vous restaurer ?"
    read -p "Entrez le numéro de la sauvegarde: " choice
    
    if ! [[ "${choice}" =~ ^[0-9]+$ ]] || [ "${choice}" -lt 1 ] || [ "${choice}" -gt ${#backup_files[@]} ]; then
        error "Choix invalide"
        exit 1
    fi
    
    local selected_backup="${backup_files[$((choice-1))]}"
    local selected_filename=$(basename "${selected_backup}")
    
    # Déterminer quelle base restaurer selon le nom du fichier
    local db_to_restore
    local other_db
    local other_backup=""
    
    if [[ "${selected_filename}" == *"${POSTGRES_DB}"* ]]; then
        db_to_restore="${POSTGRES_DB}"
        other_db="${POSTGRES_USERDATA_DB}"
    elif [[ "${selected_filename}" == *"${POSTGRES_USERDATA_DB}"* ]]; then
        db_to_restore="${POSTGRES_USERDATA_DB}"
        other_db="${POSTGRES_DB}"
    else
        error "Impossible de déterminer la base de données à restaurer depuis le nom du fichier"
        exit 1
    fi
    
    # Extraire la date/heure du nom de fichier pour trouver la sauvegarde correspondante de l'autre base
    # Format attendu: superset-20251128-183700.sql.gz ou superset-20251128.sql.gz
    local timestamp_pattern=""
    if [[ "${selected_filename}" =~ -([0-9]{8}-[0-9]{6})\. ]]; then
        # Format avec heure: 20251128-183700
        timestamp_pattern="${BASH_REMATCH[1]}"
    elif [[ "${selected_filename}" =~ -([0-9]{8})\. ]]; then
        # Format sans heure: 20251128
        timestamp_pattern="${BASH_REMATCH[1]}"
    elif [[ "${selected_filename}" =~ -([0-9]{6})\. ]]; then
        # Format semaine: 202548
        timestamp_pattern="${BASH_REMATCH[1]}"
    fi
    
    # Chercher la sauvegarde correspondante de l'autre base
    if [ -n "${timestamp_pattern}" ]; then
        local other_backup_candidate=$(find "${BACKUP_DIR}" -type f \( -name "${other_db}-*${timestamp_pattern}*.sql.gz" -o -name "${other_db}-*${timestamp_pattern}*.sql" \) 2>/dev/null | head -1)
        if [ -n "${other_backup_candidate}" ] && [ -f "${other_backup_candidate}" ]; then
            other_backup="${other_backup_candidate}"
        fi
    fi
    
    # Afficher les informations de restauration
    echo ""
    info "Restauration planifiée:"
    echo "  - Base '${db_to_restore}' depuis: $(basename "${selected_backup}")"
    if [ -n "${other_backup}" ]; then
        echo "  - Base '${other_db}' depuis: $(basename "${other_backup}")"
        echo ""
        warning "ATTENTION: Cette opération va écraser les deux bases de données!"
        read -p "Voulez-vous restaurer les deux bases ? (oui/non): " restore_both
        
        if [ "${restore_both}" = "oui" ] || [ "${restore_both}" = "OUI" ] || [ "${restore_both}" = "o" ] || [ "${restore_both}" = "O" ]; then
            # Restaurer les deux bases
            restore_database "${db_to_restore}" "${selected_backup}"
            restore_database "${other_db}" "${other_backup}"
        else
            # Restaurer uniquement la base sélectionnée
            warning "ATTENTION: Cette opération va écraser la base de données '${db_to_restore}'!"
            read -p "Êtes-vous sûr de vouloir continuer ? (oui/non): " confirm
            
            if [ "${confirm}" != "oui" ] && [ "${confirm}" != "OUI" ] && [ "${confirm}" != "o" ] && [ "${confirm}" != "O" ]; then
                info "Restauration annulée"
                exit 0
            fi
            
            restore_database "${db_to_restore}" "${selected_backup}"
        fi
    else
        # Pas de sauvegarde correspondante pour l'autre base
        warning "ATTENTION: Cette opération va écraser la base de données '${db_to_restore}'!"
        read -p "Êtes-vous sûr de vouloir continuer ? (oui/non): " confirm
        
        if [ "${confirm}" != "oui" ] && [ "${confirm}" != "OUI" ] && [ "${confirm}" != "o" ] && [ "${confirm}" != "O" ]; then
            info "Restauration annulée"
            exit 0
        fi
        
        restore_database "${db_to_restore}" "${selected_backup}"
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
