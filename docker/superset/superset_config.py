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

# Application root (for reverse proxy with subpath)
# If Superset is accessed via http://domain/superset/, set this to "/superset"
APPLICATION_ROOT = os.environ.get("SUPERSET_APPLICATION_ROOT", "/superset")

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
        "img-src": ["'self'", "data:", "https:", "https://*.tile.openstreetmap.org"],
        "font-src": ["'self'", "data:", "https:"],  # Allow data: for base64 fonts (required for superset-chat)
        "style-src": ["'self'", "'unsafe-inline'", "https:"],  # Allow inline styles
        "worker-src": ["'self'", "blob:"],
        "connect-src": [
            "'self'",
            "https://*.tile.openstreetmap.org",
            "https://a.tile.openstreetmap.org",
            "https://b.tile.openstreetmap.org",
            "https://c.tile.openstreetmap.org",
            "https://api.mapbox.com",
            "https://*.mapbox.com"
        ],
        "frame-ancestors": ["'none'"],
    },
    "force_https": False,  # Let https-portal handle HTTPS
}

# Mapbox configuration
MAPBOX_API_KEY = os.environ.get("MAPBOX_API_KEY", None)
# OpenStreetMap configuration (prévision v6.0.0)
DECKGL_BASE_MAP = [
    ["https://tile.openstreetmap.org/{z}/{x}/{y}.png", "OpenStreetMap"]
]

# Localization
BABEL_DEFAULT_LOCALE = os.environ.get("SUPERSET_BABEL_DEFAULT_LOCALE", "fr")

# LANGUAGES = {
#     "en": {"flag": "us", "name": "English"},
#     "fr": {"flag": "fr", "name": "Français"},
# }

# Feature flags for translations
FEATURE_FLAGS = {
    "ENABLE_REACT_TRANSLATIONS": True,
    "ENABLE_TEMPLATE_PROCESSING": True,
    "ENABLE_JAVASCRIPT_CONTROLS": True,
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

# ============================================
# Superset Chat Plugin Configuration
# ============================================
import logging

logger = logging.getLogger()

# Flask-AppBuilder Init Hook for custom views
def init_custom_views(app):
    """Initialize custom views after Flask app is created"""
    try:
        from superset_chat.ai_superset_assistant import AISupersetAssistantView

        # Get the appbuilder instance
        appbuilder = app.appbuilder

        # Create a subclass with a custom route_base
        # Include APPLICATION_ROOT in route_base if it's set (for reverse proxy)
        app_root = APPLICATION_ROOT.rstrip('/') if APPLICATION_ROOT else ''
        route_base_path = f"{app_root}/ai_superset_assistant" if app_root else "/ai_superset_assistant"
        
        class CustomAISupersetAssistantView(AISupersetAssistantView):
            route_base = route_base_path
            
            def assistant(self):
                """Override the assistant method to fix hardcoded URLs in the HTML content"""
                # Call the parent method to get the HTML content
                original_result = super().assistant()
                
                # If it's a string (HTML), replace all hardcoded URLs
                if isinstance(original_result, str):
                    # Replace old route with new route_base (all occurrences)
                    old_route = "/aisupersetassistantview"
                    new_route = route_base_path
                    # Replace all occurrences (case-insensitive to be safe)
                    import re
                    fixed_content = re.sub(
                        re.escape(old_route),
                        new_route,
                        original_result,
                        flags=re.IGNORECASE
                    )
                    logger.info(f"   Fixed URLs: {old_route} -> {new_route}")
                    return fixed_content
                
                return original_result

        # Register the view in "Custom Tools" category
        # Flask-AppBuilder will automatically create the category if it doesn't exist
        category_name = "Custom Tools"
        
        appbuilder.add_view(
            CustomAISupersetAssistantView,
            "AI Superset Assistant",
            icon="fa-robot",
            category=category_name,
            category_icon="fa-wrench"  # Icon for the category menu
        )

        logger.info("✅ AI Superset Assistant plugin registered successfully!")
        logger.info(f"   Category: {category_name} (created automatically if needed)")
        logger.info(f"   View name: AI Superset Assistant")
        logger.info(f"   Route base: {route_base_path}")
        logger.info(f"   Accessible at: {route_base_path}/ or {route_base_path}/assistant")
        logger.info(f"   Note: In Superset 5.0.0, React menu may not show Flask-AppBuilder categories")

    except Exception as e:
        logger.error(f"❌ Failed to register AI Superset Assistant plugin: {e}")
        import traceback
        logger.error(traceback.format_exc())

FLASK_APP_MUTATOR = lambda app: init_custom_views(app)