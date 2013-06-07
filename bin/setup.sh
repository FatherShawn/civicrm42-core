#!/usr/bin/env bash

CALLEDPATH=`dirname $0`

# Convert to an absolute path if necessary
case "$CALLEDPATH" in
  .*)
    CALLEDPATH="$PWD/$CALLEDPATH"
    ;;
esac

if [ ! -f "$CALLEDPATH/setup.conf" ]; then
  echo
  echo "Missing configuration file. Please copy $CALLEDPATH/setup.conf.txt to $CALLEDPATH/setup.conf and edit it."
  exit 1
fi

source "$CALLEDPATH/setup.conf"

if [ "$1" = '-h' ] || [ "$1" = '--help' ]; then
  echo; echo Usage: setup.sh [schema file] [database data file] [database name] [database user] [database password] [additional args]; echo
  exit 0
fi


# fetch command line arguments if available
if [ ! -z $1 ] ; then SCHEMA=$1; fi
if [ ! -z $2 ] ; then DBLOAD=$2; fi
if [ ! -z $3 ] ; then DBNAME=$3; fi
if [ ! -z $4 ] ; then DBUSER=$4; fi
if [ ! -z $5 ] ; then DBPASS=$5; fi

# verify if we have at least DBNAME given
if [ -z $DBNAME ] ; then
  echo "No database name defined!"
  exit 1
fi
if [ -z $DBUSER ] ; then
  echo "No database username defined!"
  exit 1
fi
if [ -z $DBPASS ] ; then
  read -p "Database password:"
  DBPASS=$REPLY
fi

# run code generator if it's there - which means it's
# checkout, not packaged code
if [ -d $CALLEDPATH/../xml ]; then
  cd $CALLEDPATH/../xml
  "$PHP5PATH"php GenCode.php $SCHEMA
fi

# someone might want to use empty password for development,
# let's make it possible - we asked before.
if [ -z $DBPASS ]; then # password still empty
  PASSWDSECTION=""
else
  PASSWDSECTION="-p$DBPASS"
fi

cd $CALLEDPATH/../sql
echo; echo "Dropping civicrm_* tables from database $DBNAME"
# mysqladmin -f -u $DBUSER $PASSWDSECTION $DBARGS drop $DBNAME
MYSQLCMD="mysql -u$DBUSER $PASSWDSECTION $DBARGS $DBNAME"
echo "SELECT table_name FROM information_schema.TABLES  WHERE TABLE_SCHEMA='${DBNAME}' AND TABLE_TYPE = 'VIEW'" \
  | $MYSQLCMD \
  | grep '^\(civicrm_\|log_civicrm_\)' \
  | awk -v NOFOREIGNCHECK='SET FOREIGN_KEY_CHECKS=0;' 'BEGIN {print NOFOREIGNCHECK}{print "drop view " $1 ";"}' \
  | $MYSQLCMD
echo "SELECT table_name FROM information_schema.TABLES  WHERE TABLE_SCHEMA='${DBNAME}' AND TABLE_TYPE = 'BASE TABLE'" \
  | $MYSQLCMD \
  | grep '^\(civicrm_\|log_civicrm_\)' \
  | awk -v NOFOREIGNCHECK='SET FOREIGN_KEY_CHECKS=0;' 'BEGIN {print NOFOREIGNCHECK}{print "drop table " $1 ";"}' \
  | $MYSQLCMD


echo; echo Creating database structure
mysql -u $DBUSER $PASSWDSECTION $DBARGS $DBNAME < civicrm.mysql

# load civicrm_generated.mysql sample data unless special DBLOAD is passed
if [ -z $DBLOAD ]; then
    echo; echo Populating database with example data - civicrm_generated.mysql
    mysql -u $DBUSER $PASSWDSECTION $DBARGS $DBNAME < civicrm_generated.mysql
else
    echo; echo Populating database with required data - civicrm_data.mysql
    mysql -u $DBUSER $PASSWDSECTION $DBARGS $DBNAME < civicrm_data.mysql
    echo; echo Populating database with $DBLOAD data
    mysql -u $DBUSER $PASSWDSECTION $DBARGS $DBNAME < $DBLOAD
fi

# load additional script if DBADD defined
if [ ! -z $DBADD ]; then
    echo; echo Loading $DBADD
    mysql -u $DBUSER $PASSWDSECTION $DBARGS $DBNAME < $DBADD
fi

# run the cli script to build the menu and the triggers
cd $CALLEDPATH/..
"$PHP5PATH"php bin/cli.php -e System -a flush --triggers 1 --session 1

# reset config_backend and userFrameworkResourceURL which gets set
# when config object is initialized
mysql -u$DBUSER $PASSWDSECTION $DBARGS $DBNAME -e "UPDATE civicrm_domain SET config_backend = NULL; UPDATE civicrm_setting SET value = NULL WHERE name = 'userFrameworkResourceURL';"

echo; echo "Setup Complete. Logout from your CMS to avoid session conflicts."

# to generate a new data file do the following from the sql directory:
# mysqladmin -f -u $DBUSER $PASSWDSECTION drop $DBNAME
# mysqladmin -f -u $DBUSER $PASSWDSECTION create $DBNAME
# mysql -u $DBUSER $PASSWDSECTION $DBNAME < civicrm.mysql
# mysql -u $DBUSER $PASSWDSECTION $DBNAME < civicrm_data.mysql
# mysql -u $DBUSER $PASSWDSECTION $DBNAME < civicrm_sample.mysql
# mysql -u $DBUSER $PASSWDSECTION $DBNAME < zipcodes.mysql
# php GenerateData.php
# echo "drop table zipcodes ; update civicrm_domain set config_backend = null; UPDATE civicrm_setting SET value = NULL WHERE name = 'userFrameworkResourceURL' OR name = 'imageUploadURL';" | mysql -u $DBUSER $PASSWDSECTION $DBNAME
# mysqldump -c -e -t -n -u $DBUSER $PASSWDSECTION $DBNAME  > civicrm_generated.mysql
# add sample custom data
# cat civicrm_sample_custom_data.mysql >> civicrm_generated.mysql
# cat ../CRM/Case/xml/configuration.sample/SampleConfig.mysql >> civicrm_generated.mysql
