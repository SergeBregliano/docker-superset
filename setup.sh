#!/bin/bash

# Script d'initialisation de Superset
# Ce script doit être exécuté après le premier démarrage des conteneurs

set -e

# Charger les variables d'environnement
if [ -f .env ]; then
    # Lire le fichier .env ligne par ligne en gérant les accents et les espaces
    while IFS= read -r line || [ -n "$line" ]; do
        # Ignorer les lignes vides et les commentaires
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # Parser la ligne KEY=VALUE
        if [[ "$line" =~ ^[[:space:]]*([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            # Supprimer les espaces en début/fin (sans utiliser xargs pour éviter les problèmes d'accents)
            key="${key#"${key%%[![:space:]]*}"}"
            key="${key%"${key##*[![:space:]]}"}"
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"
            # Exporter la variable
            export "$key=$value"
        fi
    done < .env
fi

CONTAINER_NAME=${MAIN_CONTAINER_NAME:-superset}
ADMIN_USERNAME=${SUPERSET_ADMIN_USERNAME:-admin}
ADMIN_EMAIL=${SUPERSET_ADMIN_EMAIL:-admin@localhost}
ADMIN_PASSWORD=${SUPERSET_ADMIN_PASSWORD:-admin}

echo "Initialisation de Superset..."
echo "Conteneur: $CONTAINER_NAME"
echo "Admin: $ADMIN_USERNAME"

# Attendre que le conteneur soit prêt
echo "Attente du démarrage du conteneur..."
until docker ps | grep -q "$CONTAINER_NAME"; do
    sleep 2
done

# Attendre que Superset soit prêt
echo "Attente que Superset soit prêt..."
until docker exec "$CONTAINER_NAME" curl -f http://localhost:8088/health > /dev/null 2>&1; do
    echo "   En attente..."
    sleep 5
done

echo "Superset est prêt!"

# Vérifier et créer la base de données user_data si elle n'existe pas
echo "Vérification de la base de données 'user_data'..."
DB_NAME=${POSTGRES_DB:-superset}
USERDATA_DB=${POSTGRES_USERDATA_DB:-user_data}
DB_USER=${POSTGRES_USER:-superset}
DB_CONTAINER=${MAIN_CONTAINER_NAME:-superset}_database

# Attendre que PostgreSQL soit prêt
until docker exec "$DB_CONTAINER" pg_isready -U "$DB_USER" -d "$DB_NAME" > /dev/null 2>&1; do
    echo "   En attente de PostgreSQL..."
    sleep 2
done

# Vérifier si la base user_data existe
if ! docker exec "$DB_CONTAINER" psql -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$USERDATA_DB"; then
    echo "   Création de la base '$USERDATA_DB'..."
    # Se connecter à la base 'postgres' (par défaut) pour créer d'autres bases
    docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "postgres" -c "CREATE DATABASE $USERDATA_DB;" || {
        echo "Erreur lors de la création de la base $USERDATA_DB"
        exit 1
    }
    docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "postgres" -c "GRANT ALL PRIVILEGES ON DATABASE $USERDATA_DB TO $DB_USER;"
    echo "Base '$USERDATA_DB' créée avec succès !"
else
    echo "Base '$USERDATA_DB' existe déjà"
fi
echo ""

# Mise à jour de la base de données
echo "Mise à jour de la base de données..."
docker exec "$CONTAINER_NAME" superset db upgrade

# Initialisation
echo "Initialisation de Superset..."
docker exec "$CONTAINER_NAME" superset init

# Création de l'utilisateur admin
echo "Création de l'utilisateur admin..."
docker exec "$CONTAINER_NAME" superset fab create-admin \
    --username "$ADMIN_USERNAME" \
    --firstname Superset \
    --lastname Admin \
    --email "$ADMIN_EMAIL" \
    --password "$ADMIN_PASSWORD" || echo "L'utilisateur admin existe déjà"

echo "Initialisation terminée!"
echo ""
echo "Accédez à Superset: http://localhost:${SUPERSET_PORT:-8088}"
echo "Identifiant: $ADMIN_USERNAME"