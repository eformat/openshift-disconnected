#!/bin/bash

# Description: Simple Script to Create an NSS Certificat Authority (CA), and client / server certificats that can be used for testing. 
# Usage: Simply run the script with out options. Be sure to set the Configuration settings below
# Opetions: are positional
#        1: -i - This option activates intermediate mode, and will issue and intermediate CA certificate, clients and servers will be signed by the intermediat and not the CA. 
#        2: -j - This option activates Java, and will issue java keystores for 

# -- Configuration -------------------------------------------------------
# Testing Varables
DB_LOCAL=./certs_db
CERT_LOCAL=./certs
# Use this for most production items
## CERT_LOCAL=/etc/pki/
## DB_LOCAL=/etc/pki/nssdb/
# You want to this directory so that tls/{certs,private}/ and java/ are sub directories. 
INDEX=0
PASSWORD="password"
#HOSTNAME=$(hostname)
HOSTNAME=bastion.hosts.eformat.me
CLIENT="client"

# -- Script Below ---------------------------------------------------------

# These are Required Pakages for this script to run. 
for package in nss-tools openssl gawk 
do
    if [[ $(rpm -q $package > /dev/null 2>&1; echo $?) == 1 ]]; then
        echo "$package is not installed, script requires $package to run!" 
        exit 1
    fi
done

# This simply indicates what mode you are in. 
if [[ $1 == "-i" ]]; then
    echo "Intermediate Mode Activated!"  
fi
if [[ $2 == "-j" ]]; then
    echo "Java Mode Activated!"
    if [[ $(java -version > /dev/null 2>&1; echo $?) != 0 ]]; then
        echo "Java is not installed"
        exit 1
    fi 
    mkdir -p $CERT_LOCAL/java;
fi 

### BEGIN 

mkdir -p $CERT_LOCAL/tls/certs; mkdir -p $CERT_LOCAL/tls/private; 
(w ; ps -ef ; date ) | sha1sum | awk '{print $1}' > $CERT_LOCAL/tls/.noise.txt
( echo $PASSWORD ) > $CERT_LOCAL/tls/.pwdfile.txt

echo "Createing CA Store"
mkdir -p $DB_LOCAL; ( echo "$PASSWORD"; echo "$PASSWORD" ) | certutil -N -d $DB_LOCAL -z $CERT_LOCAL/tls/.nosie.txt -f $CERT_LOCAL/tls/.pwdfile.txt
echo "Createing CA"
( echo y; echo; echo y ) | certutil -S -s "CN=root_ca, O=personal_ca" -n "root_ca" -t ",,C" -x -d $DB_LOCAL -2 -z $CERT_LOCAL/tls/.noise.txt -m $INDEX -v 120 -f $CERT_LOCAL/tls/.pwdfile.txt
# This is here to incrament the index. 
((INDEX+=1))

if [[ $1 == "-i" ]]; then
    # Create the IM CA 
    echo "Creating Intermediary CA Certificate"  
    ( echo y ; echo ; echo y ) | certutil -S -n "im_ca" -s "CN=im_ca, O=personal_ca.org" -x -t "CT,," -x -m $INDEX -v 120 -d $DB_LOCAL -z $CERT_LOCAL/tls/.noise.txt -f $CERT_LOCAL/tls/.pwdfile.txt -2
    # This is here to incrament the index. 
    ((INDEX+=1))
fi

echo "Createing Server Certificate Request"
( echo N ; echo ; echo N ) | certutil -R -s "CN=$HOSTNAME, O=org.org, L=City, ST=State, C=US" -a -o $CERT_LOCAL/tls/server.csr -d $DB_LOCAL -z $CERT_LOCAL/tls/.noise.txt -f $CERT_LOCAL/tls/.pwdfile.txt
echo "Createing Client Certificate Request"
( echo N ; echo ; echo N ) | certutil -R -s "CN=$CLIENT, O=org.org, L=City, ST=State, C=US" -a -o $CERT_LOCAL/tls/client.csr -d $DB_LOCAL -z $CERT_LOCAL/tls/.noise.txt -f $CERT_LOCAL/tls/.pwdfile.txt

# These are here if you want to verify what is in the DB. 
#certutil -L -d $DB_LOCAL
#certutil -K -d $DB_LOCAL

SIGNING_AUTHORITY="root_ca"
if [[ $1 == "-i" ]]; then
    SIGNING_AUTHORITY="im_ca"
fi

echo "Signing a Server Certificate"
( echo N ; echo ; echo N ) | certutil -C -m $INDEX -i $CERT_LOCAL/tls/server.csr -o $CERT_LOCAL/tls/certs/server.crt -c "$SIGNING_AUTHORITY" -a -d $DB_LOCAL -2 -z $CERT_LOCAL/tls/.noise.txt -f $CERT_LOCAL/tls/.pwdfile.txt
# This is here to incrament the index. 
((INDEX+=1))
echo "Signing a Client Certificate"
( echo N ; echo ; echo N ) | certutil -C -m $INDEX -i $CERT_LOCAL/tls/client.csr -o $CERT_LOCAL/tls/certs/client.crt -c "$SIGNING_AUTHORITY" -a -d $DB_LOCAL -2 -z $CERT_LOCAL/tls/.noise.txt -f $CERT_LOCAL/tls/.pwdfile.txt
# This is here to incrament the index. However at this point its not needed unless other certificates will be issued.  
((INDEX+=1))

echo "Adding a Server Certificate"
certutil -A -d $DB_LOCAL -i $CERT_LOCAL/tls/certs/server.crt -n "server" -t "u,u,u" -z $CERT_LOCAL/tls/.noise.txt -f $CERT_LOCAL/tls/.pwdfile.txt
echo "Adding Client Certificate"
certutil -A -d $DB_LOCAL -i $CERT_LOCAL/tls/certs/client.crt -n "client" -t "u,u,u" -z $CERT_LOCAL/tls/.noise.txt -f $CERT_LOCAL/tls/.pwdfile.txt

echo "Exporting CA cert" 
certutil -L -d $DB_LOCAL -n root_ca -a > $CERT_LOCAL/tls/certs/cacert.crt

if [[ $1 == "-i" ]]; then
    echo "Exporting Intermediary CA cert" 
    certutil -L -d $DB_LOCAL -n im_ca -a > $CERT_LOCAL/tls/certs/imcert.crt
    echo "Creating Cert Bundle"
    cat $CERT_LOCAL/tls/certs/cacert.crt > $CERT_LOCAL/tls/certs/ca_bundle.crt; cat $CERT_LOCAL/tls/certs/imcert.crt >> $CERT_LOCAL/tls/certs/ca_bundle.crt
fi  # openssl crl2pkcs7 -nocrl -certfile certificate.cer -out certificate.p7b -certfile CACert.cer

echo "Expoting Server and Client KeyStores" 
pk12util -d $DB_LOCAL -o $CERT_LOCAL/tls/certs/server.pk12 -n server -k $CERT_LOCAL/tls/.pwdfile.txt -W $PASSWORD
pk12util -d $DB_LOCAL -o $CERT_LOCAL/tls/certs/client.pk12 -n client -k $CERT_LOCAL/tls/.pwdfile.txt -W $PASSWORD

echo "Exporting Server and Client Keys"
export PASSWORD
openssl pkcs12 -in $CERT_LOCAL/tls/certs/server.pk12 -out $CERT_LOCAL/tls/private/server.key -nodes -nocerts -clcerts -password env:PASSWORD
openssl pkcs12 -in $CERT_LOCAL/tls/certs/client.pk12 -out $CERT_LOCAL/tls/private/client.key -nodes -nocerts -clcerts -password env:PASSWORD

if [[ $2 == "-j" ]]; then
    # Create Client and Server Keystores with the correct CA files included for trust relationships. 
    keytool -importkeystore -srckeystore $CERT_LOCAL/tls/certs/server.pk12 -srcstoretype pkcs12 -srcalias server -srcstorepass $PASSWORD -destkeystore $CERT_LOCAL/java/server.jks -deststoretype jks -deststorepass $PASSWORD -destalias server -storepass $PASSWORD
    keytool -import -trustcacerts -alias root -file $CERT_LOCAL/tls/certs/cacert.crt -keystore $CERT_LOCAL/java/server.jks -storepass $PASSWORD -noprompt
    if [[ $1 == "-i" ]]; then
        keytool -import -trustcacerts -alias im -file $CERT_LOCAL/tls/certs/imcert.crt -keystore $CERT_LOCAL/java/server.jks -storepass $PASSWORD -noprompt
    fi
    keytool -importkeystore -srckeystore $CERT_LOCAL/tls/certs/client.pk12 -srcstoretype pkcs12 -srcalias client -srcstorepass $PASSWORD -destkeystore $CERT_LOCAL/java/client.jks -deststoretype jks -deststorepass $PASSWORD -destalias client -storepass $PASSWORD
    keytool -import -trustcacerts -alias root -file $CERT_LOCAL/tls/certs/cacert.crt -keystore $CERT_LOCAL/java/client.jks -storepass $PASSWORD -noprompt
    if [[ $1 == "-i" ]]; then
        keytool -import -trustcacerts -alias im -file $CERT_LOCAL/tls/certs/imcert.crt -keystore $CERT_LOCAL/java/client.jks -storepass $PASSWORD -noprompt
    fi 
fi 
unset PASSWORD

# Self Signed Notes: 

###  JAVA

# KEY_FILE="my_keystore.jks"
# echo "JAVA_HOME: $JAVA_HOME"
# echo "Creating keystore: $KEY_FILE"
# keytool -genkey -alias test -keyalg RSA -keystore $KEY_FILE -storepass "password" -keypass "passowrd" -dname "CN=server, OU=MYOU, O=MYORG, L=MYCITY, ST=MYSTATE, C=MY"
