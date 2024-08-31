#!/bin/bash

# Define colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to echo in green
echo_green() {
    echo -e "${GREEN}$1${NC}"
}

echo_red() {
    echo -e "${RED}$1${NC}"
}

ok_or_exit(){
    if [ $? -ne 0 ];then
        echo_red "Something went wrong, shutting down... $?"
        killall slapd
        exit 1
    fi
}

# Function to check if required environment variables are set
check_env_var() {
    if [ -z "${!1}" ]; then
        echo -e "${NC}Error: Environment variable $1 is not set.${NC}" >&2
        exit 1
    fi
}

# Function to check if slapd is ready
check_service_ready() {
    ldapsearch -x -H ldapi:/// -s base -b "" &>/dev/null
}

# Function to start LDAP
start_service() {
    echo_green "Starting slapd..."
    # Start slapd with the specified options
    slapd -d $LDAP_DEBUG -h 'ldap:/// ldapi:///' &
    SERVICE_PID=$!
}

init(){

    if [ "$INIT" = "true" ]; then
            echo_green "Initializing directory, here we go!"
            sleep 1

            echo_green "These is the current state of the configuration database:"
            ldapsearch -LLLQ -Y EXTERNAL -H ldapi:/// -b cn=config dn  | grep -v '^$'

        # Check if the kerberos.schema.gz file exists before copying
        if [ -f /usr/share/doc/krb5-kdc-ldap/kerberos.schema.gz ]; then
            echo_green "kerberos.schema.gz found. Proceeding with extraction and LDAP schema management..."

            # Copy, extract, and manage the schema
            cp /usr/share/doc/krb5-kdc-ldap/kerberos.schema.gz /etc/ldap/schema/
            gunzip /etc/ldap/schema/kerberos.schema.gz

            ldap-schema-manager -i /etc/ldap/schema/kerberos.schema | grep -v '^$'

            ok_or_exit
            
            echo_green "Kerberos schema imported successfully."
        else
            echo_green "kerberos.schema.gz not found. Skipping schema management steps."
            exit 1
        fi


        HASHED_LDAP_ADMIN_PASSWORD=$(slappasswd -s "$LDAP_ADMIN_PASSWORD")
        # Set admin password
        ldapmodify -H ldapi:/// -Y EXTERNAL <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: $LDAP_BASE_DN
-
replace: olcRootDN
olcRootDN: cn=admin,$LDAP_BASE_DN
-
replace: olcRootPW
olcRootPW: $HASHED_LDAP_ADMIN_PASSWORD
EOF


        if [ "$ROLE" = "master" ]; then
            init_master
        elif [ "$ROLE" = "slave" ]; then
            init_slave
        fi

    fi


}

init_slave(){
    echo_green "Configuring LDAP for SLAVE..."
    ldapmodify -Q -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: syncprov

dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcDbIndex
olcDbIndex: entryUUID eq
-
add: olcSyncrepl
olcSyncrepl: rid=0
    provider=$LDAP_MASTER_URL
    bindmethod=simple
    binddn="cn=replicator,$LDAP_BASE_DN" credentials=$LDAP_REPLICATOR_PASSWORD
    searchbase="$LDAP_BASE_DN"
    schemachecking=on
    type=refreshAndPersist retry="60 +"
-
add: olcUpdateRef
olcUpdateRef: $LDAP_MASTER_URL
EOF
    if [ $? -eq 20 ];then
        $?=0
    fi
    ok_or_exit

    echo_green "Initialization finished!"

}

init_master(){

    echo_green "Setting admin password..."

    dc_value=$(echo "$LDAP_BASE_DN" | awk -F ',|=' '{print $(NF-2)}')
    ldapadd -x -D cn=admin,$LDAP_BASE_DN -w $LDAP_ADMIN_PASSWORD <<EOF
dn: $LDAP_BASE_DN
objectClass: top
objectClass: dcObject
objectClass: organization
o: Organization
dc: $dc_value

dn: cn=admin,$LDAP_BASE_DN
changetype: add
objectClass: simpleSecurityObject
objectClass: organizationalRole
cn: admin
description: LDAP administrator
userPassword: $HASHED_LDAP_ADMIN_PASSWORD

EOF

    ok_or_exit

    # Modify LDAP configuration
    echo_green "Modifying LDAP configuration to add index for principals..."
    ldapmodify -Q -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={1}mdb,cn=config
add: olcDbIndex
olcDbIndex: krbPrincipalName eq,pres,sub
EOF

    ok_or_exit

    echo_green "Updating LDAP Access Control Lists (ACLs)..."
    ldapmodify -Q -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={1}mdb,cn=config
add: olcAccess
olcAccess: {2}to attrs=krbPrincipalKey
    by anonymous auth
    by dn.exact="uid=kdc-service,$LDAP_BASE_DN" read
    by dn.exact="uid=kadmin-service,$LDAP_BASE_DN" write
    by self write
    by * none
-
add: olcAccess
olcAccess: {3}to dn.subtree="$KERBEROS_LDAP_CONTAINER,$LDAP_BASE_DN"
    by dn.exact="uid=kdc-service,$LDAP_BASE_DN" read
    by dn.exact="uid=kadmin-service,$LDAP_BASE_DN" write
    by * none
-
add: olcAccess
olcAccess: {4}to dn.subtree="$LDAP_BASE_DN"
    by dn.exact="uid=kdc-service,$LDAP_BASE_DN" read
    by dn.exact="uid=kadmin-service,$LDAP_BASE_DN" write
    by * none        
EOF

    ok_or_exit

    HASHED_LDAP_REPLICATOR_PASSWORD=$(slappasswd -s "$LDAP_REPLICATOR_PASSWORD")
    echo_green "Creating replication user..."
    ldapadd -x -D cn=admin,$LDAP_BASE_DN -w $LDAP_ADMIN_PASSWORD <<EOF
dn: cn=replicator,$LDAP_BASE_DN
objectClass: simpleSecurityObject
objectClass: organizationalRole
cn: replicator
description: Replication user
userPassword: $HASHED_LDAP_REPLICATOR_PASSWORD
EOF

    ok_or_exit

    echo_green "Configuring LDAP for Delta Replication..."
    ldapmodify -Q -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcAccess
olcAccess: {0}to *
    by dn.exact="cn=replicator,$LDAP_BASE_DN" read
    by * break
-
add: olcLimits
olcLimits: dn.exact="cn=replicator,$LDAP_BASE_DN"
    time.soft=unlimited time.hard=unlimited
    size.soft=unlimited size.hard=unlimited
EOF

    ok_or_exit

    ldapadd -Q -Y EXTERNAL -H ldapi:/// <<EOF
# Add indexes to the frontend db.
dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcDbIndex
olcDbIndex: entryCSN eq
-
add: olcDbIndex
olcDbIndex: entryUUID eq

#Load the syncprov module.
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: syncprov

# syncrepl Provider for primary db
dn: olcOverlay=syncprov,olcDatabase={1}mdb,cn=config
changetype: add
objectClass: olcOverlayConfig
objectClass: olcSyncProvConfig
olcOverlay: syncprov
olcSpCheckpoint: 100 10
olcSpSessionLog: 1000000
EOF

    ok_or_exit

    HASHED_KERBEROS_KDC_PASSWORD=$(slappasswd -s "$KERBEROS_KDC_PASSWORD")
    HASHED_KERBEROS_KADMIN_PASSWORD=$(slappasswd -s "$KERBEROS_KADMIN_PASSWORD")

    echo_green "Creating users for KADMIN and KDC..."
    ldapadd -x -D cn=admin,$LDAP_BASE_DN -w $LDAP_ADMIN_PASSWORD <<EOF
dn: uid=kdc-service,$LDAP_BASE_DN
uid: kdc-service
objectClass: account
objectClass: simpleSecurityObject
userPassword: $HASHED_KERBEROS_KDC_PASSWORD
description: Account used for the Kerberos KDC

dn: uid=kadmin-service,$LDAP_BASE_DN
uid: kadmin-service
objectClass: account
objectClass: simpleSecurityObject
userPassword: $HASHED_KERBEROS_KADMIN_PASSWORD
description: Account used for the Kerberos Admin server
EOF

    ok_or_exit

    echo_green "Creating Kerberos REALM..."
    echo -e "$KERBEROS_MASTER_PASSWORD\n$KERBEROS_MASTER_PASSWORD\n$KERBEROS_LDAP_CONTAINER,$LDAP_BASE_DN" | kdb5_ldap_util -D cn=admin,$LDAP_BASE_DN create -w $LDAP_ADMIN_PASSWORD -subtrees $LDAP_BASE_DN -r $KERBEROS_REALM -s -H ldapi:/// >/dev/null

    ok_or_exit

    echo_green "Initialization finished!"


}

pre_init(){
# Check if /INIT file exists or INIT environment variable is set to true
if [ "$INIT" = "true" ]; then
    echo_green "INIT flag detected. Checking required environment variables..."

    check_env_var "ROLE"
    if [ $ROLE = "master" ];then
        check_env_var "LDAP_BASE_DN"
        check_env_var "LDAP_REPLICATOR_PASSWORD"
        check_env_var "LDAP_ADMIN_PASSWORD"
        check_env_var "LDAP_CONFIG_PASSWORD"
        check_env_var "KERBEROS_LDAP_CONTAINER"
        check_env_var "KERBEROS_KDC_PASSWORD"
        check_env_var "KERBEROS_KADMIN_PASSWORD"
        check_env_var "KERBEROS_MASTER_PASSWORD"
        check_env_var "KERBEROS_REALM"  
    elif [ $ROLE = "slave"];then
        check_env_var "LDAP_BASE_DN"
        check_env_var "LDAP_REPLICATOR_PASSWORD"
        check_env_var "LDAP_MASTER_URL"
    fi
    # Check required environment variables


    echo_green "All required environment variables are set. Proceeding with initialization..."

    # Remove all files in /var/lib/ldap/ and /etc/ldap/
    rm -rf /var/lib/ldap/*
    echo_green "Removed all files from /var/lib/ldap/."

    rm -rf /etc/ldap/*
    echo_green "Removed all files from /etc/ldap/."

    # Copy initial LDAP configuration
    echo_green "Copying initial LDAP configuration files..."
    cp -r /opt/ldap/ /etc/
    echo_green "Copied all files to /etc/ldap/."

    echo_green "Initialization cleanup complete."
fi
}

pre_init

# Call the function to start LDAP
start_service

# Wait until slapd is ready
echo_green "Waiting for slapd to start..."
while ! check_service_ready; do
    sleep 1
done
echo_green "slapd started"

init

wait $SERVICE_PID


