#!/bin/bash
# set -vx
# set -eu

exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3

EDITOR=vi
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORKING=$DIR
cd $DIR
echo "Working dir is $DIR"

WORKDATE=`/bin/date "+%m%d%y_%s"`
PLAINDATE=`date`

PROG=`basename $0`

usage() {
echo "$PROG usage:"
echo
echo "$PROG -H"
echo "$PROG [ -C Customer Settings ]"
echo
echo "-H print this help and exit"
echo "-C Customer Settings File"
}

ARGS=`getopt H:C: $*`

if [ $? != 0 ] ; then
usage
exit 1
fi

set -- $ARGS
while [ "$1" != -- ] ; do
case "$1" in
-H) usage ; exit 0 ;;
-C) export CUSTSET="$2" ; shift ;;
*) usage ; exit 1 ;;
esac

shift

done

shift

if [ $# -lt 1 ] ; then
echo $PROG: One Customer is needed
usage
exit 1

elif [ $# -gt 1 ] ; then
echo $PROG: ignoring more than the first 1
fi

setup()
{
DIRS='xtupledb custini custbak custsql ini log'
set -- $DIRS
for i in "$@"
do
 if [ -d $i ];
then
echo "Directory $i exists"
else
echo "$i does not exists, creating."
mkdir -p $i
fi
done
}

sendslack()
{
# Read in from $SETS
# filename=$BACKUPFILE
# MESSAGE='WSGLoad found and downloaded a database named '
payload="payload={\"channel\": \"${SLACK_CHANNEL}\", \"username\": \"${SLACK_USERNAME}\", \"text\": \"${SLACK_MESSAGE}\", \"icon_emoji\": \"${emoji}\"}"
curl -s -X POST --data-urlencode "${payload}" ${SLACK_HOOK}
}

enviro()
{
BAKDIR=${WORKING}/xtupledb
SQLDIR=${WORKING}/sql
LOGDIR=${WORKING}/log
SETS=${WORKING}/ini/settings.ini
CUSTSETS=${WORKING}/custini/${CUSTSET}
CUSTBAK=${WORKING}/custbak
EC2IPV4=`ec2metadata --public-ipv4`
}



settings()
{
if [ -e $SETS ]
then
source $SETS
SLACK_MESSAGE="Starting WSGLoad"
sendslack
else
echo "No Settings"
exit 0;
fi
}

custsettings()
{

if [ -e $CUSTSETS ]
then
source $CUSTSETS
exec 1>>${LOGDIR}/${CRMACCT}_${DATE}_log.out 2>&1
echo ""
echo "================"
echo "In ${FUNCNAME[0]}"
echo ""

echo "Using ${CUSTSETS}"
else
echo "No Settings"
exit 0;
fi
}

s3check ()
{
exec 1>>${LOGDIR}/${CRMACCT}_${DATE}_log.out 2>&1
echo ""
echo "================"
echo "In ${FUNCNAME[0]}"
BUDATE="${DATE}"
echo "Backup Date is $DATE"
S3BACKUPS=`s3cmd ls s3://bak_$CRMACCT | sed -e's/  */ /g' | cut -d ' ' -f 4 | grep $BUDATE | grep .backup$ | head -1`
echo "S3Backups = $S3BACKUPS"
}

s3download()
{
exec 1>>${LOGDIR}/${CRMACCT}_${DATE}_log.out 2>&1
echo ""
echo "================"
echo "In ${FUNCNAME[0]}"

BACKUPFILE="${S3BACKUPS##*/}"
if [ -z $BACKUPFILE ];
then
echo "Nothing found"
exit 0;
else
S3SIZE=`s3cmd ls --list-md5 $S3BACKUPS | sed -e's/  */ /g' | cut -d ' ' -f 3`
echo "${S3MD5}"
echo "s3cmd get --no-progress --skip-existing $S3BACKUPS ${BAKDIR}/${BACKUPFILE}"
STARTTIME=`date "+%T"`
SLACK_MESSAGE="Started DL ${BACKUPFILE} ${STARTTIME}"
sendslack
s3cmd get --no-progress --skip-existing $S3BACKUPS ${BAKDIR}/${BACKUPFILE}
STOPTIME=`date "+%T"`
SLACK_MESSAGE="Downloaded ${BACKUPFILE} ${STOPTIME}"
sendslack

DLSIZE=`ls -lk ${BAKDIR}/${BACKUPFILE} | cut -d' ' -f5`
echo "On S3 ${S3SIZE}, On Disk ${DLSIZE}"
if [ ${S3SIZE} = ${DLSIZE} ];
then
echo "Size is good"
else
echo "Bad Download"
# exit 0;
fi

fi

}

stopdb()
{
exec 1>>${LOGDIR}/${CRMACCT}_${DATE}_log.out 2>&1
echo ""
echo "================"
echo "In ${FUNCNAME[0]}"

cmd="sudo pg_ctlcluster ${PGVER} ${PGCLUSTER}-${XTVER}-${XTTYPE} stop --force"
echo "$cmd"
ACT=`$cmd`
SLACK_MESSAGE="Stopped $DBNAME"
sendslack

}

stopmobile()
{
exec 1>>${LOGDIR}/${CRMACCT}_${DATE}_log.out 2>&1
echo ""
echo "================"
echo "In ${FUNCNAME[0]}"

cmd="sudo service xtuple stop ${PGCLUSTER} ${XTVER} ${XTTYPE}"
echo "$cmd"
ACT=`$cmd`
SLACK_MESSAGE="Stopped xtuple service for ${PGCLUSTER}"
sendslack

}


startdb()
{
exec 1>>${LOGDIR}/${CRMACCT}_${DATE}_log.out 2>&1
echo ""
echo "================"
echo "In ${FUNCNAME[0]}"

cmd="sudo pg_ctlcluster ${PGVER} ${PGCLUSTER}-${XTVER}-${XTTYPE} start"
echo "$cmd"
ACT=`$cmd`
SLACK_MESSAGE="Started PG for ${PGCLUSTER}"
sendslack

}

initpgcmd()
{
exec 1>>${LOGDIR}/${CRMACCT}_${DATE}_log.out 2>&1
echo ""
echo "================"
echo "In ${FUNCNAME[0]}"

PGCMD="psql -At -U ${PGUSER} -p ${PGPORT} -h ${PGHOST}"
echo ${PGCMD}
}

dropdb()
{
exec 1>>${LOGDIR}/${CRMACCT}_${DATE}_log.out 2>&1
echo ""
echo "================"
echo "In ${FUNCNAME[0]}"

DROPDB=`${PGCMD} postgres -c "DROP DATABASE ${DBNAME};"`
echo "Dropped $DBNAME"
SLACK_MESSAGE="Dropped ${DBNAME}"
sendslack

}

repairglobals()
{
exec 1>>${LOGDIR}/${CRMACCT}_${DATE}_log.out 2>&1
echo ""
echo "================"
echo "In ${FUNCNAME[0]}"

USRLIST=`${PGCMD} postgres -c "SELECT rolname FROM pg_roles WHERE rolname NOT IN ('postgres','admin','xtrole','monitor');"`

for USR in ${USRLIST}; do

cat << EOF >> ${CRMACCT}_${DATE}_dropusers.sql
DROP USER '$USER';
EOF
done;

${PGCMD} postgres < ${CRMACCT}_${DATE}_dropusers.sql

echo "Dropped Users"
SLACK_MESSAGE="Dropped Users"
sendslack

GLOBALFILE=`s3cmd ls s3://bak_$CRMACCT | sed -e's/  */ /g' | cut -d ' ' -f 4 | grep global | grep $BUDATE | grep .sql$ | head -1`
s3cmd get --no-progress --skip-existing $GLOBALFILE ${BAKDIR}/${GLOBALFILE}

${PGCMD} postgres < ${BAKDIR}/${GLOBALFILE}

echo "Restored Globals"
SLACK_MESSAGE="Restored Globals"
sendslack
}

createdb()
{
exec 1>>${LOGDIR}/${CRMACCT}_${DATE}_log.out 2>&1
echo ""
echo "================"
echo "In ${FUNCNAME[0]}"

CREATEDB=`${PGCMD} postgres -c "CREATE DATABASE ${DBNAME} OWNER ${PGUSER};"`
echo "Created $DBNAME"
SLACK_MESSAGE="Created ${DBNAME}"
sendslack

}

restoredb()
{
exec 1>>${LOGDIR}/${CRMACCT}_${DATE}_log.out 2>&1
echo ""
echo "================"
echo "In ${FUNCNAME[0]}"

STARTTIME=`date "+%T"`
SLACK_MESSAGE="Started ${DBNAME} Restore: ${STARTTIME}"
sendslack
RESTOREFILE=${BAKDIR}/${BACKUPFILE}
RESTOREDB=`pg_restore -U ${PGUSER} -p ${PGPORT} -h ${PGHOST} -d ${DBNAME} ${RESTOREFILE}`
STOPTIME=`date "+%T"`
SLACK_MESSAGE="Completed ${DBNAME} Restore: ${STOPTIME}"
sendslack
}



bakcustschema()
{
exec 1>>${LOGDIR}/${CRMACCT}_${DATE}_log.out 2>&1
echo ""
echo "================"
echo "In ${FUNCNAME[0]}"

STARTTIME=`date "+%T"`
SLACK_MESSAGE="Backing Up Custom Schemas ${CUSTSCHEMALIST} : ${STARTTIME}"
sendslack

for CUSTSCHEMA in $CUSTSCHEMALIST; do
pg_dump -U ${PGUSER} -p ${PGPORT} -h ${PGHOST} --format plain --file ${CUSTBAK}/${DBNAME}_${CUSTSCHEMA}_${WORKDATE}.sql --schema ${CUSTSCHEMA} ${DBNAME}

SLACK_MESSAGE="Completed backup of $CUSTSCHEMA"
sendslack

done;
STOPTIME=`date "+%T"`
SLACK_MESSAGE="Completed Backing Up Custom Schemas ${CUSTSCHEMALIST} : ${STOPTIME}"
sendslack

}

restorecustschema()
{
exec 1>>${LOGDIR}/${CRMACCT}_${DATE}_log.out 2>&1
echo ""
echo "================"
echo "In ${FUNCNAME[0]}"

STARTTIME=`date "+%T"`
SLACK_MESSAGE="Starting Ordered Restore of Custom Schemas : ${CUSTSCHEMARESTOREORDER} ${STARTTIME}"
sendslack

for ORDEREDSCHEMANAME in ${CUSTSCHEMARESTOREORDER}; do

# Add an existance check and log at some point...
CUSTSCHEMADUMP=${CUSTBAK}/${DBNAME}_${ORDEREDSCHEMANAME}_${WORKDATE}.sql

psql -U ${PGUSER} -p ${PGPORT} -h ${PGHOST} ${DBNAME} < ${CUSTSCHEMADUMP}

SLACK_MESSAGE="Completed Ordered Restore of ${CUSTSCHEMADUMP}"
sendslack

done;
STOPTIME=`date "+%T"`
SLACK_MESSAGE="Completed Ordered Restore of Custom Schemas : ${STOPTIME}"
sendslack

}

checkdb()
{
exec 1>>${LOGDIR}/${CRMACCT}_${DATE}_log.out 2>&1
echo ""
echo "================"
echo "In ${FUNCNAME[0]}"

PGQRY="select now();"
CHECK=`${PGCMD} ${DBNAME} -c "select now();"`
echo "$CHECK"

$PGCMD ${DBNAME} < ${SQLDIR}/getpkgver.sql
XTVERS=`$PGCMD ${DBNAME} -c \
"
SELECT data FROM (
SELECT 1,'Co: '||fetchmetrictext('remitto_name') AS data \
UNION \
SELECT 2,'Ap: '||fetchmetrictext('Application')||' v.'||fetchmetrictext('ServerVersion') \
UNION \
SELECT 4,'Pk: '||pkghead_name||':'||getpkgver(pkghead_name) \
FROM pkghead) as foo ORDER BY 1;"`

echo "${DB} Info"
echo "==============="
echo "${XTVERS}"
SLACK_MESSAGE="Checked ${DBNAME}"
sendslack

}

runpresql()
{
exec 1>>${LOGDIR}/${CRMACCT}_${DATE}_log.out 2>&1
echo ""
echo "================"
echo "In ${FUNCNAME[0]}"

PRESQL="${WORKING}/custsql/${PRESQL}"
if [ -e $PRESQL ];
then
SLACK_MESSAGE="Running presql file ${PRESQL} on ${DBNAME}"
echo $SLACK_MESSAGE
sendslack
CMD=`${PGCMD} ${DBNAME} < ${PRESQL}`
SLACK_MESSAGE="Ran ${PRESQL}"
echo $SLACK_MESSAGE
sendslack
else
SLACK_MESSAGE="no presql file."
echo $SLACK_MESSAGE
sendslack
fi
}

rundropsql()
{
exec 1>>${LOGDIR}/${CRMACCT}_${DATE}_log.out 2>&1
echo ""
echo "================"
echo "In ${FUNCNAME[0]}"

DROPSQL="${WORKING}/custsql/${DROPSQL}"
if [ -e $DROPSQL ];
then
SLACK_MESSAGE="Running dropsql file ${DROPSQL} on ${DBNAME}"
echo $SLACK_MESSAGE
sendslack
CMD=`${PGCMD} ${DBNAME} < ${DROPSQL}`
SLACK_MESSAGE="Ran ${DROPSQL}"
echo $SLACK_MESSAGE
sendslack
else
SLACK_MESSAGE="no dropsql file."
echo $SLACK_MESSAGE
sendslack

fi
}

runupdater()
{
# TODO - PUT THE AUTO UPDATER CODE INLINE IN HERE... For Getting the logging in one place...

exec 1>>${LOGDIR}/${CRMACCT}_${DATE}_log.out 2>&1
echo ""
echo "================"
echo "In ${FUNCNAME[0]}"
STARTTIME=`date "+%T"`
SLACK_MESSAGE="Started Headless Updater: ${STARTTIME}"
echo $SLACK_MESSAGE
sendslack

bash $AUTO_UPDATER_PATH -l $AUTO_UPDATER_UG_SCRIPT_DIR $AUTO_UPDATER_TARGET_CONF

STOPTIME=`date "+%T"`
SLACK_MESSAGE="Completed Headless Updater: ${STOPTIME}"
echo $SLACK_MESSAGE
sendslack

}

runpostsql()
{
exec 1>>${LOGDIR}/${CRMACCT}_${DATE}_log.out 2>&1
echo ""
echo "================"
echo "In ${FUNCNAME[0]}"

POSTSQL="${WORKING}/custsql/${POSTSQL}"
if [ -e $POSTSQL ];
then
SLACK_MESSAGE="Running postsql file ${POSTSQL} on ${DBNAME}"
echo $SLACK_MESSAGE
sendslack
CMD=`${PGCMD} ${DBNAME} < ${POSTSQL}`
SLACK_MESSAGE="Ran ${POSTSQL}"
echo $SLACK_MESSAGE
sendslack
else
SLACK_MESSAGE="no postsql file."
echo $SLACK_MESSAGE
sendslack

fi
}

checkxtver()
{
exec 1>>${LOGDIR}/${CRMACCT}_${DATE}_log.out 2>&1
echo ""
echo "================"
echo "In ${FUNCNAME[0]}"

CKXTVER=`${PGCMD} ${DBNAME} -c "SELECT getpkgver('xt');"`

if [ -z $CKXTVER ];
then
CKXTVER='NOT_FOUND'
fi

STOPTIME=`date "+%T"`
SLACK_MESSAGE="XTVERSION is ${CKXTVER}. Done at ${STOPTIME}"
sendslack
}

startmobile()
{
exec 1>>${LOGDIR}/${CRMACCT}_${DATE}_log.out 2>&1
echo ""
echo "================"
echo "In ${FUNCNAME[0]}"

cmd="sudo service xtuple start ${PGCLUSTER} ${XTVER} ${XTTYPE}"
echo "$cmd"
ACT=`$cmd`
STARTTIME=`date "+%T"`
SLACK_MESSAGE="Started xtuple service for ${PGCLUSTER} at ${STARTTIME} on ${EC2IPV4}"
sendslack

}

checkmobile()
{
exec 1>>${LOGDIR}/${CRMACCT}_${DATE}_log.out 2>&1
echo ""
echo "================"
echo "In ${FUNCNAME[0]}"

CKMOB=`${PGCMD} ${DBNAME} -c "SELECT getpkgver('xt');"`
if [ -z $CKMOB ];
then
SLACK_MESSAGE="No Mobile, running updater"
echo "${SLACK_MESSAGE}"
sendslack


else
SLACK_MESSAGE="Mobile ${CKMOB} found. Running ${XTPATH}/scripts/build_app.js -c ${XTCFG} with node $NVER"
echo "${SLACK_MESSAGE}"
sendslack
sudo n $NVER
sudo ${XTPATH}/scripts/build_app.js -c ${XTCFG}
checkxtver
fi
}

runbuildapp()
{
exec 1>>${LOGDIR}/${CRMACCT}_${DATE}_log.out 2>&1
echo ""
echo "================"
echo "In ${FUNCNAME[0]}"
STARTTIME=`date "+%T"`
SLACK_MESSAGE="Running Build:${STARTTIME}: ${XTPATH}/scripts/build_app.js -d ${DBNAME} -c ${XTCFG} with n $NVER"
echo "${SLACK_MESSAGE}\n"
sendslack
sudo n $NVER
sudo ${XTPATH}/scripts/build_app.js -d ${DBNAME} -c ${XTCFG}
checkxtver
STOPTIME=`date "+%T"`
SLACK_MESSAGE="Completed Applying Build:${STOPTIME}:"
echo "${SLACK_MESSAGE}\n"
sendslack
}

runxdruple()
{
exec 1>>${LOGDIR}/${CRMACCT}_${DATE}_log.out 2>&1
echo ""
echo "================"
echo "In ${FUNCNAME[0]}"
SLACK_MESSAGE="Applying xDruple: ${XTPATH}/scripts/build_app.js -c ${XTCFG} -e ${XTPRIPATH}/source/xdruple with node $NVER"
echo "${SLACK_MESSAGE}"
sendslack
sudo n $NVER
sudo ${XTPATH}/scripts/build_app.js -c ${XTCFG} -e ${XTPRIPATH}/source/xdruple
checkxtver
}

sendtos3()
{
true
}


sendreport()
{
echo placeholder
}

makereport()
{
EC2DATA=`ec2metadata --instance-id --local-ipv4 --public-ipv4 --availability-zone`

REPORT=$REPORTDIR/${CUST}_${WORKDATE}.log
cat << EOF >> $REPORT

Install Date: ${PLAINDATE}

Customer: ${CUST}
Mobile Version: ${XTVER}
Edition: ${EDITION}

MobileURL: $XTFQDN
AdminUser: $XTADMIN
AdminPass: $XTPASS

==Desktop Client Information==
Client Version: ${XTAPPVER}
Server: $XTFQDN
Port: $CUSTPORT
Database: ${DB}

==Details for ${DB}==
DB linked to: ${ORIGDB}
$XTDETAIL

==xTuple Server Command==
$CMD

==EC2Data==
$EC2DATA

EOF
}

mailreport()
{
REPORT=${LOGDIR}/${CRMACCT}_${DATE}_log.out
MAILPRGM=`which mutt`
if [ -z $MAILPRGM ]; then
echo "Couldn't mail anything - no mailer."
echo "Set up Mutt."
true
else
MSUB="Mobile Instance loaded by xsInstaller for you on $HOSTNAME"
MES="${REPORT}"

$MAILPRGM -s "WSG CloudOps Mobilized $DBNAME for you on $HOSTNAME" $MTO < $MES
fi
}

# We want to do this every time.
enviro
settings
custsettings

if [[ "$RUNDLNEWDB" == 1 ]];
then
s3check
s3download
else
echo "Not checking S3"
fi

# Probably want to do this every time.
stopdb
stopmobile
startdb
initpgcmd

if [[ "$RUNRESTORE" == 1 ]];
then
dropdb
createdb
restoredb
else
echo "Not dropping, creating or restoring"
fi

if [[ "$REPAIRGLOBALS" == 1 ]];
then
repairglobals
else
echo "Not messing with globals"
fi

if [[ "$RUNCUSTSCHEMABAK" == 1 ]];
then
bakcustschema
else
echo "Not backing up custom schemas"
fi


if [[ "$RUNPRE" == 1 ]];
 then
    runpresql
 else
 echo "Skipping runpresql"
fi

if [[ "$RUNDROP" == 1 ]];
 then
    rundropsql
 else
 echo "Skipping rundropsql"
fi

if [[ "$RUNUPDATER" == 1 ]];
 then
    runupdater
fi

if [[ "$RUNBUILDAPP" == 1 ]];
 then
runbuildapp
else
echo "Not running build_app"
fi

if [[ "$RUNXDRUPLE" == 1 ]];
 then
runxdruple
else
echo "Not running build_app for xdruple"
fi

if [[ "$RUNCUSTSCHEMARESTORE" == 1 ]];
then
restorecustschema
else
echo "Not restoring custom schemas"
fi


if [[ "$RUNPOST" == 1 ]];
 then
    runpostsql
 else
 echo "Skipping runpostsql"
fi


if [[ "$STARTMOBILE" == 1 ]];
 then
   stopmobile 
   startmobile
 else
 echo "Skipping startstopmobile"
fi


if [[ "$RUNMOBILE" == 1 ]];
 then
  checkdb
  runpresql
  rundropsql

if [[ "$RUNUPDATERAFTERMOBILE" == 1 ]];
 then
  runupdater
 else
echo "Not running updater after mobile"
fi

  checkmobile
  checkxtver
  startmobile


else
  checkdb
  checkxtver
fi

mailreport


exit 0;

