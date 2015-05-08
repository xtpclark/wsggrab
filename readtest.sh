#!/bin/bash
source /home/ubuntu/wsggrab/custini/asset.ini

echo $CUSTSCRIPT
echo $CTRLFILE
for F in $(cat $CTRLFILE) ; do
result=`psql -At -U postgres -p 5432 < ${CUSTSCRIPT}/${F}`
echo $result
done

exit 0;
