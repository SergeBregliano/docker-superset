import os

# Database configuration
POSTGRES_USER = os.environ.get("DATABASE_USER", "superset")
POSTGRES_PASSWORD = os.environ.get("DATABASE_PASSWORD", "")
POSTGRES_HOST = os.environ.get("DATABASE_HOST", "database")
POSTGRES_PORT = os.environ.get("DATABASE_PORT", "5432")
POSTGRES_DB = os.environ.get("DATABASE_DB", "superset")

# Configuration de la base de données
# Superset utilise cette base pour ses métadonnées (dashboards, charts, users, etc.)
SQLALCHEMY_DATABASE_URI = (
    f"postgresql+psycopg2://{POSTGRES_USER}:{POSTGRES_PASSWORD}"
    f"@{POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_DB}"
)

# Les exemples seront chargés dans la base user_data (données utilisateurs)
POSTGRES_USERDATA_DB = os.environ.get("POSTGRES_USERDATA_DB", "user_data")
SQLALCHEMY_EXAMPLES_URI = (
    f"postgresql+psycopg2://{POSTGRES_USER}:{POSTGRES_PASSWORD}"
    f"@{POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_USERDATA_DB}"
)

# Redis configuration for cache and Celery
REDIS_HOST = os.environ.get("REDIS_HOST", "redis")
REDIS_PORT = os.environ.get("REDIS_PORT", "6379")
REDIS_DB = int(os.environ.get("REDIS_DB", "0"))
REDIS_PASSWORD = os.environ.get("REDIS_PASSWORD", "")

# Redis connection string
REDIS_URL = f"redis://:{REDIS_PASSWORD}@{REDIS_HOST}:{REDIS_PORT}/{REDIS_DB}" if REDIS_PASSWORD else f"redis://{REDIS_HOST}:{REDIS_PORT}/{REDIS_DB}"

# Cache configuration
CACHE_CONFIG = {
    "CACHE_TYPE": "RedisCache",
    "CACHE_DEFAULT_TIMEOUT": 300,
    "CACHE_KEY_PREFIX": "superset_",
    "CACHE_REDIS_URL": REDIS_URL,
}

# Celery configuration for async tasks
class CeleryConfig:
    broker_url = REDIS_URL
    result_backend = REDIS_URL
    accept_content = ["json"]
    task_serializer = "json"
    result_serializer = "json"
    timezone = "UTC"
    enable_utc = True

CELERY_CONFIG = CeleryConfig

# Application name
APP_NAME = os.environ.get("SUPERSET_APP_NAME", "Superset")

# Logo customization
# APP_ICON: Chemin vers le logo principal
# Format: chemin relatif depuis /app/superset/static/assets/images/
# Exemple: "/static/assets/images/custom-logo.png" ou "/static/assets/custom/logo.png"
APP_ICON = os.environ.get("SUPERSET_APP_ICON", "/static/assets/images/superset-logo-horiz.png")

# FAVICONS: Liste des favicons
# Format JSON: [{"href": "/static/assets/custom/favicon.png"}]
# Ou format simple: /static/assets/custom/favicon.png
import json
FAVICONS_ENV = os.environ.get("SUPERSET_FAVICONS", "")
try:
    FAVICONS = json.loads(FAVICONS_ENV) if FAVICONS_ENV else [{"href": "/static/assets/images/favicon.png"}]
except (json.JSONDecodeError, ValueError):
    FAVICONS = [{"href": FAVICONS_ENV}] if FAVICONS_ENV else [{"href": "/static/assets/images/favicon.png"}]

# Security
SECRET_KEY = os.environ.get("SUPERSET_SECRET_KEY", "")
ENABLE_PROXY_FIX = True
PROXY_FIX_CONFIG = {
    "x_for": 1,
    "x_proto": 1,
    "x_host": 1,
    "x_port": 1,
    "x_prefix": 1,
}

# Production settings
PREVENT_UNSAFE_DB_CONNECTIONS = True
TALISMAN_ENABLED = True
TALISMAN_CONFIG = {
    "content_security_policy": {
        "default-src": ["'self'", "'unsafe-inline'", "'unsafe-eval'"],
        "img-src": ["'self'", "data:", "https:"],
        "worker-src": ["'self'", "blob:"],
        "connect-src": ["'self'"],
        "frame-ancestors": ["'none'"],
    },
    "force_https": False,  # Let https-portal handle HTTPS
}

# Localization
BABEL_DEFAULT_LOCALE = os.environ.get("SUPERSET_BABEL_DEFAULT_LOCALE", "fr")
BABEL_DEFAULT_FOLDER = "superset/translations"
# LANGUAGES = {
#     "en": {"flag": "us", "name": "English"},
#     "fr": {"flag": "fr", "name": "Français"},
# }

# Feature flags for translations
FEATURE_FLAGS = {
    "ENABLE_REACT_TRANSLATIONS": True,
    "ENABLE_TEMPLATE_PROCESSING": True,
    # Force French locale for better translation coverage
    "LOCALIZATION": True,
}

# Additional Babel configuration
BABEL_CONFIG = {
    "BABEL_DEFAULT_LOCALE": BABEL_DEFAULT_LOCALE,
    "BABEL_DEFAULT_TIMEZONE": "UTC",
}

# Performance
ROW_LIMIT = 50000
VIZ_ROW_LIMIT = 10000
SUPERSET_WEBSERVER_TIMEOUT = 60