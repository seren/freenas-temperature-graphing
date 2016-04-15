# freenas-temperature-graphing
Bash scripts using rrdtool to graph FreeNAS CPU and drive temperatures

Copy the .sh files to a directory on the server and create cronjobs to 
run them. You can edit your cron jobs with the command `crontab -e` (see crontabs.txt for example entries). These need to be run as root (to access the SMART stats), so put the cron entries in root's crontab. You may need to re-add them after FreeNAS updates are applied.

## Examples:

![CPU temperatures per minute](examples/temps-1min-cpus.png)
![Drive temperatures per minute](examples/temps-1min-drives.png)

![CPU temperatures per 5 minutes](examples/temps-5min-cpus.png)
![Drive temperatures per 5 minutes](examples/temps-5min-drives.png)

The color scheme is easy to change. Pull requests welcome
