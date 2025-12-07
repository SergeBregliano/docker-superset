"""
Module de redirection personnalisée pour Superset.
Redirige les utilisateurs vers des dashboards spécifiques selon leur nom d'utilisateur ou leur rôle.
Les URLs peuvent inclure des paramètres de requête pour contrôler le panneau de filtres :
- ?expand_filters=0 (replié) ou ?expand_filters=1 (déplié)
- ?show_filters=0 (masqué) ou ?show_filters=1 (affiché)
"""
import os
import json


def get_user_dashboard_redirects():
    """
    Charge la configuration des redirections depuis les variables d'environnement.
    
    Returns:
        dict: Dictionnaire des redirections {"username": "/superset/dashboard/ID/", ...}
    """
    redirects_env = os.environ.get("SUPERSET_USER_DASHBOARD_REDIRECTS", "{}")
    try:
        return json.loads(redirects_env) if redirects_env else {}
    except (json.JSONDecodeError, ValueError) as e:
        print(f"Warning: Invalid JSON in SUPERSET_USER_DASHBOARD_REDIRECTS: {e}")
        return {}


def get_default_home_page():
    """Retourne la page d'accueil par défaut."""
    return os.environ.get("SUPERSET_DEFAULT_HOME_PAGE", "/superset/welcome/")


def create_custom_index_view_mutator():
    """
    Crée la fonction mutator pour personnaliser l'application Flask.
    Compatible avec Superset 5.0.0+ (utilise FLASK_APP_MUTATOR).
    
    Returns:
        function: Fonction mutator pour Flask
    """
    redirects = get_user_dashboard_redirects()
    default_page = get_default_home_page()
    
    def mutate_app(app):
        """
        Fonction mutator pour personnaliser l'application Flask.
        Redirige les utilisateurs vers des dashboards spécifiques selon leur nom d'utilisateur ou leur rôle.
        """
        try:
            from flask import redirect, g, request
            from flask_appbuilder import expose, IndexView
            from superset.extensions import appbuilder
            from superset import security_manager
            from superset.utils.core import get_user_id
            from superset.superset_typing import FlaskResponse
            
            # Capturer les variables dans la closure
            user_redirects = redirects.copy()
            default_home = default_page
            
            def check_and_redirect():
                """Vérifie si l'utilisateur doit être redirigé vers un dashboard"""
                # Vérifier si l'utilisateur est authentifié
                if not hasattr(g, 'user') or not g.user:
                    return None
                
                # Vérifier si l'utilisateur n'est pas anonyme (a un attribut username)
                if not hasattr(g.user, 'username'):
                    return None
                
                # Vérifier que l'utilisateur est vraiment connecté
                try:
                    if not get_user_id():
                        return None
                except Exception:
                    return None
                
                username = g.user.username
                
                # Vérifier d'abord par utilisateur
                if username in user_redirects:
                    return user_redirects[username]
                
                # Ensuite par rôle
                try:
                    user_roles = security_manager.get_user_roles()
                    for role in user_roles:
                        if role.name in user_redirects:
                            return user_redirects[role.name]
                except Exception:
                    pass
                
                return None
            
            # Intercepter les requêtes vers la racine et welcome
            @app.before_request
            def intercept_redirects():
                if request.method == 'GET':
                    path = request.path
                    if path in ('/', '/superset/welcome/', '/superset/welcome'):
                        dashboard_url = check_and_redirect()
                        if dashboard_url:
                            return redirect(dashboard_url)
            
            class CustomIndexView(IndexView):
                @expose("/")
                def index(self) -> FlaskResponse:
                    if not hasattr(g, 'user') or not g.user:
                        return redirect("/login/")
                    
                    # Vérifier si l'utilisateur n'est pas anonyme
                    if not hasattr(g.user, 'username'):
                        return redirect("/login/")
                    
                    dashboard_url = check_and_redirect()
                    if dashboard_url:
                        return redirect(dashboard_url)
                    
                    return redirect(default_home)
            
            # Définir la vue personnalisée
            appbuilder.indexview = CustomIndexView
            
        except Exception as e:
            import traceback
            print(f"Warning: Could not load custom index view: {e}")
            print(f"Traceback: {traceback.format_exc()}")
    
    return mutate_app
