#!/bin/bash

# Script pour charger les exemples Superset dans la base user_data
# Usage: ./load-examples.sh
#
# Prérequis:
# - Les conteneurs doivent être démarrés (docker-compose up -d)
# - Superset doit être initialisé (./setup.sh)
# - La base user_data doit exister (créée automatiquement par setup.sh)

set -e

# Charger les variables d'environnement
if [ -f .env ]; then
    # Lire le fichier .env ligne par ligne et exporter chaque variable
    while IFS= read -r line || [ -n "$line" ]; do
        # Ignorer les lignes vides et les commentaires
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # Exporter la variable si elle est au format KEY=VALUE
        if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            # Supprimer les espaces en début/fin de valeur
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"
            # Supprimer les guillemets entourants si présents
            if [[ "$value" =~ ^\".*\"$ ]] || [[ "$value" =~ ^\'.*\'$ ]]; then
                value="${value:1:-1}"
            fi
            export "$key=$value"
        fi
    done < .env
fi

CONTAINER_NAME=${MAIN_CONTAINER_NAME:-superset}
USERDATA_DB=${POSTGRES_USERDATA_DB:-user_data}

echo "Chargement des exemples Superset dans la base '$USERDATA_DB'..."
echo "Conteneur: $CONTAINER_NAME"
echo ""

# Vérifier que le conteneur est en cours d'exécution
if ! docker ps | grep -q "$CONTAINER_NAME"; then
    echo "Le conteneur $CONTAINER_NAME n'est pas en cours d'exécution"
    echo "   Démarrez-le avec: docker-compose up -d"
    exit 1
fi

# Attendre que Superset soit prêt
echo "Attente que Superset soit prêt..."
until docker exec "$CONTAINER_NAME" curl -f http://localhost:8088/health > /dev/null 2>&1; do
    echo "   En attente..."
    sleep 5
done

echo "Superset est prêt!"
echo ""

# Vérifier que la base user_data existe
DB_CONTAINER=${MAIN_CONTAINER_NAME:-superset}_database
DB_USER=${POSTGRES_USER:-superset}

if ! docker exec "$DB_CONTAINER" psql -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$USERDATA_DB"; then
    echo "La base de données '$USERDATA_DB' n'existe pas"
    echo "   Exécutez d'abord: ./setup.sh"
    exit 1
fi

echo "La base '$USERDATA_DB' existe"
echo ""

# Charger les exemples
echo "Chargement des exemples Superset..."
echo "   (Cela peut prendre quelques minutes...)"
echo ""

if docker exec "$CONTAINER_NAME" superset load-examples 2>&1; then
    echo ""
    echo "Exemples chargés avec succès dans '$USERDATA_DB'!"
    echo ""
    echo "Prochaines étapes:"
    echo "   1. Connectez-vous à Superset"
    echo "   2. Allez dans Data → Databases"
    echo "   3. Ajoutez une connexion à la base 'user_data' si ce n'est pas déjà fait:"
    echo "      - Nom: User Data"
    echo "      - SQLAlchemy URI: postgresql://${DB_USER}:${POSTGRES_PASSWORD}@database:${POSTGRES_PORT:-5432}/${USERDATA_DB}"
    echo "   4. Les exemples seront disponibles via cette connexion"
    echo ""
else
    echo ""
    echo "Erreur lors du chargement des exemples"
    echo "   Vérifiez les logs avec: docker-compose logs superset"
    exit 1
fi

