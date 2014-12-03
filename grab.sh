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

#!/bin/bash
PROG=`basename $0`

usage() {
echo "$PROG usage:"
echo
echo "$PROG -H"
echo "$PROG [ -c CRMACCNTNAME ] [ -D DATE]"
echo
echo "-H print this help and exit"
echo "-c CRMACCOUNT Name"
echo "-D date range"
}

ARGS=`getopt H:c:D: $*`

if [ $? != 0 ] ; then
usage
exit 1
fi

set -- $ARGS
while [ "$1" != -- ] ; do
case "$1" in
-H) usage ; exit 0 ;;
-c) export CRMACCT="$2" ; shift ;;
-D) export DATE="$2" ; shift ;;
-C) export CUSTSET="$2" ; shift ;;
*) usage ; exit 1 ;;
esac

shift

done

shift

if [ $# -lt 1 ] ; then
echo $PROG: One db to backup is required
usage
exit 1

elif [ $# -gt 1 ] ; then
echo $PROG: multiple dbs named - ignoring more than the first 1
fi


enviro()
{

BAKDIR=${WORKING}/xtupledb
SETS=${WORKING}/ini/settings.ini
}

settings()
{
if [ -e $SETS ]
then
source $SETS
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
S3BACKUPS=`s3cmd ls s3://bak_$CRMACCT | sed -e's/  */ /g' | cut -d ' ' -f 4 | grep $DATE | grep .backup$ | head -1`
}

s3download()
{
BACKUPFILE="${S3BACKUPS##*/}"
if [ -z $BACKUPFILE ];
then
echo "Nothing found"
exit 0;
else
echo "s3cmd get $S3BACKUPS ${BAKDIR}/${BACKUPFILE}"
# s3cmd get $S3BACKUPS ${BAKDIR}/${BACKUPFILE}
fi
}

sendslack()
{
# Read in from $SETS

filename=$BACKUPFILE
MESSAGE='WSGLoad found a database named '

payload="payload={\"channel\": \"${SLACK_CHANNEL}\", \"username\": \"${SLACK_USERNAME}\", \"text\": \"${MESSAGE}${filename}\", \"icon_emoji\": \"${emoji}\"}"

curl -X POST --data-urlencode "${payload}" ${SLACK_HOOK}
}

enviro
settings
s3check
s3download
sendslack
