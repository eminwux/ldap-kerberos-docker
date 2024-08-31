# Dockerized OpenLDAP and MIT Kerberos Setup
## Overview
This project provides a containerized environment for running OpenLDAP and MIT Kerberos using Docker. The setup includes both master and slave configurations for LDAP and Kerberos, ensuring a robust and scalable authentication and directory service. This README will guide you through setting up and running the containers, as well as provide details about the project structure.

## Project Structure
```bash
.
├── ldap
│   ├── build
│   │   └── Dockerfile
│   └── volumes
│       ├── master
│       │   ├── conf
│       │   └── data
│       ├── slave
│       │   ├── conf
│       │   └── data
│       └── scripts
│           └── entrypoint.sh
├── krb5
│   ├── build
│   │   └── Dockerfile
│   └── volumes
│       ├── master
│       │   └── conf
│       ├── slave
│       │   └── conf
│       └── scripts
│           └── entrypoint.sh
├── docker-compose.yaml
└── .gitignore
```
## Services Overview
### LDAP
`ldap-master`: The primary LDAP server. It is configured with a base DN and initial schemas. Data and configuration are stored in volumes.

`ldap-slave`: The secondary LDAP server replicates data from the master. It is configured to connect to the master LDAP server.

### Kerberos
`kdc-master`: The primary Kerberos Key Distribution Center (KDC). It integrates with the LDAP master for user and service principal information.

`kdc-slave`: The secondary KDC replicates the data from the master KDC and is configured similarly.

## Use Cases
This project provides four distinct services: ldap-master, ldap-slave, kdc-master, and kdc-slave. Each service is designed to work in specific configurations. Below are the use cases for each service and the valid combinations for running them together.

### 1. ldap-master
Use Case: The ldap-master service is the primary LDAP server responsible for handling directory services. It holds the authoritative data and is configured to allow replication to ldap-slave instances.

When to Use:

Use ldap-master when you need a standalone LDAP server or when you plan to run it alongside a Kerberos Key Distribution Center (kdc-master or kdc-slave).
Valid Combinations:

ldap-master + kdc-master
ldap-master + kdc-slave

Restrictions:

Do not run ldap-master and ldap-slave together in the same environment.

### 2. ldap-slave
Use Case: The ldap-slave service is a secondary LDAP server configured to replicate data from the ldap-master. It serves as a read-only copy of the directory, useful for load balancing or redundancy.

When to Use:

Use ldap-slave when you need a replicated LDAP directory service for high availability or distributed access.
Valid Combinations:

ldap-slave + kdc-master
ldap-slave + kdc-slave

Restrictions:

Do not run ldap-slave and ldap-master together in the same environment.

### 3. kdc-master
Use Case: The kdc-master service is the primary Kerberos server responsible for handling authentication requests. It stores the principal database and serves as the authority for issuing Kerberos tickets.

When to Use:

Use kdc-master when you need a standalone Kerberos server or when running it alongside an LDAP server (ldap-master or ldap-slave).
Valid Combinations:

kdc-master + ldap-master
kdc-master + ldap-slave

Restrictions:

Do not run kdc-master and kdc-slave together in the same environment.
### 4. kdc-slave
Use Case: The kdc-slave service is a secondary Kerberos server with kdc but without kadmind. It provides redundancy and load balancing for Kerberos authentication services.

When to Use:

Use kdc-slave when you need a replicated Kerberos environment for high availability.
Valid Combinations:

kdc-slave + ldap-master
kdc-slave + ldap-slave

Restrictions:

Do not run kdc-slave and kdc-master together in the same environment.

# Important Notes
Single Role Enforcement: Each environment can only have one master or one slave service for LDAP and Kerberos at a time. Running both the master and slave roles together for LDAP or Kerberos in the same environment will cause conflicts and is not supported.
Inter-service Compatibility: While you cannot run two services of the same role together (e.g., ldap-master with ldap-slave or kdc-master with kdc-slave), you can run any combination of LDAP and Kerberos services as long as they respect the master/slave constraints.

# Setup Instructions
## Prerequisites

Docker and Docker Compose installed on your system.
Basic knowledge of LDAP and Kerberos.

## Step-by-Step Setup
### Clone the Repository:
```bash
git clone <repository_url>
cd <repository_directory>
```

### Build and Start the Containers: Use Docker Compose to build and run the containers.

```bash
docker-compose up --build
```

### Accessing LDAP:

LDAP Master is available on port 389.
Use an LDAP client like ldapsearch or Apache Directory Studio to interact with the LDAP server.

Example command:
```bash
docker exec -ti ldap-master /bin/bash
ldapsearch -x -H ldap://localhost -b $LDAP_BASE_DN -D "cn=admin,$LDAP_BASE_DN" -w $LDAP_ADMIN_PASSWORD
```

### Accessing Kerberos:

KDC is available on port 88.
Use kadmin to manage Kerberos principals.

Example command:
```bash
docker exec -ti kdc-master /bin/bash
kadmin.local
```

### Volumes
LDAP Volumes:

./ldap/volumes/master/data: Stores the LDAP database for the master.
./ldap/volumes/master/conf: Configuration files for the master.
./ldap/volumes/slave/data: Stores the LDAP database for the slave.
./ldap/volumes/slave/conf: Configuration files for the slave.

Kerberos Volumes:

./krb5/volumes/master/conf: Configuration files for the KDC master.
./krb5/volumes/slave/conf: Configuration files for the KDC slave.


## Environment Variables
`INIT`: Only used when starting the service for the first time.
`ROLE`: Defines the role of the container (master or slave).
`LDAP_BASE_DN`: Base DN for the LDAP directory.
`LDAP_REPLICATOR_PASSWORD`: Password for LDAP replication.
`LDAP_CONFIG_PASSWORD`: Admin password for LDAP configuration.
`KERBEROS_REALM`: Kerberos realm (e.g., EXAMPLE.COM).
`KERBEROS_KDC_PASSWORD`: Password for the KDC.
`KERBEROS_KADMIN_PASSWORD`: Password for Kerberos admin.

### Initial Setup with INIT=true
When starting the services for the first time, you must set the environment variable INIT=true. This setting initializes the service by configuring the necessary databases, creating initial directories, and setting up any required schema or configurations. **Important**: This process will delete any existing data and configurations, effectively resetting the service.

Start Services for the First Time:
```bash
docker-compose up -d --build --env INIT=true
```

### Post-Initialization
Once the initial setup is complete, you should restart the services with INIT=false. This prevents the initialization process from running again, protecting your data from being inadvertently deleted or overwritten.

Restart Services After Initialization:

```bash
docker-compose down
docker-compose up -d --env INIT=false
```
Remove Secret Variables: Ensure that any sensitive environment variables are cleared from your environment to avoid accidental exposure.

### Handling Secret Variables
The environment variables, including sensitive information like passwords and Kerberos keys, are only required during the initialization phase. After the initial setup is complete and the services are restarted with INIT=false, these variables are no longer used by the running containers.


### Restart Policy
The containers are set to restart unless stopped manually, ensuring they automatically recover from failures.

## Troubleshooting

Check container logs for debugging using:

``` bash
docker-compose logs ldap-master
docker-compose logs kdc-master
```

LDAP & Kerberos Synchronization: Ensure that the LDAP master is up and running before starting the Kerberos services.

# License
This project is licensed under the MIT License. See the LICENSE file for more details.

# Contributing
Contributions are welcome! Please submit a pull request or open an issue to discuss any changes or improvements.
For any questions or support, please contact [eminwux at famous-google-mail-service].

