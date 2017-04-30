#!/bin/bash

#from https://support.sysally.net/projects/kb/wiki/Script_to_set_yum_priority#Script-to-set-yum-priority

REPODIR="/etc/yum.repos.d"
get_priority_info(){
  sed -n -e "/^\[/h; /priority *=/{ G; s/\n/ /; s/ity=/ity = /; p }" ${REPODIR}/*.repo | sort -k3n
}

MANAGE_COMMAND=""

DNF=0
rpm -q dnf
DNF=`echo $?`

YUM=0
rpm -q yum
YUM=`echo $?`

if [ ${DNF} -eq 0 ]; then
   echo "dnf found. Use dnf."
   MANAGE_COMMAND="dnf"
else
   echo "dnf not found. Search yum."
    if [ ${YUM} -eq 0 ]; then
       echo "yum found. Use yum."
       MANAGE_COMMAND="yum"
       echo "Install yum-priorities."
       yum -y install yum-priorities
    else
       echo "yum not found. Error."
       exit 1
    fi
fi

REPOLIST_COMMAND="${MANAGE_COMMAND} --noplugins repolist"

THIS_DIR=$(cd $(dirname $0);pwd)
TEMPDIR="${THIS_DIR}/tmp"
TEMPFILE_1="${TEMPDIR}/repolist1.tmp"
TEMPFILE_2="${TEMPDIR}/repolist2.tmp"
TEMPFILE_3="${TEMPDIR}/repolist3.tmp"
TEMPFILE_4="${TEMPDIR}/repolist4.tmp"
TEMPFILE_5="${TEMPDIR}/repolist5.tmp"
rm -rf ${TEMPDIR}
mkdir ${TEMPDIR}

echo -e "Please use priority in steps of 5" 
echo -e " eg: base extras and updates can have priority 1 , epel can have priority 5 etc" 
echo -e " This helps to incorporate a repo with priority in between if required in future!" 
echo -n "" 

`${REPOLIST_COMMAND} > ${TEMPFILE_1}`
cat ${TEMPFILE_1}|sed -e "s/\*//"> ${TEMPFILE_2}
cat ${TEMPFILE_2}|sed -e "1d"|sed -e "/repolist:/d"> ${TEMPFILE_3}
cat ${TEMPFILE_3}|awk '{print $1}' > ${TEMPFILE_4}
cat ${TEMPFILE_4}|sed -e "s/\/.*//"> ${TEMPFILE_5}

echo "Enabled yum repos:" 
echo "=======================" 
cat ${TEMPFILE_5}
echo "=======================" 
echo

grep -rl "priority=" ${REPODIR}
EXIST=`echo $?`
if [ ${EXIST} -eq 0 ]; then
   echo -e "Found existing priority setting..exiting! Delete it."
   get_priority_info
   for repo in `cat ${TEMPFILE_5}`
   do
           for file in `find ${REPODIR} -type f`
           do
                   sed -i "/^priority=.*$/d" $file
           done
   done
fi

for repo in `cat ${TEMPFILE_5}`
do
        echo "priority for repo $repo = ?" 
        read priority
        for file in `find ${REPODIR} -type f`
        do
                sed -i "/\[$repo\]/a\priority=$priority" $file
        done
done

get_priority_info

rm -rf ${TEMPDIR}
