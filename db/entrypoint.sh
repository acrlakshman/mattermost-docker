#!/bin/bash

: ${ENV_SECRETS_DIR:=/run/secrets}

env_secret_debug()
{
    if [ ! -z "$ENV_SECRETS_DEBUG" ]; then
        echo -e "\033[1m$@\033[0m"
    fi
}

# usage: env_secret_expand VAR
#    ie: env_secret_expand 'XYZ_DB_PASSWORD'
# (will check for "$XYZ_DB_PASSWORD" variable value for a placeholder that defines the
#  name of the docker secret to use instead of the original value. For example:
# XYZ_DB_PASSWORD=DOCKERSECRET:my-db.secret
env_secret_expand() {
    var="$1"
    eval val=\$$var
    if secret_name=$(expr match "$val" "DOCKERSECRET:\([^}]\+\)$"); then
        secret="${ENV_SECRETS_DIR}/${secret_name}"
        env_secret_debug "Secret file for $var: $secret"
        if [ -f "$secret" ]; then
            val=$(cat "${secret}")
            export "$var"="$val"
            env_secret_debug "Expanded variable: $var=$val"
        else
            env_secret_debug "Secret file does not exist! $secret"
        fi
    fi
}

env_secrets_expand() {
    for env_var in $(printenv | cut -f1 -d"=")
    do
        env_secret_expand $env_var
    done

    if [ ! -z "$ENV_SECRETS_DEBUG" ]; then
        echo -e "\n\033[1mExpanded environment variables\033[0m"
        printenv
    fi
}

env_secrets_expand

# if wal-e backup is not enabled, use minimal wal-e logging to reduce disk space
export WAL_LEVEL=${WAL_LEVEL:-minimal}
export ARCHIVE_MODE=${ARCHIVE_MODE:-off}
export ARCHIVE_TIMEOUT=${ARCHIVE_TIMEOUT:-60}

function update_conf () {
  wal=$1
  # PGDATA is defined in upstream postgres dockerfile
  config_file=$PGDATA/postgresql.conf

  # Check if configuration file exists. If not, it probably means that database is not initialized yet
  if [ ! -f $config_file ]; then
    return
  fi
  # Reinitialize config
  sed -i "s/log_timezone =.*$//g" $PGDATA/postgresql.conf
  sed -i "s/timezone =.*$//g" $PGDATA/postgresql.conf
  sed -i "s/wal_level =.*$//g" $config_file
  sed -i "s/archive_mode =.*$//g" $config_file
  sed -i "s/archive_timeout =.*$//g" $config_file
  sed -i "s/archive_command =.*$//g" $config_file

  # Configure wal-e
  if [ "$wal" = true ] ; then
    /docker-entrypoint-initdb.d/setup-wale.sh
  fi
  echo "log_timezone = $DEFAULT_TIMEZONE" >> $config_file
  echo "timezone = $DEFAULT_TIMEZONE" >> $config_file
}

if [ "${1:0:1}" = '-' ]; then
  set -- postgres "$@"
fi

if [ "$1" = 'postgres' ]; then
  # Check wal-e variables
  wal_enable=true
  VARS=(AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY WALE_S3_PREFIX AWS_REGION)
  for v in ${VARS[@]}; do
    if [ "${!v}" = "" ]; then
      echo "$v is required for Wal-E but not set. Skipping Wal-E setup."
      wal_enable=false
    fi
  done

  # Setup wal-e env variables
  if [ "$wal_enable" = true ] ; then
    for v in ${VARS[@]}; do
      export $v="${!v}"
    done
    WAL_LEVEL=archive
    ARCHIVE_MODE=on
  fi

  # Update postgresql configuration
  update_conf $wal_enable

  # Run the postgresql entrypoint
  docker-entrypoint.sh postgres
fi
