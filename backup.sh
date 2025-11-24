#!/bin/bash

# Script de sauvegarde pour Superset
# Ce script sauvegarde PostgreSQL (priorité 1) et les fichiers Superset

set -e

# Charger les variables d'environnement
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

BACKUP_DIR=${BACKUP_DIR:-./backups}
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATA_PATH=${DATA_PATH:-./appData}

# Créer le dossier de sauvegarde
mkdir -p "$BACKUP_DIR"

echo "Début de la sauvegarde Superset..."
echo "Dossier de sauvegarde: $BACKUP_DIR"
echo ""

# 1. Sauvegarde PostgreSQL (PRIORITÉ 1 - CRITIQUE)
echo "Sauvegarde PostgreSQL (priorité 1)..."
DB_NAME=${POSTGRES_DB:-superset}
USERDATA_DB=${POSTGRES_USERDATA_DB:-user_data}
DB_USER=${POSTGRES_USER:-superset}
CONTAINER_NAME=${MAIN_CONTAINER_NAME:-superset}_database

# Sauvegarde de la base Superset (métadonnées)
PG_BACKUP_FILE="$BACKUP_DIR/postgres_${DB_NAME}_${TIMESTAMP}.sql.gz"
docker exec "$CONTAINER_NAME" pg_dump -U "$DB_USER" "$DB_NAME" | gzip > "$PG_BACKUP_FILE"

if [ -f "$PG_BACKUP_FILE" ] && [ -s "$PG_BACKUP_FILE" ]; then
    PG_SIZE=$(du -h "$PG_BACKUP_FILE" | cut -f1)
    echo "Base '$DB_NAME' sauvegardée: $PG_BACKUP_FILE ($PG_SIZE)"
else
    echo "Erreur lors de la sauvegarde de la base $DB_NAME"
    exit 1
fi

# Sauvegarde de la base user_data (données utilisateurs)
if docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$USERDATA_DB"; then
    USERDATA_BACKUP_FILE="$BACKUP_DIR/postgres_${USERDATA_DB}_${TIMESTAMP}.sql.gz"
    docker exec "$CONTAINER_NAME" pg_dump -U "$DB_USER" "$USERDATA_DB" | gzip > "$USERDATA_BACKUP_FILE"
    
    if [ -f "$USERDATA_BACKUP_FILE" ] && [ -s "$USERDATA_BACKUP_FILE" ]; then
        USERDATA_SIZE=$(du -h "$USERDATA_BACKUP_FILE" | cut -f1)
        echo "Base '$USERDATA_DB' sauvegardée: $USERDATA_BACKUP_FILE ($USERDATA_SIZE)"
    else
        echo "Aucune donnée dans la base $USERDATA_DB"
    fi
else
    echo "La base $USERDATA_DB n'existe pas encore (sera créée au premier démarrage)"
fi

# 2. Sauvegarde des fichiers Superset (PRIORITÉ 2)
echo ""
echo "Sauvegarde des fichiers Superset (priorité 2)..."

# Sauvegarder lib (fichiers uploadés, cache)
if [ -d "$DATA_PATH/superset/lib" ] && [ "$(ls -A $DATA_PATH/superset/lib)" ]; then
    FILES_BACKUP="$BACKUP_DIR/superset_files_${TIMESTAMP}.tar.gz"
    tar -czf "$FILES_BACKUP" -C "$DATA_PATH" superset/lib superset/home 2>/dev/null || true
    
    if [ -f "$FILES_BACKUP" ] && [ -s "$FILES_BACKUP" ]; then
        FILES_SIZE=$(du -h "$FILES_BACKUP" | cut -f1)
        echo "Fichiers Superset sauvegardés: $FILES_BACKUP ($FILES_SIZE)"
    else
        echo "Aucun fichier à sauvegarder dans superset/lib et superset/home"
    fi
else
    echo "Aucun fichier dans superset/lib et superset/home (normal si vous n'avez pas uploadé de fichiers)"
fi

# 3. Résumé
echo ""
echo "Sauvegarde terminée !"
echo ""
echo "Résumé :"
echo "   - Base '$DB_NAME' (métadonnées): $PG_BACKUP_FILE"
if [ -f "$USERDATA_BACKUP_FILE" ]; then
    echo "   - Base '$USERDATA_DB' (données utilisateurs): $USERDATA_BACKUP_FILE"
fi
if [ -f "$FILES_BACKUP" ]; then
    echo "   - Fichiers: $FILES_BACKUP"
fi
echo ""
echo "Pour restaurer PostgreSQL :"
echo "   # Restaurer la base Superset (métadonnées)"
echo "   gunzip < $PG_BACKUP_FILE | docker exec -i $CONTAINER_NAME psql -U $DB_USER $DB_NAME"
if [ -f "$USERDATA_BACKUP_FILE" ]; then
    echo ""
    echo "   # Restaurer la base user_data (données utilisateurs)"
    echo "   gunzip < $USERDATA_BACKUP_FILE | docker exec -i $CONTAINER_NAME psql -U $DB_USER $USERDATA_DB"
fi

