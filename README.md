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

## Mise à jour (migration de version)

Lors d’un passage à une nouvelle version majeure de Superset (par ex. 5.x → 6.x) :

1. **Sauvegarder la base métadonnées**  
   Faire un backup complet PostgreSQL (base `superset` et éventuellement `user_data`) avant toute mise à jour. Utiliser par ex. le script `./backup-restore.sh` ou `pg_dump`.

2. **Passer à la nouvelle version**  
   Dans `.env`, définir `SUPERSET_VERSION=6.0.0` (ou la version cible). Optionnel : `BUILD_TRANSLATIONS=true` pour inclure les traductions dans l’image ; `INCLUDE_CHROMIUM=true` uniquement si vous utilisez Alertes & Rapports avec captures d’écran.

3. **Reconstruire et redémarrer**  
   ```bash
   docker compose down
   docker compose build --no-cache
   docker compose up -d
   ```

4. **Migrations et initialisation**  
   Une fois le conteneur prêt, exécuter (ou relancer le script d’init) :
   ```bash
   ./setup.sh
   ```
   Ce script lance `superset db upgrade`, `superset init` et la création de l’admin si besoin. En 6.0+, `FAB_ADD_SECURITY_API = True` est requis pour la gestion des rôles dans l’UI (déjà présent dans `superset_config.py`).

5. **Vérifications**  
   Tester la page d’accueil, les redirections personnalisées par utilisateur/rôle, et l’affichage des dashboards / graphiques ECharts.

## Traductions

Superset est configuré pour utiliser le français par défaut (`BABEL_DEFAULT_LOCALE=fr`).

### Traductions personnalisées

Vous pouvez utiliser vos propres traductions en montant un volume dans le conteneur. Placez vos fichiers de traduction compilés (`.mo`) dans le dossier suivant :

```
${DATA_PATH}/superset/translations/fr/LC_MESSAGES/messages.mo
```

Le volume est automatiquement monté dans le conteneur à `/app/superset/translations/fr/`, remplaçant les traductions françaises par défaut.

**Structure attendue :**
```
appData/superset/translations/
└── fr/
    └── LC_MESSAGES/
        └── messages.json
        └── messages.mo
        └── messages.po
```

**Note :** Pour modifier les fichiers de traduction, ne pas hésiter à utiliser [Poedit](https://poedit.net/).

## Interface utilisateur en français

Pour qu'un utilisateur puisse disposer d'une interface en français, il faut que son rôle possède le droit ``can language pack Superset``.



## Configuration

### Variables d'environnement principales

| Variable | Description | Défaut |
|----------|-------------|--------|
| `SUPERSET_VERSION` | Version de Superset | `6.0.0` |
| `SUPERSET_SECRET_KEY` | Clé secrète (OBLIGATOIRE) | - |
| `POSTGRES_PASSWORD` | Mot de passe PostgreSQL | - |
| `REDIS_PASSWORD` | Mot de passe Redis | - |
| `VIRTUAL_HOST` | Domaine pour https-portal | `localhost` |
| `SUPERSET_ADMIN_PASSWORD` | Mot de passe admin | - |
| `SUPERSET_USER_DASHBOARD_REDIRECTS` | Redirections personnalisées par utilisateur/rôle (format JSON) | `{}` |
| `SUPERSET_DEFAULT_HOME_PAGE` | Page d'accueil par défaut après connexion | `/superset/welcome/` |
| `BUILD_TRANSLATIONS` | Inclure les traductions dans l'image (recommandé pour le français) | `true` |
| `INCLUDE_CHROMIUM` | Inclure Chromium pour Alertes & Rapports (screenshots) | `false` |

### Redirection personnalisée vers les dashboards

Vous pouvez configurer Superset pour rediriger automatiquement certains utilisateurs ou rôles vers des dashboards spécifiques après leur connexion.

**Configuration dans `.env` :**

```bash
# Redirections par utilisateur ou par rôle
# Format JSON: {"username": "/superset/dashboard/ID/", "role_name": "/superset/dashboard/ID/"}
SUPERSET_USER_DASHBOARD_REDIRECTS={"admin": "/superset/dashboard/1/", "user1": "/superset/dashboard/5/", "Gamma": "/superset/dashboard/10/"}

# Dashboard par défaut si aucune correspondance n'est trouvée
SUPERSET_DEFAULT_HOME_PAGE=/superset/welcome/
```

**Exemples :**

- **Rediriger un utilisateur spécifique :**
  
  ```bash
  SUPERSET_USER_DASHBOARD_REDIRECTS={"user1": "/superset/dashboard/3/"}
  ```
  
- **Rediriger avec panneau de filtres replié :**
  
  ```bash
  SUPERSET_USER_DASHBOARD_REDIRECTS={"user1": "/superset/dashboard/3/?expand_filters=0"}
  ```
  
- **Rediriger avec panneau de filtres masqué :**
  
  ```bash
  SUPERSET_USER_DASHBOARD_REDIRECTS={"user1": "/superset/dashboard/3/?show_filters=0"}
  ```
  
- **Rediriger tous les utilisateurs d'un rôle :**
  
  ```bash
  SUPERSET_USER_DASHBOARD_REDIRECTS={"Gamma": "/superset/dashboard/10/"}
  ```
  
- **Combiner utilisateurs et rôles :**
  ```bash
  SUPERSET_USER_DASHBOARD_REDIRECTS={"admin": "/superset/dashboard/1/", "Gamma": "/superset/dashboard/10/"}
  ```

**Priorité :**

- Les redirections par utilisateur ont la priorité sur les redirections par rôle
- Si aucune correspondance n'est trouvée, l'utilisateur est redirigé vers `SUPERSET_DEFAULT_HOME_PAGE`

**Paramètres de filtres disponibles :**

- `expand_filters=0` : Panneau de filtres replié
- `expand_filters=1` : Panneau de filtres déplié
- `show_filters=0` : Panneau de filtres masqué
- `show_filters=1` : Panneau de filtres affiché

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

- **`appData/database/postgres`**
  - Dashboards (tableaux de bord)
  - Charts (graphiques)
  - Datasources (sources de données)
  - Users (utilisateurs)
  - Roles (rôles et permissions)
  - Logs d'activité

### Séparation des bases de données PostgreSQL

Les métadonnées Superset et les données utilisateurs sont séparées dans deux bases de données PostgreSQL différentes :

- **Base `superset`** (métadonnées) : 
  - Dashboards, charts, utilisateurs, rôles, permissions, etc.
  - Tables créées automatiquement par Superset
  - **Ne pas modifier manuellement !**
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

## Graphiques GeoJSON

- Pré-requis : disposer de la librairie [GDAL](https://gdal.org) pour pouvoir utiliser ogr2ogr

- Vérifier la structure du fichier GeoJSON en le chargeant sur le site https://geojson.io/ ou https://mapshaper.org/

- Charger le fichier GeoJSON dans une table de la base de données

  ```shell
  ogr2ogr -f "PostgreSQL" \
    PG:"host=localhost dbname=votre_db user=votre_user password=votre_password" \
    votre_fichier.geojson \
    -nln nom_de_la_table \
    -overwrite
  ```

- Ensuite, deux méthodes permettent d'utiliser les fichiers GeoJSON afin d'établir des graphiques deck.gl geojson :

  - Requête SQL personnalisée pour le champ GeoJson Column

    ```sql
    json_build_object(
        'type', 'Feature',
        'geometry', ST_AsGeoJSON(ST_Transform(wkb_geometry, 4326))::json,
          'properties', json_build_object()
    )::text
    ```

  - Requête SQL pour un Dataset virtuel

    ```sql
    SELECT *, 
        json_build_object(
            'type', 'Feature',
            'geometry', ST_AsGeoJSON(ST_Transform((ST_Dump(wkb_geometry)).geom::geometry, 4326))::json,
            'properties', json_build_object()
        )::text AS geojson
    FROM nom_de_la_table;
    ```

## Sauvegarde et restauration

### Vue d'ensemble

Le système de sauvegarde couvre les deux bases de données :

- Base `superset` : métadonnées (dashboards, charts, utilisateurs, rôles, etc.)
- Base `user_data` : données utilisateurs (CSV uploadés, tables créées manuellement)

### Méthodes de sauvegarde

#### 1. Sauvegarde automatique (recommandée)

Un service Docker `backup` est configuré pour effectuer des sauvegardes automatiques quotidiennes.

**Configuration :**
- **Fréquence** : Quotidienne (`@daily` à minuit)
- **Rétention** : 7 dernières sauvegardes conservées automatiquement
- **Emplacement** : `appData/backups/` (monté dans le conteneur)

**Vérifier les sauvegardes automatiques :**
```bash
# Lister les sauvegardes automatiques
ls -lh appData/backups/

# Vérifier les logs du service backup
docker-compose logs backup
```

**Personnaliser la fréquence :**
Modifiez la variable `SCHEDULE` dans `docker-compose.yaml` :
- `@daily` : Tous les jours à minuit
- `@weekly` : Une fois par semaine
- `0 2 * * *` : Tous les jours à 2h du matin (format cron)
- `0 */6 * * *` : Toutes les 6 heures

**Personnaliser la rétention :**
Modifiez `BACKUP_NUM_KEEP` dans `docker-compose.yaml` (nombre de sauvegardes à conserver).

#### 2. Sauvegarde et restauration manuelles

Un script `backup-restore.sh` permet de gérer facilement les sauvegardes et restaurations.

**Utilisation :**

```bash
# Exécuter le script
bash ./backup-restore.sh
# Ou simplement (si le fichier est exécutable)
./backup-restore.sh
```

Le script propose un menu avec les options suivantes :

1. **Effectuer une sauvegarde** : Lance une sauvegarde manuelle des deux bases (`superset` et `user_data`)
2. **Restaurer une sauvegarde** : Liste toutes les sauvegardes disponibles (groupées par date) et permet de restaurer une ou les deux bases
3. **Quitter**

**Fonctionnalités :**
- Détection automatique des sauvegardes "latest" et des sauvegardes groupées par date
- Restauration automatique des deux bases si les sauvegardes correspondent
- Vérification et correction automatique des permissions du répertoire de backup
- Arrêt/redémarrage automatique de Superset lors des restaurations

**Note :** Le script utilise le conteneur `prodrigestivill/postgres-backup-local` pour effectuer les sauvegardes, garantissant la cohérence avec les sauvegardes automatiques.

### Restauration

#### Restaurer les bases de données PostgreSQL

```bash
# Arrêter Superset
docker-compose stop superset

# Restaurer la base superset
gunzip < appData/backups/postgres_superset_YYYYMMDD_HHMMSS.sql.gz | \
  docker exec -i ${MAIN_CONTAINER_NAME:-superset}_database \
  psql -U ${POSTGRES_USER:-superset} ${POSTGRES_DB:-superset}

# Restaurer la base user_data (si la sauvegarde existe)
if [ -f appData/backups/postgres_user_data_YYYYMMDD_HHMMSS.sql.gz ]; then
  gunzip < appData/backups/postgres_user_data_YYYYMMDD_HHMMSS.sql.gz | \
    docker exec -i ${MAIN_CONTAINER_NAME:-superset}_database \
    psql -U ${POSTGRES_USER:-superset} ${POSTGRES_USERDATA_DB:-user_data}
fi

# Redémarrer Superset
docker-compose start superset
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

