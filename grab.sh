#!/bin/bash
#set -vx
# set -eu
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


sendslack()
{
# Read in from $SETS
# filename=$BACKUPFILE
# MESSAGE='WSGLoad found and downloaded a database named '
payload="payload={\"channel\": \"${SLACK_CHANNEL}\", \"username\": \"${SLACK_USERNAME}\", \"text\": \"${SLACK_MESSAGE}\", \"icon_emoji\": \"${emoji}\"}"
curl -X POST --data-urlencode "${payload}" ${SLACK_HOOK}
}

enviro()
{
BAKDIR=${WORKING}/xtupledb
SQLDIR=${WORKING}/sql
SETS=${WORKING}/ini/settings.ini
CUSTSETS=${WORKING}/ini/${CUSTSET}
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
else
echo "No Settings"
exit 0;
fi
}


setup()
{
#Setup Directories
DIRS='xtupledb'
echo "Creating local directories"
mkdir -p $DIR/ $DIRS
echo "Created ${DIR}/ ${DIRS}"
}

s3check ()
{
DATE="_${DATE}"
echo "DATE is $DATE"
S3BACKUPS=`s3cmd ls s3://bak_$CRMACCT | sed -e's/  */ /g' | cut -d ' ' -f 4 | grep $DATE | grep .backup$ | head -1`
echo "S3Backups = $S3BACKUPS"
}

s3download()
{
BACKUPFILE="${S3BACKUPS##*/}"
if [ -z $BACKUPFILE ];
then
echo "Nothing found"
exit 0;
else
S3SIZE=`s3cmd ls --list-md5 $S3BACKUPS | sed -e's/  */ /g' | cut -d ' ' -f 3`
echo "${S3MD5}"
echo "s3cmd get --skip-existing $S3BACKUPS ${BAKDIR}/${BACKUPFILE}"
STARTTIME=`date "+%T"`
SLACK_MESSAGE="Started DL ${BACKUPFILE} ${STARTTIME}"
sendslack
s3cmd get --skip-existing $S3BACKUPS ${BAKDIR}/${BACKUPFILE}
STOPTIME=`date "+%T"`
SLACK_MESSAGE="Downloaded ${BACKUPFILE} ${STOPTIME}"
sendslack

DLSIZE=`ls -lk ${BAKDIR}/${BACKUPFILE} | cut -d' ' -f5`
echo "On S3 ${S3SIZE}"
echo "On Disk ${DLSIZE}"
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
cmd="sudo pg_ctlcluster ${PGVER} ${PGCLUSTER}-${XTVER}-${XTTYPE} stop --force"
echo "$cmd"
ACT=`$cmd`
SLACK_MESSAGE="Stopped $DBNAME"
sendslack

}

stopmobile()
{
cmd="sudo service xtuple stop ${PGCLUSTER} ${XTVER} ${XTTYPE}"
echo "$cmd"
ACT=`$cmd`
SLACK_MESSAGE="Stopped xtuple service for ${PGCLUSTER}"
sendslack

}


startdb()
{
cmd="sudo pg_ctlcluster ${PGVER} ${PGCLUSTER}-${XTVER}-${XTTYPE} start"
echo "$cmd"
ACT=`$cmd`
SLACK_MESSAGE="Started PG for ${PGCLUSTER}"
sendslack

}

initpgcmd()
{
PGCMD="psql -At -U ${PGUSER} -p ${PGPORT} -h ${PGHOST}"
}

dropdb()
{
DROPDB=`${PGCMD} postgres -c "DROP DATABASE ${DBNAME};"`
echo "Dropped $DBNAME"
SLACK_MESSAGE="Dropped ${DBNAME}"
sendslack

}

createdb()
{
CREATEDB=`${PGCMD} postgres -c "CREATE DATABASE ${DBNAME} OWNER ${PGUSER};"`
echo "Created $DBNAME"
SLACK_MESSAGE="Created ${DBNAME}"
sendslack

}

restoredb()
{
STARTTIME=`date "+%T"`
SLACK_MESSAGE="Started ${DBNAME} Restore: ${STARTTIME}"
sendslack
RESTOREFILE=${BAKDIR}/${BACKUPFILE}
RESTOREDB=`pg_restore -U ${PGUSER} -p ${PGPORT} -h ${PGHOST} -d ${DBNAME} ${RESTOREFILE}`
STOPTIME=`date "+%T"`
SLACK_MESSAGE="Completed ${DBNAME} Restore: ${STOPTIME}"
sendslack
}

checkdb()
{
PGQRY="select now();"
CHECK=`${PGCMD} ${DBNAME} -c "select now();"`
# echo "$CHECK"

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

#echo " "
#echo "${DB} Info"
#echo "==============="
#echo "${XTVER}"
SLACK_MESSAGE="Checked ${DBNAME}"
sendslack

}

runpresql()
{
PRESQL="${WORKING}/custsql/${PRESQL}"
if [ -e $PRESQL ];
then
SLACK_MESSAGE="Running presql file ${PRESQL} on ${DBNAME}"
sendslack
CMD=`${PGCMD} ${DBNAME} < ${PRESQL}`
SLACK_MESSAGE="Ran ${CUSTSQL}"
sendslack
else
echo "no pre file."
fi
}

rundropsql()
{
DROPSQL="${WORKING}/custsql/${DROPSQL}"
if [ -e $DROPSQL ];
then
SLACK_MESSAGE="Running dropsql file ${DROPSQL} on ${DBNAME}"
sendslack
CMD=`${PGCMD} ${DBNAME} < ${PRESQL}`
SLACK_MESSAGE="Ran ${CUSTSQL}"
sendslack
else
echo "no drop file."
fi
}

runpostsql()
{
POSTSQL="${WORKING}/custsql/${POSTSQL}"
if [ -e $POSTSQL ];
then
SLACK_MESSAGE="Running postsql file ${POSTSQL} on ${DBNAME}"
sendslack
CMD=`${PGCMD} ${DBNAME} < ${POSTSQL}`
SLACK_MESSAGE="Ran ${POSTSQL}"
sendslack
else
echo "no postsql file."
fi
}

checkxtver()
{
CKXTVER=`${PGCMD} ${DBNAME} -c "SELECT getpkgver('xt');"`
STOPTIME=`date "+%T"`
SLACK_MESSAGE="XTVERSION is ${CKXTVER}. Done at ${STOPTIME}"
sendslack
}

startmobile()
{
cmd="sudo service xtuple start ${PGCLUSTER} ${XTVER} ${XTTYPE}"
echo "$cmd"
ACT=`$cmd`
STARTTIME=`date "+%T"`
SLACK_MESSAGE="Started xtuple service for ${PGCLUSTER} at ${STARTTIME} on ${EC2IPV4}"
sendslack

}

checkmobile()
{
CKMOB=`${PGCMD} ${DBNAME} -c "SELECT getpkgver('xt');"`
if [ -z $CKMOB ];
then
SLACK_MESSAGE="No Mobile, running updater"
sendslack
else
SLACK_MESSAGE="Mobile ${CKMOB} found. Running ${XTPATH}/scripts/build_app.js -c ${XTCFG} with node $NVER"
sendslack
sudo n $NVER
sudo ${XTPATH}/scripts/build_app.js -c ${XTCFG}
checkxtver
fi
}

sendreport()
{
echo placeholder
}

enviro
settings
custsettings

s3check

s3download
stopdb
stopmobile
startdb
initpgcmd

dropdb
createdb
restoredb

checkdb

runpresql
rundropsql

checkmobile

runpostsql

checkxtver
startmobile
#sendslack
