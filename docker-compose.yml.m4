dnl This is a YAML template file.  Simply translate it with m4 to create
dnl a standard configuration.  Customizations can and should be added in .env
dnl by setting the appropriate variables.
dnl
dnl Usage:
dnl   m4 docker-compose.yml.m4 > docker-compose.yml
dnl   ( set -a; source .env; m4 docker-compose.yml.m4 ) > docker-compose.yml
dnl
dnl ----------------------------------------
divert(-1)dnl
define(`read_env', `esyscmd(`printf "%s" "$$1"')')
define(`ifenvelse', `ifelse(read_env(`$1'),, `$2', read_env(`$1'))')

define(`BACKEND_IMAGE',
ifenvelse(`DOCKER_OPENSLIDES_BACKEND_NAME', openslides/openslides-server):dnl
ifenvelse(`DOCKER_OPENSLIDES_BACKEND_TAG', latest))
define(`FRONTEND_IMAGE',
ifenvelse(`DOCKER_OPENSLIDES_FRONTEND_NAME', openslides/openslides-client):dnl
ifenvelse(`DOCKER_OPENSLIDES_FRONTEND_TAG', latest))

define(`PRIMARY_DB', `ifenvelse(`PGNODE_REPMGR_PRIMARY', pgnode1)')

define(`PGBOUNCER_NODELIST',
`ifelse(read_env(`PGNODE_2_ENABLED'), 1, `,pgnode2')`'dnl
ifelse(read_env(`PGNODE_3_ENABLED'), 1, `,pgnode3')')

define(`PROJECT_DIR', ifdef(`PROJECT_DIR',PROJECT_DIR,.))
define(`ADMIN_SECRET_AVAILABLE', `syscmd(`test -f 'PROJECT_DIR`/secrets/adminsecret.env')sysval')
define(`USER_SECRET_AVAILABLE', `syscmd(`test -f 'PROJECT_DIR`/secrets/usersecret.env')sysval')
divert(0)dnl
dnl ----------------------------------------
# This configuration was created from a template file.  Before making changes,
# please make sure that you do not have a process in place that would override
# your changes in the future.  The accompanying .env file might be the correct
# place for customizations instead.
version: '3.4'

x-osserver:
  &default-osserver
  image: BACKEND_IMAGE
  networks:
    - front
    - back
  restart: always
x-osserver-env: &default-osserver-env
    INSTANCE_DOMAIN: "ifenvelse(`INSTANCE_DOMAIN', http://example.com:8000)"
    DEFAULT_FROM_EMAIL: "ifenvelse(`DEFAULT_FROM_EMAIL', noreply@example.com)"
    REDIS_REPLICAS: ifenvelse(`REDIS_RO_SERVICE_REPLICAS', 1)
    SERVER_IS_SECONDARY: # unset
x-pgnode: &default-pgnode
  image: ifenvelse(`DEFAULT_DOCKER_REGISTRY', openslides)/openslides-repmgr:latest
  build: ./repmgr
  networks:
    - dbnet
  labels:
    org.openslides.role: "postgres"
  restart: always
x-pgnode-env: &default-pgnode-env
  REPMGR_RECONNECT_ATTEMPTS: 30
  REPMGR_RECONNECT_INTERVAL: 10
  REPMGR_WAL_ARCHIVE: "ifenvelse(`PGNODE_WAL_ARCHIVING', on)"

services:
  prioserver:
    # This service is the main server service in that it is responsible for
    # database migrations, adding the initial user credentials etc.  However,
    # the direct access to this service's resources is only granted to select,
    # prioritized OpenSlides users or groups.  The general workload is handled
    # by the regular "server" service below.
    << : *default-osserver
    environment:
      << : *default-osserver-env
    command: "gunicorn -w 1 --preload -b 0.0.0.0:8000
      -k uvicorn.workers.UvicornWorker openslides.asgi:application"
    depends_on:
      - postfix
      - pgbouncer
      - redis
      - redis-slave
      - redis-channels
    ifelse(ADMIN_SECRET_AVAILABLE, 0, secrets:, USER_SECRET_AVAILABLE, 0, secrets:)
      ifelse(ADMIN_SECRET_AVAILABLE, 0,- os_admin)
      ifelse(USER_SECRET_AVAILABLE, 0,- os_user)
  server:
    << : *default-osserver
    # Below is the default command.  You can uncomment it to override the
    # number of workers, for example:
    # command: "gunicorn -w 8 --preload -b 0.0.0.0:8000
    #   -k uvicorn.workers.UvicornWorker openslides.asgi:application"
    #
    # Uncomment the following line to use daphne instead of gunicorn:
    # command: "daphne -b 0.0.0.0 -p 8000 openslides.asgi:application"
    depends_on:
      - prioserver
    environment:
      << : *default-osserver-env
      # With this variable set this service will not attempt to prepare the
      # instance by, e.g., running migations.  This is exclusively left up to
      # the main service to avoid conflicts.
      SERVER_IS_SECONDARY: 1
    ifelse(read_env(`OPENSLIDES_BACKEND_SERVICE_REPLICAS'),,,deploy:
      replicas: ifenvelse(`OPENSLIDES_BACKEND_SERVICE_REPLICAS', 1))
  client:
    image: FRONTEND_IMAGE
    restart: always
    depends_on:
      - prioserver
      - server
    networks:
      - front
    ports:
      - "127.0.0.1:ifenvelse(`EXTERNAL_HTTP_PORT', 61000):80"

  pgnode1:
    << : *default-pgnode
    environment:
      << : *default-pgnode-env
      REPMGR_NODE_ID: 1
      REPMGR_PRIMARY: ifelse(PRIMARY_DB, pgnode1, `# This is the primary', PRIMARY_DB)
    volumes:
      - "dbdata1:/var/lib/postgresql"
ifelse(read_env(`PGNODE_2_ENABLED'), 1, `'
  pgnode2:
    << : *default-pgnode
    environment:
      << : *default-pgnode-env
      REPMGR_NODE_ID: 2
      REPMGR_PRIMARY: ifelse(PRIMARY_DB, pgnode2, `# This is the primary', PRIMARY_DB)
    volumes:
      - "dbdata2:/var/lib/postgresql")
ifelse(read_env(`PGNODE_3_ENABLED'), 1, `'
  pgnode3:
    << : *default-pgnode
    environment:
      << : *default-pgnode-env
      REPMGR_NODE_ID: 3
      REPMGR_PRIMARY: ifelse(PRIMARY_DB, pgnode3, `# This is the primary', PRIMARY_DB)
    volumes:
      - "dbdata3:/var/lib/postgresql")

  pgbouncer:
    environment:
      - PG_NODE_LIST=pgnode1`'PGBOUNCER_NODELIST
    image: ifenvelse(`DEFAULT_DOCKER_REGISTRY', openslides)/openslides-pgbouncer:latest
    build: ./pgbouncer
    restart: always
    networks:
      back:
        aliases:
          - db
          - postgres
      dbnet:
  postfix:
    image: ifenvelse(`DEFAULT_DOCKER_REGISTRY', openslides)/openslides-postfix:latest
    build: ./postfix
    restart: always
    environment:
      MYHOSTNAME: "ifenvelse(`POSTFIX_MYHOSTNAME', localhost)"
      RELAYHOST: "ifenvelse(`POSTFIX_RELAYHOST', localhost)"
    networks:
      - back
  redis:
    image: redis:alpine
    restart: always
    networks:
      back:
        aliases:
          - rediscache
  redis-slave:
    image: redis:alpine
    restart: always
    command: ["redis-server", "--save", "", "--slaveof", "redis", "6379"]
    depends_on:
      - redis
    networks:
      back:
        aliases:
          - rediscache-slave
    ifelse(read_env(`REDIS_RO_SERVICE_REPLICAS'),,,deploy:
      replicas: ifenvelse(`REDIS_RO_SERVICE_REPLICAS', 1))
  redis-channels:
    image: redis:alpine
    restart: always
    networks:
      back:
  media:
    image: ifenvelse(`DEFAULT_DOCKER_REGISTRY', openslides)/openslides-media-service:latest
    build: https://github.com/OpenSlides/openslides-media-service.git
    environment:
      - CHECK_REQUEST_URL=server:8000/check-media/
    restart: always
    networks:
      front:
      back:
    # Override command to run more workers per task
    # command: ["gunicorn", "-w", "4", "--preload", "-b",
    #   "0.0.0.0:8000", "src.mediaserver:app"]

volumes:
  dbdata1:
ifelse(read_env(`PGNODE_2_ENABLED'), 1, `  dbdata2:')
ifelse(read_env(`PGNODE_3_ENABLED'), 1, `  dbdata3:')

networks:
  front:
  back:
  dbnet:

secrets:
  ifelse(ADMIN_SECRET_AVAILABLE, 0,os_admin:
    file: ./secrets/adminsecret.env)
  ifelse(USER_SECRET_AVAILABLE, 0,os_user:
    file: ./secrets/usersecret.env)

# vim: set sw=2 et:
