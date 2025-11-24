# Docker Superset

Stack Docker complète pour Apache Superset, compatible avec https-portal.

## Architecture

- **Superset** : Application principale (Apache Superset)
- **PostgreSQL** : Base de données pour les métadonnées
- **Redis** : Cache et queue pour les tâches asynchrones (Celery)

## Prérequis

- Docker et Docker Compose installés
- Réseaux Docker `gateway` et `myapp` créés (ou modifiez les noms dans `.env`)

## Démarrage rapide

### 1. Configuration initiale

Copier le fichier d'exemple

```bash
cp env.example .env
```

Éditer .env et configurer :

```bash
- SUPERSET_SECRET_KEY
- POSTGRES_PASSWORD
- REDIS_PASSWORD
- SUPERSET_ADMIN_PASSWORD
- VIRTUAL_HOST #(si vous utilisez https-portal)
```

Pour configurer **SUPERSET_SECRET_KEY** :

```bash
python3 -c "import secrets; print(secrets.token_urlsafe(64))"
```

### 2. Démarrer les services

```bash
# Démarrer tous les services
docker-compose up -d

# Vérifier les logs
docker-compose logs -f superset
```

### 3. Initialiser Superset

```bash
# Exécuter le script d'initialisation
./setup.sh
```

Le script va :
- Attendre que Superset soit prêt
- Mettre à jour la base de données
- Initialiser Superset
- Créer l'utilisateur admin

### 4. Accéder à Superset

- **Local** : http://localhost:8088
- **Production** : Via https-portal avec le domaine configuré dans `VIRTUAL_HOST`

Identifiants par défaut (modifiables dans `.env`) :
- Username : `admin`
- Password : Celui défini dans `SUPERSET_ADMIN_PASSWORD`

## Traductions

Superset est configuré pour utiliser le français par défaut (`BABEL_DEFAULT_LOCALE=fr`), mais **les traductions françaises peuvent être incomplètes**. 

Superset est principalement développé en anglais et les traductions dépendent des contributions de la communauté. Si vous constatez que certaines parties de l'interface restent en anglais, c'est normal et cela signifie que ces traductions n'ont pas encore été fournies par la communauté.

Pour contribuer aux traductions françaises, consultez le [projet Superset sur GitHub](https://github.com/apache/superset).

## 🔧 Configuration

### Variables d'environnement principales

| Variable | Description | Défaut |
|----------|-------------|--------|
| `SUPERSET_VERSION` | Version de Superset | `5.0.0` |
| `SUPERSET_SECRET_KEY` | Clé secrète (OBLIGATOIRE) | - |
| `POSTGRES_PASSWORD` | Mot de passe PostgreSQL | - |
| `REDIS_PASSWORD` | Mot de passe Redis | - |
| `VIRTUAL_HOST` | Domaine pour https-portal | `localhost` |
| `SUPERSET_ADMIN_PASSWORD` | Mot de passe admin | - |

### Réseaux Docker

La stack utilise deux réseaux :
- `gateway` : Réseau externe pour https-portal (doit exister)
- `myapp` : Réseau interne pour la communication entre services

Pour créer les réseaux :
```bash
docker network create gateway
docker network create myapp
```

## Structure des volumes

Les données sont stockées dans `./appData` :

### Volumes de base de données

- **`appData/database/postgres`** : **CRITIQUE** ⚠️
  - **Contient TOUTES les métadonnées Superset** :
    - Dashboards (tableaux de bord)
    - Charts (graphiques)
    - Datasources (sources de données)
    - Users (utilisateurs)
    - Roles (rôles et permissions)
    - Logs d'activité
  - **Sauvegarde essentielle** : C'est le volume à sauvegarder !

### Séparation des bases de données PostgreSQL

Les métadonnées Superset et les données utilisateurs sont séparées dans deux bases de données PostgreSQL différentes :

- **Base `superset`** (métadonnées) : 
  - Dashboards, charts, utilisateurs, rôles, permissions, etc.
  - Tables créées automatiquement par Superset
  - **Ne pas modifier manuellement !**
  - **Sauvegarde essentielle** ⚠️

- **Base `user_data`** (données utilisateurs) :
  - CSV uploadés, tables créées manuellement
  - **Utilisez cette base pour vos données**
  - Créée automatiquement au premier démarrage

Cette séparation permet de :
- Protéger les métadonnées Superset des modifications accidentelles
- Organiser clairement les données
- Faciliter les sauvegardes sélectives
- Améliorer la sécurité et la maintenance

#### Comment utiliser la base `user_data` ?

**1. Ajouter une connexion à la base `user_data` dans Superset :**
   - Allez dans **Data → Databases → + Database**
   - Nom : `User Data`
   - SQLAlchemy URI : `postgresql://superset:VOTRE_MOT_DE_PASSE@database:5432/user_data`
   - Remplacez `VOTRE_MOT_DE_PASSE` par le mot de passe défini dans `.env`

**2. Uploader un CSV :**
   - Utilisez la connexion `user_data` lors de l'upload
   - Les tables seront créées directement dans la bonne base

**3. Créer des tables via SQL Lab :**
   - Sélectionnez la connexion `user_data`
   - Créez vos tables normalement

#### Charger les exemples Superset dans `user_data`

Superset fournit des exemples de données (jeux de données et dashboards) pour vous aider à démarrer. Ces exemples peuvent être chargés directement dans la base `user_data` :

**1. Charger les exemples :**

   ```bash
   # Assurez-vous que les conteneurs sont démarrés
   docker-compose up -d
   
   # Exécutez le script de chargement
   ./load-examples.sh
   ```

**2. Accéder aux exemples :**

   - Après le chargement, ajoutez la connexion à `user_data` dans Superset (voir section précédente)
   - Les exemples seront disponibles via cette connexion
   - Vous pourrez explorer les dashboards et jeux de données d'exemple

**Note :** Le script `load-examples.sh` vérifie automatiquement que Superset est prêt et que la base `user_data` existe avant de charger les exemples.

### Stratégie de sauvegarde recommandée

Sauvegarder `appData/database/postgres` (dump PostgreSQL)

#### Script de sauvegarde

Un script `backup.sh` est fourni pour faciliter les sauvegardes :

```bash
# Exécuter la sauvegarde
./backup.sh

# Les sauvegardes sont créées dans ./backups/
# - postgres_superset_YYYYMMDD_HHMMSS.sql.gz (dump PostgreSQL)
# - superset_files_YYYYMMDD_HHMMSS.tar.gz (fichiers uploadés)
```

**Restauration PostgreSQL** :
```bash
# Restaurer depuis une sauvegarde
gunzip < backups/postgres_superset_YYYYMMDD_HHMMSS.sql.gz | \
  docker exec -i ${MAIN_CONTAINER_NAME:-superset}_database \
  psql -U ${POSTGRES_USER:-superset} ${POSTGRES_DB:-superset}
```

## Sécurité

- Secrets stockés dans `.env` (non versionné)
- Healthchecks configurés pour tous les services
- Configuration de sécurité Superset activée
- Proxy fix configuré pour https-portal
- Connexions non sécurisées désactivées par défaut

## Commandes utiles

```bash
# Voir les logs
docker-compose logs -f superset

# Redémarrer un service
docker-compose restart superset

# Arrêter tous les services
docker-compose down

# Arrêter et supprimer les volumes (⚠️ supprime les données)
docker-compose down -v
rm -rf ./appData #(executé à la racine du projet)

# Reconstruire l'image Superset
docker-compose build superset

# Accéder au shell du conteneur Superset
docker exec -it superset bash

# Vérifier l'état des services
docker-compose ps
```

## Mise à jour

```bash
# 1. Modifier SUPERSET_VERSION dans .env
# 2. Reconstruire l'image
docker-compose build superset

# 3. Redémarrer
docker-compose up -d superset

# 4. Mettre à jour la base de données
docker exec superset superset db upgrade
```

## Dépannage

### Superset ne démarre pas

```bash
# Vérifier les logs
docker-compose logs superset

# Vérifier que PostgreSQL est prêt
docker-compose ps database

# Vérifier que Redis est prêt
docker-compose ps redis
```

### Erreur de connexion à la base de données

Vérifiez que :
- Les variables `POSTGRES_*` sont correctement définies dans `.env`
- Le conteneur database est démarré et healthy
- Les mots de passe correspondent

### Problème avec https-portal

Assurez-vous que :
- Le réseau `gateway` existe et est partagé
- `VIRTUAL_HOST` est configuré dans `.env`
- `VIRTUAL_PORT=8088` est défini dans docker-compose.yaml

## Ressources

- [Documentation Apache Superset](https://superset.apache.org/docs/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)

