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
        killall krb5kdc
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

# Function to check if krb5kdc is ready
check_service_ready() {
    # Define the hostname and port for the krb5kdc service
    local host="localhost"
    local port=88

    # Attempt to connect to the krb5kdc service
    echo_green "Checking if krb5kdc is ready on $host:$port..."

    while ! nc -z $host $port; do
        echo_green "Waiting for krb5kdc to start..."
        sleep 2
    done

    echo "krb5kdc is up and running on $host:$port."
}

# Function to start krb5kdc
start_service() {
    echo_green "Starting krb5kdc..."
    # Start krb5kdc in the background
    krb5kdc -n &
    
    if [ $ROLE = "master" ];then
        kadmind -nofork &

    elif [ $ROLE = "slave" ];then
        true
    fi

    # Capture the PID of the krb5kdc process
    SERVICE_PID=`pidof krb5kdc`

    echo_green "krb5kdc started with PID $SERVICE_PID."
}

init(){

    if [ "$INIT" = "true" ]; then
        echo_green "Initializing kerberos, here we go!"

        echo_green "Initialization finished!"
    fi


}

pre_init(){
# Check if /INIT file exists or INIT environment variable is set to true
    if [ "$INIT" = "true" ]; then
        echo_green "INIT flag detected. Checking required environment variables..."

        check_env_var "KERBEROS_LDAP_CONTAINER"
        check_env_var "KERBEROS_KDC_PASSWORD"
        check_env_var "KERBEROS_KADMIN_PASSWORD"
        check_env_var "KERBEROS_MASTER_PASSWORD"
        check_env_var "KERBEROS_REALM"      

        check_env_var "ROLE"
        if [ $ROLE = "master" ];then
            true
        elif [ $ROLE = "slave" ];then
            true
        fi

        # Check required environment variables
        echo_green "All required environment variables are set. Proceeding with initialization..."

        sleep 1

        rm -rf /etc/krb5.conf /etc/krb5kdc/kdc.conf /etc/krb5kdc/kadm5.acl

        # kdc configuration
        envsubst < /etc/krb5kdc/kdc.conf.template > /etc/krb5kdc/kdc.conf

        # kadm5 configuration
        envsubst < /etc/krb5kdc/kadm5.acl.template > /etc/krb5kdc/kadm5.acl

        # krb5 client configuration
        envsubst < /etc/krb5kdc/krb5.conf.template > /etc/krb5.conf
        
        echo -e "$KERBEROS_MASTER_PASSWORD" | kdb5_util stash

        if [ $ROLE = "master" ];then
            echo_green "role: $ROLE"
        elif [ $ROLE = "slave" ];then
            echo_green "role: $ROLE"
        else
            echo_red "role $ROLE not defined"
        fi

        echo -e "$KERBEROS_KADMIN_PASSWORD\n$KERBEROS_KADMIN_PASSWORD" | kdb5_ldap_util -D cn=admin,$LDAP_BASE_DN stashsrvpw -w $LDAP_ADMIN_PASSWORD -f /etc/krb5kdc/service.keyfile uid=kadmin-service,$LDAP_BASE_DN

        echo -e "$KERBEROS_KDC_PASSWORD\n$KERBEROS_KDC_PASSWORD" | kdb5_ldap_util -D cn=admin,$LDAP_BASE_DN stashsrvpw -w $LDAP_ADMIN_PASSWORD -f /etc/krb5kdc/service.keyfile uid=kdc-service,$LDAP_BASE_DN

    fi
}

pre_init

# Call the function to start krb5kdc
start_service

# Wait until slapd is ready
echo_green "Waiting for krb5kdc to start..."
while ! check_service_ready; do
    sleep 1
done
echo_green "krb5kdc started"

init

wait $SERVICE_PID


