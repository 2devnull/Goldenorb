#!/bin/sh 

	rm -f /tmp/easyrsa
### Step 1: Create the PKI directory tree
	PKI_DIR="/tmp/openvpn"

	if [ -d "$PKI_DIR" ]; then
		rm -rfv "$PKI_DIR"
	fi
	mkdir -p ${PKI_DIR}
	chmod -R 0600 ${PKI_DIR}
	mkdir -p ${PKI_DIR}/client
	chmod -R 0600 ${PKI_DIR}/client
	mkdir -p ${PKI_DIR}/server
	chmod -R 0600 ${PKI_DIR}/server
	mkdir -p ${PKI_DIR}/package
	chmod -R 0600 ${PKI_DIR}/package
	if [ -d "/www/package" ]; then
		rm -rfv "/www/package"
	fi
	ln -s ${PKI_DIR}/package /www/package
	cd ${PKI_DIR}
  
	touch index.txt
	echo 1000 > serial
	mkdir newcerts 
  
  
### Step 2: Start with a clean configuration, and establish the basic variables
	cp /etc/ssl/openssl.cnf ${PKI_DIR}
	PKI_CNF=${PKI_DIR}/openssl.cnf

	CNT=$(uci get openvpn.settings.country)
	CTY=$(uci get openvpn.settings.city)
	ORG=$(uci get openvpn.settings.organ)
	DAYS=$(uci get openvpn.settings.days)
	CNAME=$(uci get openvpn.settings.comm)
	EMAIL=$(uci get openvpn.settings.email)
	UNIT=$(uci get openvpn.settings.unit)
	UNSTRUC=$(uci get openvpn.settings.unstruc)
	
	sed -i "/^dir/   s:=.*:= ${PKI_DIR}/:" ${PKI_CNF}
	sed -i '/.*Name/ s:= match:= optional:'     ${PKI_CNF}

	sed -i "/organizationName_default/    s:= .*:= $ORG:"  		${PKI_CNF}
	sed -i "/stateOrProvinceName_default/ s:= .*:= $CTY:"    	${PKI_CNF}
	sed -i "/countryName_default/         s:= .*:= $CNT:"       ${PKI_CNF}
	if [ ! -z $CNAME ]; then
		sed -i -e "s/commonName			= Common Name (e.g. server FQDN or YOUR name)/commonName = $CNAME/g"       ${PKI_CNF}
	fi
	if [ ! -z $EMAIL ]; then
		sed -i -e "s/emailAddress			= Email Address/emailAddress = $EMAIL/g"       ${PKI_CNF}
	fi
	if [ ! -z $UNIT ]; then
		sed -i -e "s/organizationalUnitName		= Organizational Unit Name (eg, section)/organizationalUnitName = $UNIT/g"       ${PKI_CNF}
	fi
	if [ ! -z $UNSTRUC ]; then
		sed -i -e "s/unstructuredName		= An optional company name/unstructuredName = $UNSTRUC/g"       ${PKI_CNF}
	fi
  
	sed -i "/default_days/   s:=.*:= $DAYS:"  	${PKI_CNF} 
	sed -i "/default_bits/   s:=.*:= 2048:"     ${PKI_CNF} 


cat >> ${PKI_CNF} <<"EOF"
###############################################################################
### Check via: openssl x509 -text -noout -in *.crt | grep 509 -A 1
[ my-server ] 
#  X509v3 Key Usage:          Digital Signature, Key Encipherment
#  X509v3 Extended Key Usage: TLS Web Server Authentication
  keyUsage = digitalSignature, keyEncipherment
  extendedKeyUsage = serverAuth

[ my-client ] 
#  X509v3 Key Usage:          Digital Signature
#  X509v3 Extended Key Usage: TLS Web Client Authentication
  keyUsage = digitalSignature
  extendedKeyUsage = clientAuth

EOF
  
	echo "1" > /tmp/easyrsa
	
### Step 3a: Create the CA, Server, and Client certificates (*without* using easy-rsa):
# pkitool --initca            ## equivalent to the 'build-ca' script
	openssl req -batch -nodes -new -keyout "ca.key" -out "ca.crt" -x509 -config ${PKI_CNF}  2> /dev/null ## x509 (self-signed) for the CA

	echo "2" > /tmp/easyrsa
# pkitool --server my-server  ## equivalent to the 'build-key-server' script
	openssl req -batch -nodes -new -keyout "$ORG-server.key" -out "$ORG-server.csr" -subj "/CN=$ORG-server" -config ${PKI_CNF} 2> /dev/null 
	openssl ca  -batch -keyfile "ca.key" -cert "ca.crt" -in "$ORG-server.csr" -out "$ORG-server.crt" -config ${PKI_CNF} -extensions my-server 2> /dev/null 

	echo "3" > /tmp/easyrsa  
# pkitool          my-client  ## equivalent to the 'build-key' script
	openssl req -batch -nodes -new -keyout "$ORG-client.key" -out "$ORG-client.csr" -subj "/CN=$ORG-client" -config ${PKI_CNF} 2> /dev/null 
	openssl ca  -batch -keyfile "ca.key" -cert "ca.crt" -in "$ORG-client.csr" -out "$ORG-client.crt" -config ${PKI_CNF} -extensions my-client 2> /dev/null     

	chmod 0600 "ca.key"
	chmod 0600 "$ORG-server.key"
	chmod 0600 "$ORG-client.key"
	
	cp "ca.crt" ${PKI_DIR}/client
	cp "$ORG-client.key" ${PKI_DIR}/client
	cp "$ORG-client.crt" ${PKI_DIR}/client
	cp "ca.crt" ${PKI_DIR}/server
	cp "$ORG-server.key" ${PKI_DIR}/server
	cp "$ORG-server.crt" ${PKI_DIR}/server
	
	echo "4" > /tmp/easyrsa
### Step 4: Create the Diffie-Hellman parameters
	openssl dhparam -out dh2048.pem 2048 2> /dev/null 
	cp "dh2048.pem" ${PKI_DIR}/server

	echo "5" > /tmp/easyrsa
	
### Step 5: Create the client's .ovpn file
###

OVPN_FILE="${PKI_DIR}/$ORG.ovpn"

tee "$OVPN_FILE" >/dev/null <<EOF2
  client 
  dev tun
  fast-io
  remote "my-server-address 1194"
  remote-cert-tls server
  nobind
  persist-key
  persist-tun
  comp-lzo no
  verb 3
  auth-user-pass
EOF2

	echo '<ca>'    >> ${OVPN_FILE}
	cat            >> ${OVPN_FILE} < ca.crt        
	echo '</ca>'   >> ${OVPN_FILE}

	echo '<cert>'  >> ${OVPN_FILE}
	cat            >> ${OVPN_FILE} < $ORG-client.crt 
	echo '</cert>' >> ${OVPN_FILE}

	echo '<key>'   >> ${OVPN_FILE}
	cat            >> ${OVPN_FILE} < $ORG-client.key 
	echo '</key>'  >> ${OVPN_FILE}
	
	cp ${OVPN_FILE} ${PKI_DIR}/client
	
	tar -czf ${PKI_DIR}/package/certificates.tar.gz ./client ./server
	sleep 7
	echo "6" > /tmp/easyrsa