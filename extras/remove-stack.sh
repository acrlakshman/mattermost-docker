rm -rf volumes
docker stack rm mm
docker secret rm mm_db_user mm_db_password mm_db_name
#docker volume prune
