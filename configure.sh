#!/bin/bash
#
# Author: Paul Beyleveld <pbeyleveld at netskope dot com>
# Date:   Jun 2023
#
# This script is to make simplify the process of standing up a guacamole server leveraging
# docker to start a postgres, guacd, guacamole client and nginx container. Access to Guacamole
# is configured to leverage SAML and SAML configuration is captured when using this script.
#

# Check for the existence of .env file
if [ -f .env ]; then
    echo "Error: .env file found. Exiting the script."
    exit 1
fi

# check if docker is running
if ! (docker ps >/dev/null 2>&1)
then
	echo "docker daemon not running, will exit here!"
	exit
fi

# Function to validate the email address using regex
validate_email() {
    local email=$1
    local regex='^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'

    if [[ $email =~ $regex ]]; then
        echo "Valid email address: $email"
        return 0
    else
        echo "Invalid email address: $email"
        return 1
    fi
}

# Function to verify input with the user
verify_input() {

    echo -e "\nYou entered the following:"

    echo "  SAML_ENTITY_ID: $1"
    echo "  SAML_IDP_URL: $2"
    echo "  SAML_IDP_METADATA_URL: $3"
    
    read -p "Is this correct? (y/n): " choice

    case "$choice" in
        [yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}


echo -e "\n- Setting up Guacamole -"
# Capture administrative account to setup guacamole
while true; do
    echo -n "Enter admin account [admin@example.onmicrosoft.com]: "
    read GUACADMIN

    if validate_email "$GUACADMIN"; then
        break
    fi
done

echo "Preparing folder init and creating ./init/initdb.sql"
mkdir ./init >/dev/null 2>&1
chmod -R +x ./init
#docker run --rm guacamole/guacamole /opt/guacamole/bin/initdb.sh --postgres > ./init/initdb.sql
# 001-create-schema.sql  002-create-admin-user.sql
docker run --rm guacamole/guacamole cat /opt/guacamole/postgresql/schema/001-create-schema.sql > ./init/initdb.sql

#generate password for guacamole admin
PWD=$(< /dev/urandom tr -dc '!@#%=+_'A-Za-z0-9 | head -c18; echo)
GUAC_PWD_HASH=$( tr -d '\n' <<<"$PWD" | sha256sum | tr -dc a-f0-9 )
#generate password for postgres
PWD=$(< /dev/urandom tr -dc '!@#%=+_'A-Za-z0-9 | head -c18; echo)

echo "Adding guacamole user $GUACADMIN with password $PWD"

# Add guacamole admin account creation script to ./init/initdb.sql
    cat <<EOF >> "./init/initdb.sql"
    
-- Create default user "$GUACADMIN" with password
INSERT INTO guacamole_entity (name, type) VALUES ('$GUACADMIN', 'USER');
INSERT INTO guacamole_user (entity_id, password_hash, password_salt, password_date)
SELECT
    entity_id,
    decode('${GUAC_PWD_HASH}', 'hex'), 
    null,
    CURRENT_TIMESTAMP
FROM guacamole_entity WHERE name = '$GUACADMIN' AND guacamole_entity.type = 'USER';

-- Grant this user all system permissions
INSERT INTO guacamole_system_permission (entity_id, permission)
SELECT entity_id, permission::guacamole_system_permission_type
FROM (
    VALUES
        ('$GUACADMIN', 'CREATE_CONNECTION'),
        ('$GUACADMIN', 'CREATE_CONNECTION_GROUP'),
        ('$GUACADMIN', 'CREATE_SHARING_PROFILE'),
        ('$GUACADMIN', 'CREATE_USER'),
        ('$GUACADMIN', 'CREATE_USER_GROUP'),
        ('$GUACADMIN', 'ADMINISTER')
) permissions (username, permission)
JOIN guacamole_entity ON permissions.username = guacamole_entity.name AND guacamole_entity.type = 'USER';

-- Grant admin permission to read/update/administer self
INSERT INTO guacamole_user_permission (entity_id, affected_user_id, permission)
SELECT guacamole_entity.entity_id, guacamole_user.user_id, permission::guacamole_object_permission_type
FROM (
    VALUES
        ('$GUACADMIN', '$GUACADMIN', 'READ'),
        ('$GUACADMIN', '$GUACADMIN', 'UPDATE'),
        ('$GUACADMIN', '$GUACADMIN', 'ADMINISTER')
) permissions (username, affected_username, permission)
JOIN guacamole_entity          ON permissions.username = guacamole_entity.name AND guacamole_entity.type = 'USER'
JOIN guacamole_entity affected ON permissions.affected_username = affected.name AND guacamole_entity.type = 'USER'
JOIN guacamole_user            ON guacamole_user.entity_id = affected.entity_id;

EOF

echo "done"

echo -e "\n- Generating Self-Signed Nginx certificate -"
mkdir -p ./nginx/ssl >/dev/null 2>&1
#get hostname
HOSTNAME=$(hostname -A | xargs)
openssl req -nodes -newkey rsa:2048 -new -x509 -keyout nginx/ssl/self-ssl.key -out nginx/ssl/self.cert -subj '/C=US/CN=$HOSTNAME/emailAddress=root@$HOSTNAME'



echo "done"

echo -e "\n- Configure SAML Attributes -"
# Capture SAML attributes
while true; do
    echo -n "Enter Netskope App URL [example: https://app-8443-tenant.eu.npaproxy.goskope.com]: "
    read SAML_ENTITY_ID
    echo -n "Enter SAML IDP Login URL: "
    read SAML_IDP_URL
    echo -n "Enter SAML Metadata URL: "
    read SAML_IDP_METADATA_URL

    if verify_input "$SAML_ENTITY_ID" "$SAML_IDP_URL" "$SAML_IDP_METADATA_URL"; then
        break
    fi
done

echo -e "\n- Writing config to .env -"

# Creating .env configuration file
echo PG_PWD=$PWD > .env
echo SAML_ENTITY_ID=$SAML_ENTITY_ID >> .env
echo SAML_IDP_URL=$SAML_IDP_URL >> .env
echo SAML_IDP_METADATA_URL=$SAML_IDP_METADATA_URL >> .env

echo "Completed writing config variables to .env"

docker-compose up -d
