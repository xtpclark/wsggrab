wsggrab
=======

web services group db grabber

Usage:
./grab.sh -C nameof.ini

<pre>
Steps:
Check for recent backup
Download backup
`Verify download completed completely`
Stop all db connections
Drop existing db
Recreate db, same name
Load db, same name
`Verify the database restored fully`
Drop custom objects - From `wtf-did-you-do` script
Apply upgrades - Using automatic updater if production db hasn't been mobilized
`Verify upgrades worked`
Apply Mobile - This can also upgrade a mobilized database
`Verify mobilize worked`
Send notification it's done.
</pre>
