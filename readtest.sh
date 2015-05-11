#!/bin/bash

source /home/ubuntu/wsggrab/custini/asset.ini
#CUSTSCRIPT='${AUTO_UPDATER_UG_SCRIPT_DIR}/customsql'
#CTRLFILE='${CUSTSCRIPT}/manifest.txt'
#RUNCUSTSQLLOAD=1

echo $CUSTSCRIPT
echo $CTRLFILE
for F in $(cat $CTRLFILE) ; do
# result=`psql -At -U postgres -p 5432 < ${CUSTSCRIPT}/${F}`
result=`cat ${CUSTSCRIPT}/${F}`
echo $result
done

exit 0;
