#!/bin/bash
echo "This will stop and prune all docker containers"
echo "          delete your existing database (./data/)"
echo "          delete your recordings        (./record/)"
echo "          delete your drive files       (./drive/)"
echo "          delete your certs files       (./nginx/ssl/)"
echo "          delete your .env config       (.env)"
echo ""
read -p "Are you sure? [y/n] " -n 1 -r
echo ""   # (optional) move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]; then # do dangerous stuff
 docker-compose down
 #chmod -R +x -- ./init
 sudo rm -r -f ./init/ ./data/ ./drive/ ./record/ ./nginx/ssl/ .env
 echo "Pruning all stopped containers"
 docker container prune
fi

