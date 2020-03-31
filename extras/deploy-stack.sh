
mkdir -p volumes/app/mattermost/config
mkdir -p volumes/app/mattermost/data
mkdir -p volumes/app/mattermost/logs
mkdir -p volumes/app/mattermost/plugins
mkdir -p volumes/app/mattermost/client_plugins

chown -R 2000:2000 volumes/app/mattermost

echo "user" | docker secret create mm_db_user -
echo "password" | docker secret create mm_db_password -
echo "mattermost" | docker secret create mm_db_name -

docker stack deploy -c docker-stack.yml mm
