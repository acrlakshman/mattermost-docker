#!/bin/sh

# Function to generate a random salt
generate_salt() {
	tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 48 | head -n 1
}

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

# Read environment variables or set default values
DB_HOST=${DB_HOST:-db}
DB_PORT_NUMBER=${DB_PORT_NUMBER:-5432}
MM_DBNAME=${MM_DBNAME:-mattermost}
MM_CONFIG=${MM_CONFIG:-/mattermost/config/config.json}

_1=$(echo "$1" | awk  '{ s=substr($0, 0, 1); print s; }' )
if [ "$_1" = '-' ]; then
	set -- mattermost "$@"
fi

if [ "$1" = 'mattermost' ]; then
	# Check CLI args for a -config option
	for ARG in "$@"; do
		case "$ARG" in
			-config=*) MM_CONFIG=${ARG#*=};;
		esac
	done

	if [ ! -f "$MM_CONFIG" ]; then
		# If there is no configuration file, create it with some default values
		echo "No configuration file $MM_CONFIG"
		echo "Creating a new one"
		# Copy default configuration file
		cp /config.json.save "$MM_CONFIG"
		# Substitute some parameters with jq
		jq '.ServiceSettings.ListenAddress = ":8000"' "$MM_CONFIG" > "$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
		jq '.LogSettings.EnableConsole = true' "$MM_CONFIG" > "$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
		jq '.LogSettings.ConsoleLevel = "ERROR"' "$MM_CONFIG" > "$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
		jq '.FileSettings.Directory = "/mattermost/data/"' "$MM_CONFIG" > "$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
		jq '.FileSettings.EnablePublicLink = true' "$MM_CONFIG" > "$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
		jq ".FileSettings.PublicLinkSalt = \"$(generate_salt)\"" "$MM_CONFIG" > "$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
		jq '.EmailSettings.SendEmailNotifications = false' "$MM_CONFIG" > "$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
		jq '.EmailSettings.FeedbackEmail = ""' "$MM_CONFIG" > "$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
		jq '.EmailSettings.SMTPServer = ""' "$MM_CONFIG" > "$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
		jq '.EmailSettings.SMTPPort = ""' "$MM_CONFIG" > "$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
		jq ".EmailSettings.InviteSalt = \"$(generate_salt)\"" "$MM_CONFIG" > "$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
		jq ".EmailSettings.PasswordResetSalt = \"$(generate_salt)\"" "$MM_CONFIG" > "$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
		jq '.RateLimitSettings.Enable = true' "$MM_CONFIG" > "$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
		jq '.SqlSettings.DriverName = "postgres"' "$MM_CONFIG" > "$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
		jq ".SqlSettings.AtRestEncryptKey = \"$(generate_salt)\"" "$MM_CONFIG" > "$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
		jq '.PluginSettings.Directory = "/mattermost/plugins/"' "$MM_CONFIG" > "$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
	else
		echo "Using existing config file $MM_CONFIG"
	fi

	# Configure database access
	if [ -z "$MM_SQLSETTINGS_DATASOURCE" ] && [ -n "$MM_USERNAME" ] && [ -n "$MM_PASSWORD" ]; then
		echo "Configure database connection..."
		# URLEncode the password, allowing for special characters
		ENCODED_PASSWORD=$(printf %s "$MM_PASSWORD" | jq -s -R -r @uri)
		export MM_SQLSETTINGS_DATASOURCE="postgres://$MM_USERNAME:$ENCODED_PASSWORD@$DB_HOST:$DB_PORT_NUMBER/$MM_DBNAME?sslmode=disable&connect_timeout=10"
		echo "OK"
	else
		echo "Using existing database connection"
	fi

	# Wait another second for the database to be properly started.
	# Necessary to avoid "panic: Failed to open sql connection pq: the database system is starting up"
	sleep 1

	echo "Starting mattermost"
fi

exec "$@"
