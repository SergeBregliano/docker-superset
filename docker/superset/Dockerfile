ARG SUPERSET_VERSION=5.0.0
FROM apache/superset:${SUPERSET_VERSION}

USER root

# Installer les dépendances système nécessaires
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        gcc \
        g++ \
        build-essential \
        postgresql-client && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Installer les dépendances Python
RUN /app/.venv/bin/python -m ensurepip --upgrade && \
    /app/.venv/bin/python -m pip install --upgrade --no-cache-dir pip && \
    /app/.venv/bin/python -m pip install --no-cache-dir \
        psycopg2-binary \
        redis \
        prophet \
        plotly && \
    /app/.venv/bin/python -c "import psycopg2; print('psycopg2 installed successfully')" && \
    /app/.venv/bin/python -c "import redis; print('redis installed successfully')" && \
    /app/.venv/bin/python -c "import prophet; print('prophet installed successfully')" && \
    /app/.venv/bin/python -c "import plotly; print('plotly installed successfully')"

USER superset