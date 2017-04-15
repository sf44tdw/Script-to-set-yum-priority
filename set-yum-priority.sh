#from https://support.sysally.net/projects/kb/wiki/Script_to_set_yum_priority#Script-to-set-yum-priority

#!/bin/bash
yum -y install yum-priorities
grep -rl "priority=" /etc/yum.repos.d/ && ( echo -e "Found existing priority setting..exiting!" ;exit 1 )
echo -e "Please use priority in steps of 5" 
echo -e " eg: base extras and updates can have priority 1 , epel can have priority 5 etc" 
echo -e " This helps to incorporate a repo with priority in between if required in future!" 
echo -n "" 
yum repolist|sed -n '/repo id/,/repolist:/p'|grep -v "repo id"|grep -v "repolist:"|awk '{print $1}' > repolist.tmp
echo "Enabled yum repos:" 
echo "=======================" 
cat repolist.tmp
echo "=======================" 
echo
echo
for repo in `cat repolist.tmp`
do
        echo "priority for repo $repo = ?" 
        read priority
        for file in `find /etc/yum.repos.d -type f`
        do
                sed -i "/\[$repo\]/a\priority=$priority" $file
        done
done
rm -f repolist.tmp