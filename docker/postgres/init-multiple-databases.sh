#!/bin/bash
set -e

function create_user_and_database() {
	local database=$1
	echo "Creating database '$database'"
	# Se connecter à la base 'postgres' (par défaut) pour créer d'autres bases
	psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "postgres" <<-EOSQL
	    CREATE DATABASE $database;
	    GRANT ALL PRIVILEGES ON DATABASE $database TO $POSTGRES_USER;
	EOSQL
	
	# Activer PostGIS sur la base de données créée
	echo "Enabling PostGIS extension on database '$database'"
	psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$database" <<-EOSQL
	    CREATE EXTENSION IF NOT EXISTS postgis;
	    CREATE EXTENSION IF NOT EXISTS postgis_topology;
	    CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;
	EOSQL
}

# Activer PostGIS sur la base de données principale (superset)
echo "Enabling PostGIS extension on main database '$POSTGRES_DB'"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS postgis;
    CREATE EXTENSION IF NOT EXISTS postgis_topology;
    CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;
EOSQL

# Créer la deuxième base de données pour les données utilisateurs
if [ -n "$POSTGRES_USERDATA_DB" ]; then
	echo "Multiple database creation requested: $POSTGRES_USERDATA_DB"
	create_user_and_database "$POSTGRES_USERDATA_DB"
	echo "Database '$POSTGRES_USERDATA_DB' created successfully"
fi