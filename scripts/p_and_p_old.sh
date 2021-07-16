sact_res=$(sacctmgr -p show -n assoc where user=$USER | cut -d "|" -f 2,4)
partitions=$(echo "$sact_res" | cut -d "|" -f 1 | sort | uniq |  grep -v "default_no_jobs" )
projects=$(echo "$sact_res" | cut -d "|" -f 2 | sort | uniq | grep -v "^$")
echo "$projects"
echo "@"
echo "$partitions"
