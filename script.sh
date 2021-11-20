#!/bin/bash

while getopts "c:p:z:-:" OPT; do
	if [ "$OPT" = "-" ]; then
		OPT="${OPTARG%%=*}"
		OPTARG="${OPTARG#$OPT}"
		OPTARG="${OPTARG#=}"
	fi
	case "$OPT" in
        c | config )
			if ! [[ $OPTARG =~ ^[145]$ ]] ; then
				echo "Invalid configuration number: '$OPTARG'."
				exit
			fi
			CONFIG=$OPTARG;;
		p | project )
			PROJECT=$OPTARG;;
		z | zone )
			ZONE=$OPTARG;;
        frontend )
			FRONTEND=$OPTARG;;
        backend ) # For config 1
			BACKEND=$OPTARG;;
		backend-port )
			BACKEND_PORT=$OPTARG;;
		backend1 ) # For config 4 (master) & 5
			BACKEND1=$OPTARG;;
		backend2 ) # For config 4 (slave) & 5
			BACKEND2=$OPTARG;;
		backend1-port ) # For config 4 (master) & 5
			BACKEND1_PORT=$OPTARG;;
		backend2-port ) # For config 4 (slave) & 5
			BACKEND2_PORT=$OPTARG;;
        nginx )
			NGINX=$OPTARG;;
        database ) # For config 1
        	DATABASE=$OPTARG;;
		master )
			MASTER=$OPTARG;;
		slave )
			SLAVE=$OPTARG;;
        * )
			echo "Invalid option '$OPTIND'"
			exit;;
	esac
done
shift $((OPTIND-1))

echo ""
echo "============================================"
echo "Checking params ============================"
echo ""

if [ -z "$ZONE" ] ; then
	ZONE="europe-central2-a"
fi

if [ -z "$FRONTEND" ] ; then
	echo "Frontend VM name not set. Use --frontend to set."
	exit
fi

if [ -z "$NGINX" ] ; then
	NGINX="$FRONTEND"
fi

if [[ $CONFIG =~ ^[1]$ && -z "$BACKEND" ]] ; then
	echo "Backend VM name not set. For configuration 1 you must set it by --backend option."
	exit
fi

if [[ $CONFIG =~ ^[1]$ && -z "$BACKEND_PORT" ]] ; then
	BACKEND_PORT="9966"
fi

if [[ $CONFIG =~ ^[45]$ && -z "$BACKEND1" ]] ; then
	echo "Backend 1 VM name not set. For configuration 4 (master) & 5 you must set it by --backend1 option."
	exit
fi

if [[ $CONFIG =~ ^[45]$ && -z "$BACKEND1_PORT" ]] ; then
	echo "Backend 1 port not set. For configuration 4 (master) & 5 you must set it by --backend1-port option."
	exit
fi

if [[ $CONFIG =~ ^[45]$ && -z "$BACKEND2" ]] ; then
	echo "Backend 2 VM name not set. For configuration 4 (slave) & 5 you must set it by --backend1 option."
	exit
fi

if [[ $CONFIG =~ ^[45]$ && -z "$BACKEND2_PORT" ]] ; then
	echo "Backend 2 port not set. For configuration 4 (master) & 5 you must set it by --backend2-port option."
	exit
fi

if [[ $CONFIG =~ ^[45]$ && -z "$NGINX" ]] ; then
	echo "Nginx VM name not set. For configuration 4 & 5 you must set it by --nginx option."
	exit
fi

if [[ $CONFIG =~ ^[1]$ ]] && [ -z "$DATABASE" ] ; then
	echo "Database VM name not set. For configuration 1 you must set it by --database option."
	exit
fi

if [[ $CONFIG =~ ^[45]$ && -z "$MASTER" ]] ; then
	echo "Master database VM name not set. For configuration 4 & 5 you must set it by --master option."
	exit
fi

if [[ $CONFIG =~ ^[45]$ && -z "$SLAVE" ]] ; then
	echo "Slave database VM name not set. For configuration 4 & 5 you must set it by --slave option."
	exit
fi

echo ""
echo "Params check done =========================="
echo "============================================"
echo ""
echo ""
echo "============================================"
echo "Setting up database ========================"
echo ""

FRONTEND_INTERNAL_IP=$(gcloud compute instances describe $FRONTEND --zone $ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
NGINX_INTERNAL_IP=$(gcloud compute instances describe $NGINX --zone $ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

if [[ $CONFIG =~ ^[1]$ ]] ; then
	BACKEND_INTERNAL_IP=$(gcloud compute instances describe $BACKEND --zone $ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
	DB_INTERNAL_IP=$(gcloud compute instances describe $DATABASE --zone $ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
elif [[ $CONFIG =~ ^[45]$ ]] ; then
	BACKEND1_INTERNAL_IP=$(gcloud compute instances describe $BACKEND1 --zone $ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
	BACKEND2_INTERNAL_IP=$(gcloud compute instances describe $BACKEND2 --zone $ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
	MASTER_INTERNAL_IP=$(gcloud compute instances describe $MASTER --zone $ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
	MASTER_INTERNAL_IP=$(gcloud compute instances describe $MASTER --zone $ZONE --format='get(networkInterfaces[0].networkIP)')
	SLAVE_INTERNAL_IP=$(gcloud compute instances describe $SLAVE --zone $ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
	SLAVE_INTERNAL_IP=$(gcloud compute instances describe $SLAVE --zone $ZONE --format='get(networkInterfaces[0].networkIP)')
fi

if [[ $CONFIG =~ ^[1]$ ]] ; then
	gcloud beta compute ssh --zone "$ZONE" "$DATABASE"  --project "$PROJECT" <<-EOT
	#!/bin/bash
	sudo apt-get update
	sudo apt-get install mysql-server mysql-client -y
	sudo apt-get install git -y

	git clone https://github.com/spring-petclinic/spring-petclinic-rest

	cd spring-petclinic-rest/src/main/resources/db/mysql
  sudo sed -i "s/GRANT ALL PRIVILEGES ON petclinic.* TO pc@localhost IDENTIFIED BY 'pc';//g" ./initDB.sql
  sudo sed -i "s/^bind-address\s*=\s*127\.0\.0\.1$/bind-address=0.0.0.0/g" /etc/mysql/mysql.conf.d/mysqld.cnf

	sudo mysql
	source initDB.sql;
	use petclinic;
	source populateDB.sql;
  CREATE USER 'pc'@'localhost' IDENTIFIED BY 'petclinic';
	CREATE USER 'pc'@'%' IDENTIFIED BY 'petclinic';
	GRANT ALL PRIVILEGES ON petclinic.* TO 'pc'@'localhost';
	GRANT ALL PRIVILEGES ON petclinic.* TO 'pc'@'%';
	FLUSH PRIVILEGES;
	FLUSH TABLES WITH READ LOCK;
	exit
  
  git --force enable
  sudo ufw allow mysql
  sudo systemctl start mysql
  sudo systemctl enable mysql
  sudo systemctl restart mysql

	EOT
elif [[ $CONFIG =~ ^[45]$ ]] ; then
	# MASTER
	echo ""
	echo "Master ====================================="
	echo ""
	gcloud beta compute ssh --zone "$ZONE" "$MASTER"  --project "$PROJECT" <<-EOT
	#!/bin/bash
	sudo apt-get update
	sudo apt-get install mysql-server mysql-client -y
	sudo apt-get install git -y

	# konfiguracja Master

	sudo sed -i "s/^bind-address\s*=\s*127\.0\.0\.1$/bind-address=$MASTER_INTERNAL_IP/g" /etc/mysql/mysql.conf.d/mysqld.cnf
	sudo sed -i 's/^#\s*server-id\s*=\s*1$/server-id=1/g' /etc/mysql/mysql.conf.d/mysqld.cnf
	sudo sed -i 's/^#\s*log_bin\s*=\s*\/var\/log\/mysql\/mysql-bin\.log$/log_bin=\/var\/log\/mysql\/mysql-bin.log/g' /etc/mysql/mysql.conf.d/mysqld.cnf
	sudo sed -i 's/^#\s*binlog_do_db\s*=\s*include_database_name$/binlog_do_db=petclinic/g' /etc/mysql/mysql.conf.d/mysqld.cnf

	sudo systemctl restart mysql

	sudo mysql
	CREATE USER 'slave'@"$SLAVE_INTERNAL_IP" IDENTIFIED WITH mysql_native_password BY 'slave';
	GRANT REPLICATION SLAVE ON *.* TO 'slave'@"$SLAVE_INTERNAL_IP";
	FLUSH PRIVILEGES;
	exit


	git clone https://github.com/spring-petclinic/spring-petclinic-rest

	cd spring-petclinic-rest/src/main/resources/db/mysql

	sudo mysql
	source initDB.sql;
	use petclinic;
	source populateDB.sql;
	CREATE USER 'pc'@'localhost' IDENTIFIED BY 'petclinic';
	CREATE USER 'pc'@'%' IDENTIFIED BY 'petclinic';
	GRANT ALL PRIVILEGES ON petclinic.* TO 'pc'@'localhost';
	GRANT ALL PRIVILEGES ON petclinic.* TO 'pc'@'%';
	FLUSH PRIVILEGES;
	FLUSH TABLES WITH READ LOCK;
	exit

	cd ~/
	sudo mysqldump -u root petclinic > petclinic.sql
	sudo mysql -ANe "SHOW MASTER STATUS" > master_data.txt 

	gcloud compute scp petclinic.sql master_data.txt $SLAVE:~/ --zone $ZONE -q
	
	EOT

	# SLAVE
	echo ""
	echo "Slave ======================================"
	echo ""
	gcloud beta compute ssh --zone "$ZONE" "$SLAVE"  --project "$PROJECT" <<-EOT
	#!/bin/bash

	sudo apt-get update
	sudo apt-get install mysql-server mysql-client -y

	# konfiguracja Slave

	sudo mysql
	CREATE DATABASE petclinic;
	CREATE USER 'pc'@'localhost' IDENTIFIED BY 'petclinic';
	CREATE USER 'pc'@'%' IDENTIFIED BY 'petclinic';
	GRANT ALL PRIVILEGES ON petclinic.* TO 'pc'@'localhost';
	GRANT ALL PRIVILEGES ON petclinic.* TO 'pc'@'%';
	FLUSH PRIVILEGES;
	exit
	sudo mysql petclinic < petclinic.sql

	sudo sed -i 's/^#\s*server-id\s*=\s*1$/server-id=2/g' /etc/mysql/mysql.conf.d/mysqld.cnf
	sudo sed -i 's/^#\s*log_bin\s*=\s*\/var\/log\/mysql\/mysql-bin\.log$/log_bin=\/var\/log\/mysql\/mysql-bin.log/g' /etc/mysql/mysql.conf.d/mysqld.cnf
	sudo sed -i 's/^#\s*binlog_do_db\s*=\s*include_database_name$/binlog_do_db=petclinic/g' /etc/mysql/mysql.conf.d/mysqld.cnf
	sudo sed -i 's/^#\s*binlog_ignore_db\s*=\s*include_database_name$/relay-log=\/var\/log\/mysql\/mysql-relay-bin\.log/g' /etc/mysql/mysql.conf.d/mysqld.cnf
	sudo systemctl restart mysql

	# dane potrzebne do replikacji
	SOURCE_LOG=$(cat master_data.txt | awk '{print $1}')
	SOURCE_POS=$(cat master_data.txt | awk '{print $2}')

	sudo mysql

	CHANGE REPLICATION SOURCE TO
	SOURCE_HOST='$MASTER_INTERNAL_IP',
	SOURCE_USER='slave',
	SOURCE_PASSWORD='slave',
	SOURCE_LOG_FILE='$SOURCE_LOG',
	MASTER_LOG_POS=$SOURCE_POS;

	START REPLICA;
	EOT
fi

echo ""
echo "Database done =============================="
echo "============================================"
echo ""
echo ""
echo "============================================"
echo "Setting up backend ========================="
echo ""

# Backend
if [[ $CONFIG =~ ^[1]$ ]] ; then
	gcloud beta compute ssh --zone "$ZONE" "$BACKEND"  --project "$PROJECT" <<-EOT
	#!/bin/bash
	sudo apt-get update
	sudo apt-get install openjdk-11-jdk -y
	git clone https://github.com/spring-petclinic/spring-petclinic-rest.git
	cd spring-petclinic-rest

	sudo sed -i "s/server.port=..../server.port=$BACKEND_PORT/" src/main/resources/application.properties

	sudo sed -i 's/=hsqldb/=mysql/' src/main/resources/application.properties
	sudo sed -i "s/^spring.datasource.url.*$/spring.datasource.url=jdbc:mysql:\/\/$DB_INTERNAL_IP:3306\/petclinic?useUnicode=true/" src/main/resources/application-mysql.properties

	pkill -f java
	rm log.out 2> /dev/null
	echo "starting rest"
	./mvnw spring-boot:run >/dev/null 2>&1 > log.out &
	timeout 100 tail -f log.out
	echo "done"
	EOT
elif [[ $CONFIG =~ ^[45]$ ]] ; then

	echo ""
	echo "Backend 1 =================================="
	echo ""

	gcloud beta compute ssh --zone "$ZONE" "$BACKEND1"  --project "$PROJECT" <<-EOT
	#!/bin/bash
	sudo apt-get update
	sudo apt-get install openjdk-11-jdk -y
	git clone https://github.com/spring-petclinic/spring-petclinic-rest.git
	cd spring-petclinic-rest
	
	sudo sed -i "s/server.port=..../server.port=$BACKEND1_PORT/" src/main/resources/application.properties

	sudo sed -i 's/=hsqldb/=mysql/' src/main/resources/application.properties
	sudo sed -i "s/^spring.datasource.url.*$/spring.datasource.url=jdbc:mysql:\/\/$MASTER_INTERNAL_IP:3306\/petclinic?useUnicode=true\//" src/main/resources/application-mysql.properties

	pkill -f java
	rm log.out 2> /dev/null
	echo "starting rest"
	./mvnw spring-boot:run >/dev/null 2>&1 > log.out &
	timeout 100 tail -f log.out
	echo "done"
	EOT

	echo ""
	echo "Backend 2 =================================="
	echo ""

	gcloud beta compute ssh --zone "$ZONE" "$BACKEND2"  --project "$PROJECT" <<-EOT
	#!/bin/bash
	sudo apt-get update
	sudo apt-get install openjdk-11-jdk -y
	if [[ "$BACKEND1" != "$BACKEND2" ]] ; then
		git clone https://github.com/spring-petclinic/spring-petclinic-rest.git
	fi
	cd spring-petclinic-rest

	sudo sed -i "s/server.port=..../server.port=$BACKEND2_PORT/" src/main/resources/application.properties

	sudo sed -i 's/=hsqldb/=mysql/' src/main/resources/application.properties
	sudo sed -i "s/^spring.datasource.url.*$/spring.datasource.url=jdbc:mysql:\/\/$SLAVE_INTERNAL_IP:3306\/petclinic?useUnicode=true\//" src/main/resources/application-mysql.properties

	pkill -f java
	rm log.out 2> /dev/null
	echo "starting rest"
	./mvnw spring-boot:run >/dev/null 2>&1 > log.out &
	timeout 100 tail -f log.out
	echo "done"
	EOT
fi

echo ""
echo "Backend done ==============================="
echo "============================================"
echo ""

# Load balancer
if [[ "$NGINX" != "$FRONTEND" ]] ; then

	echo ""
	echo "============================================"
	echo "Setting up load balancer ==================="
	echo ""

	gcloud beta compute ssh --zone "$ZONE" "$NGINX"  --project "$PROJECT" <<-EOT
	#!/bin/bash

	sudo apt install nginx -y

	sudo sed -i '12,$d' /etc/nginx/nginx.conf
	
	EOT

	gcloud compute scp "$NGINX":/etc/nginx/nginx.conf nginx.conf --zone $ZONE -q

	if [[ "$CONFIG" == "4" ]] ; then
		sudo sed -i "/http {/a #konfiguracja4\n\tupstream backend1 {\n\t\tserver $BACKEND1_INTERNAL_IP:$BACKEND1_PORT;\n\t}\n\tupstream backend2 {\n\t\tserver $BACKEND2_INTERNAL_IP:$BACKEND2_PORT;\n\t}\n\n\tserver {\n\t\tlisten 80;\n\t\tlocation /petclinic/api/ {\n\t\t\tif (\$request_method = GET) {\n\t\t\t\tproxy_pass http://backend1/;\n\t\t\t}\n\t\t\tif (\$request_method = POST) {\n\t\t\t\tproxy_pass http://backend2/;\n\t\t\t}\n\t\t\tif (\$request_method = PUT) {\n\t\t\t\tproxy_pass http://backend2/;\n\t\t\t}\n\t\t\tif (\$request_method = DELETE) {\n\t\t\t\tproxy_pass http://backend2/;\n\t\t\t}\n\t\t}\n\t}" nginx.conf
	elif [[ "$CONFIG" == "5" ]] ; then
		sudo sed -i "/http {/a #konfiguracja5\n\tupstream backend {\n\t\tserver $BACKEND1_INTERNAL_IP:$BACKEND1_PORT;\n\t\tserver $BACKEND2_INTERNAL_IP:$BACKEND2_PORT;\n\t}\n\tserver {\n\t\tlisten 80;\n\t\tlocation /petclinic/api/ {\n\t\t\tproxy_pass http://backend/;\n\t\t}\n\t}" nginx.conf
	fi

	gcloud compute scp nginx.conf "$NGINX":~/nginx.conf --zone $ZONE -q
	gcloud beta compute ssh --zone "$ZONE" "$NGINX"  --project "$PROJECT" <<-EOT
	#!/bin/bash

	sudo mv nginx.conf /etc/nginx/nginx.conf
	sudo sed -e 's/^#*/#/' -i /etc/nginx/sites-enabled/default
	sudo nginx -s reload

	EOT

	echo ""
	echo "Load balancer done ========================="
	echo "============================================"
	echo ""

fi

echo ""
echo "============================================"
echo "Setting up frontend ========================"
echo ""

# Frontend
gcloud beta compute ssh --zone "$ZONE" "$FRONTEND"  --project "$PROJECT" <<-EOT
#!/bin/bash
sudo apt-get update
sudo apt-get install npm -y
sudo apt-get install nginx -y
sudo apt-get install nodejs -y
sudo npm i -g n

# install angular
N | sudo npm i -g @angular/cli@11.0.7

git clone https://github.com/spring-petclinic/spring-petclinic-angular.git
cd spring-petclinic-angular/

# change version of node
sudo n 12
PATH="$PATH"

# Install angular in project
N | npm i --save-dev @angular/cli@11.0.7
npm i

if [[ "$CONFIG" == "1" ]] ; then
	sudo sed -i "s/^.*REST_API_URL: .*$/  REST_API_URL: 'http:\/\/$BACKEND_INTERNAL_IP:$BACKEND_PORT\/petclinic\/api\/'/" src/environments/environment.ts
fi

if [[ "$CONFIG" == "4" || "$CONFIG" == "5" ]] ; then
	sudo sed -i "s/^.*REST_API_URL: .*$/  REST_API_URL: 'http:\/\/$NGINX_INTERNAL_IP:80\/petclinic\/api\/'/" src/environments/environment.ts
fi

ng build --base-href=/petclinic/ --deploy-url=/petclinic/

sudo mkdir /usr/share/nginx/html/petclinic
sudo cp -R dist/ /usr/share/nginx/html/petclinic/dist
	
EOT

gcloud compute scp "$NGINX":/etc/nginx/nginx.conf nginx.conf --zone $ZONE -q

if [[ "$CONFIG" == "1"  || ( $CONFIG =~ ^[45]$ && "$FRONTEND" != "$NGINX" ) ]] ; then
	sudo sed -i 's/http {/http {\n\tserver {\n\t\tlisten 80 default_server;\n\t\troot \/usr\/share\/nginx\/html;\n\t\tindex index.html;\n\t\tlocation \/petclinic\/ {\n\t\t\talias \/usr\/share\/nginx\/html\/petclinic\/dist\/;\n\t\t\ttry_files \$uri\$args \$uri\$args\/ \/petclinic\/index.html;\n\t\t}\n\t}/' nginx.conf
elif [[ "$CONFIG" == "4" && "$FRONTEND" == "$NGINX" ]] ; then
	sudo sed -i "s/http {/http {\n\tupstream backend1 {\n\t\tserver $BACKEND1_INTERNAL_IP:$BACKEND1_PORT;\n\t}\n\tupstream backend2 {\n\t\tserver $BACKEND2_INTERNAL_IP:$BACKEND2_PORT;\n\t}\n\n\tserver {\n\t\t listen 80;\n\t\t location \/petclinic\/ {\n\t\t\t alias \/usr\/share\/nginx\/html\/petclinic\/dist\/;\n\t\t\t try_files \$uri\$args \$uri\$args\/ \/petclinic\/index.html;\n\t\t}\n\t\tlocation \/petclinic\/api\/ {\n\t\t\tif (\$request_method = GET) {\n\t\t\t\tproxy_pass http:\/\/backend1\/;\n\t\t\t}\n\t\t\tif (\$request_method = POST) {\n\t\t\t\tproxy_pass http:\/\/backend2\/;\n\t\t\t}\n\t\t\tif (\$request_method = PUT) {\n\t\t\t\tproxy_pass http:\/\/backend2\/;\n\t\t\t}\n\t\t\tif (\$request_method = DELETE) {\n\t\t\t\tproxy_pass http:\/\/backend2\/;\n\t\t\t}\n\t\t}\n\t}/" nginx.conf
elif [[ "$CONFIG" == "5" && "$FRONTEND" == "$NGINX" ]] ; then
	sudo sed -i "s/http {/http {\n\tupstream backend {\n\t\tserver $BACKEND1_INTERNAL_IP:$BACKEND1_PORT;\n\t\tserver $BACKEND2_INTERNAL_IP:$BACKEND2_PORT;\n\t}\n\n\tserver {\n\t\tlisten 80;\n\t\tlocation \/petclinic\/ {\n\t\t\talias \/usr\/share\/nginx\/html\/petclinic\/dist\/;\n\t\t\ttry_files \$uri\$args \$uri\$args\/ \/petclinic\/index.html;\n\t\t}\n\t\tlocation \/petclinic\/api\/ {\n\t\t\tproxy_pass http:\/\/backend\/;\n\t\t}\n\t}/" nginx.conf
fi

gcloud compute scp nginx.conf "$NGINX":~/nginx.conf --zone $ZONE -q

gcloud beta compute ssh --zone "$ZONE" "$FRONTEND"  --project "$PROJECT" <<-EOT
#!/bin/bash

sudo mv nginx.conf /etc/nginx/nginx.conf
sudo sed -e 's/^#*/#/' -i /etc/nginx/sites-enabled/default
sudo nginx -s reload

EOT

echo ""
echo "Frontend done =============================="
echo "============================================"
echo ""
