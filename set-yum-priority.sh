#!/bin/bash

#from https://support.sysally.net/projects/kb/wiki/Script_to_set_yum_priority#Script-to-set-yum-priority

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root." >&2
  exit 254
fi

readonly ROOT_HOME='/root'
readonly ROOT_BASH_PROFILE_PATH="${ROOT_HOME}/.bash_profile"
readonly ROOT_PROFILE_PATH="${ROOT_HOME}/.profile"

if [ -f "${ROOT_BASH_PROFILE_PATH}" ]; then
  source "${ROOT_BASH_PROFILE_PATH}" >/dev/null 2>&1 || exit 200
elif [ -f "${ROOT_PROFILE_PATH}" ]; then
  source "${ROOT_PROFILE_PATH}" >/dev/null 2>&1 || exit 210
else
  exit 220
fi

#このスクリプトの名前。
readonly MY_NAME="$(basename "${0}")"

#ロックファイルのパス
_lockfile="/tmp/${MY_NAME}.lock"

readonly MY_EXEC_DATE="$(date +%Y%m%d-%H%M%S)"
readonly MY_PID="${$}"

readonly ETCDIR="/etc"
readonly REPO_DIR_NAME="yum.repos.d"
readonly REPODIR="${ETCDIR}/${REPO_DIR_NAME}"
readonly REPO_OVERRIDE_DIR="/etc/dnf/repos.override.d"

function delete_tempdir() {
	local -r TEMP_DIR_PATH="${1}"
	if [ -d "${TEMP_DIR_PATH}" ]; then
		if ! rm -rf "${TEMP_DIR_PATH}"; then
			echo "作業フォルダ削除失敗。戻り値はrmのものになる。作業フォルダ=${TEMP_DIR_PATH}"1 >&2
			exit "${?}"
		fi
	fi
	return 0
}

function delete_lock_file_and_exit() {
	local -r TEMP_DIR_PATH="${1}"
	delete_tempdir "${TEMP_DIR_PATH}"
	local -r EXIT_CODE="${2}"
	expr "${EXIT_CODE}" + 1 >/dev/null 2>&1
	local -r ret="${?}"
	if [ "${ret}" -ge 2 ]; then
		echo "指定された戻り値が数字ではない。戻り値=${EXIT_CODE}"1 >&2
		exit 100
	fi
	if [ -h "${_lockfile}" ]; then
		if ! rm -f "${_lockfile}" >/dev/null 2>&1; then
			echo "ロックファイル削除失敗。戻り値はrmのものになる。ロックファイル=${_lockfile}"1 >&2
			exit "${?}"
		fi
	fi
	exit "${EXIT_CODE}"
}

function usage_exit() {
	echo "Usage: $0 [-e] [-l]" 1>&2
	echo '有効と設定されているdnfリポジトリの優先順位を設定/表示する。
        -e 設定(既存の優先順位設定は削除される。)
        -l 設定済みの優先順位を表示する。未設定の場合は何も表示されない。' 1>&2
	exit 0
}

function get_priority_info() {
	local -r REPOSITORY_LIST="${1}"
	local -r COMMAND="${2}"
	local -r PRIORITY_LIST_FROM_ORIGINAL_REPOFILE=$(sed -n -e "/^\[/h; /priority *=/{ G; s/\n/ /; s/ity=/ity = /; p }" ${REPODIR}/*.repo | sort -k3n)
	echo "Priority parameter from repo file."
	echo "======================="
	echo "${PRIORITY_LIST_FROM_ORIGINAL_REPOFILE}"
	echo "======================="
	echo
	echo "Priority parameter from repo command.(For dnf5 or later.)"
	echo "======================="
	for repo in $(cat "${REPOSITORY_LIST}"); do
		GET_COMMAND="${COMMAND} repo info ${repo} 2>/dev/null"
		REPO_INFO_FROM_COMMAND=$(eval "${GET_COMMAND}")
		echo "${REPO_INFO_FROM_COMMAND}" | awk -F': ' '/^Repo ID/ { repo_id = $2 } /^Priority/ { print "priority = " $2 " [" repo_id "]" }'
	done
	echo "======================="
	echo
	return 0
}

ENABLE_e="f"
ENABLE_l="f"

while getopts "el" OPT; do
	case $OPT in
	e)
		ENABLE_e="t"
		;;
	l)
		ENABLE_l="t"
		;;
	: | \?)
		usage_exit
		;;
	esac
done

shift $((OPTIND - 1))

if [ "${ENABLE_e}" != "t" ] && [ "${ENABLE_l}" != "t" ]; then
	usage_exit
fi

#多重起動防止機講
# 同じ名前のプロセスが起動していたら起動しない。
readonly _lockfile="/tmp/${MY_NAME}.lock"
ln -s /dummy "${_lockfile}" 2>/dev/null || {
	echo 'Cannot run multiple instance.'
	exit 110
}
trap 'rm "${_lockfile}"; exit' SIGHUP SIGINT SIGQUIT SIGTERM

readonly TEMPDIR="/tmp/${MY_NAME}_${MY_EXEC_DATE}_${MY_PID}"
readonly TEMPFILE_1="${TEMPDIR}/repolist1.tmp"
readonly TEMPFILE_2="${TEMPDIR}/repolist2.tmp"
readonly TEMPFILE_3="${TEMPDIR}/repolist3.tmp"
readonly TEMPFILE_4="${TEMPDIR}/repolist4.tmp"
readonly TEMPFILE_5="${TEMPDIR}/repolist5.tmp"
readonly TEMPFILE_6="${TEMPDIR}/repolist6.tmp"
rm -rf "${TEMPDIR}"
mkdir -p "${TEMPDIR}"

MANAGE_COMMAND=""

DNF=0
readonly DNF_PACKAGE_LIST=$(rpm -qa | grep dnf)
DNF=$(echo "${DNF_PACKAGE_LIST}" | wc -l)

if [ "${DNF}" -ne 0 ]; then
	echo "dnf found. Use dnf."
	MANAGE_COMMAND=$(which dnf)
else
	echo "dnf not found. Error."
	delete_lock_file_and_exit "${TEMPDIR}" 1
fi

readonly REPOLIST_COMMAND="${MANAGE_COMMAND} --noplugins repolist"

echo -e "Please use priority in steps of 5"
echo -e " eg: base extras and updates can have priority 1 , epel can have priority 5 etc"
echo -e " This helps to incorporate a repo with priority in between if required in future!"
echo -n ""

#rpmコマンドでリポジトリを追加した直後の場合、リポジトリを追加した旨が表示されることがあるので1回無駄に実行する。
${REPOLIST_COMMAND} >/dev/null 2>&1

${REPOLIST_COMMAND} >"${TEMPFILE_1}"

#リポジトリIDの頭に余計な*があれば除去する。(例:fedoraのdnfコマンド)
cat "${TEMPFILE_1}" | sed -e "s/\*//" >"${TEMPFILE_2}"

#フィールド名の除去
cat "${TEMPFILE_2}" | sed -e "1d" | sed -e "/repolist:/d" >"${TEMPFILE_3}"

#リポジトリID抽出
cat "${TEMPFILE_3}" | awk '{print $1}' >"${TEMPFILE_4}"

#リポジトリIDに要らないスラッシュつき文字列があれば除去する。(例:CentOS7のアーキテクチャ名)
cat "${TEMPFILE_4}" | sed -e "s/\/.*//" >"${TEMPFILE_5}"

#リポジトリID重複除去
cat "${TEMPFILE_5}" | sort | uniq >"${TEMPFILE_6}"

[ "${ENABLE_l}" = "t" ] && get_priority_info "${TEMPFILE_6}" "${MANAGE_COMMAND}" && delete_lock_file_and_exit "${TEMPDIR}" 0

#現状をバックアップするコマンドを生成。
TAR_CMD='tar'
TAR_CMD+=' '
TAR_CMD+='Jcf'
TAR_CMD+=' '
TAR_CMD+='"'
TAR_CMD+="${ETCDIR}/${MY_NAME}_${MY_EXEC_DATE}_${MY_PID}.tar.xz"
TAR_CMD+='"'
TAR_CMD+=' '
TAR_CMD+='"'
TAR_CMD+="${REPODIR}"
TAR_CMD+='"'
#dnf5で、変更する値は書き換え用のファイルに記載するようになったのでバックアップ対象に追加。
if [ -d "${REPO_OVERRIDE_DIR}" ]; then
	TAR_CMD+=' '
	TAR_CMD+='"'
	TAR_CMD+="${REPO_OVERRIDE_DIR}"
	TAR_CMD+='"'
fi
#現状をバックアップ。
eval "${TAR_CMD}" || delete_lock_file_and_exit "${TEMPDIR}" 2

echo "Enabled yum repos:"
echo "======================="
cat "${TEMPFILE_6}"
echo "======================="
echo

#forループにしないとreadが入力待ちにならない。
for repo in $(cat "${TEMPFILE_6}"); do
	priority="0"
	until [ "${priority}" -ne 0 ]; do
		read -r -p "priority for repo ${repo} = ?(1-99)" priority
		expr "${priority}" + 1 >&/dev/null
		ret="${?}"
		if [ "${ret}" -ge 2 ]; then
			priority="0"
		fi
		if [ "${priority}" -le 0 ]; then
			priority="0"
		fi
		if [ "${priority}" -ge 100 ]; then
			priority="0"
		fi
	done
	DNF_RETURN=0
	dnf config-manager --setopt="${repo}.priority=${priority}" --save
	DNF_RETURN="${?}"
	#dnf5ではコマンドラインの形式が変わったので、旧コマンドで失敗したら新コマンドでリトライする。
	if [ "${DNF_RETURN}" -ne 0 ]; then
		dnf config-manager setopt "${repo}.priority=${priority}" || delete_lock_file_and_exit "${TEMPDIR}" 10
	fi
done

get_priority_info "${TEMPFILE_6}" "${MANAGE_COMMAND}"

delete_lock_file_and_exit "${TEMPDIR}" 0
