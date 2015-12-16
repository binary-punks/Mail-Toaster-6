#!/bin/sh

# Required settings
export TOASTER_HOSTNAME=${TOASTER_HOSTNAME:="mail.example.com"} || exit
export TOASTER_MAIL_DOMAIN=${TOASTER_MAIL_DOMAIN:="example.com"} || exit

# export these in your environment to customize
export BOURNE_SHELL=${BOURNE_SHELL:="bash"}
export JAIL_NET_PREFIX=${JAIL_NET_PREFIX:="172.16.15"}
export JAIL_NET_MASK=${JAIL_NET_MASK:="/12"}
export JAIL_NET_INTERFACE=${JAIL_NET_INTERFACE:="lo1"}
export ZFS_VOL=${ZFS_VOL:="zroot"}
export ZFS_JAIL_MNT=${ZFS_JAIL_MNT:="/jails"}
export ZFS_DATA_MNT=${ZFS_DATA_MNT:="/data"}
export FBSD_MIRROR=${FBSD_MIRROR:="ftp://ftp.freebsd.org"}

# See https://github.com/msimerson/Mail-Toaster-6/wiki/MySQL
export TOASTER_MYSQL=${TOASTER_MYSQL:="1"}
if [ "$TOASTER_MYSQL" = "1" ]; then
	echo "mysql enabled"
fi

if [ "$TOASTER_HOSTNAME" = "mail.example.com" ]; then
	echo; echo "Oops,  you aren't following instructions!"; echo
	echo "See: https://github.com/msimerson/Mail-Toaster-6/wiki/FreeBSD"; echo
	exit
fi
echo "toaster host: $TOASTER_HOSTNAME"

if [ "$TOASTER_MAIL_DOMAIN" = "example.com" ]; then
	echo; echo "Oops, you didn't follow the instructions!"; echo
	echo "See: https://github.com/msimerson/Mail-Toaster-6/wiki/FreeBSD"; echo
	exit
fi
echo "toaster domain: $TOASTER_MAIL_DOMAIN"

_this_shell=$(ps -o args= -p "$$" | grep csh)
if [ -n "$_this_shell" ]; then
    echo; echo "Oops, you didn't follow the instructions! ($_this_shell)"; echo
	echo "See: https://github.com/msimerson/Mail-Toaster-6/wiki/FreeBSD"; echo
	exit
fi
echo "shell: $SHELL"

# very little below here should need customizing. If so, consider opening
# an Issue or PR at https://github.com/msimerson/Mail-Toaster-6
export ZFS_JAIL_VOL="${ZFS_VOL}${ZFS_JAIL_MNT}"
export ZFS_DATA_VOL="${ZFS_VOL}${ZFS_DATA_MNT}"

export FBSD_ARCH; FBSD_ARCH=$(uname -m)
export FBSD_REL_VER; FBSD_REL_VER=$(/bin/freebsd-version | /usr/bin/cut -f1-2 -d'-')
export FBSD_PATCH_VER; FBSD_PATCH_VER=$(/bin/freebsd-version | /usr/bin/cut -f3 -d'-')
export FBSD_PATCH_VER; FBSD_PATCH_VER=${FBSD_PATCH_VER:="p0"}

# the 'base' jail that other jails are cloned from. This will be named as the
# host OS version, ex: base-10.2-RELEASE and the snapshot name will be the OS
# patch level, ex: base-10.2-RELEASE@p7
export BASE_NAME; BASE_NAME="base-$FBSD_REL_VER"
export BASE_VOL;  BASE_VOL="$ZFS_JAIL_VOL/$BASE_NAME"
export BASE_SNAP; BASE_SNAP="${BASE_VOL}@${FBSD_PATCH_VER}"

export STAGE_MNT;  STAGE_MNT="$ZFS_JAIL_MNT/stage"

safe_jailname()
{
	# constrain jail name chars to alpha-numeric and _
	echo "$1" | sed -e 's/[^a-zA-Z0-9]/_/g'
}

export SAFE_NAME; SAFE_NAME=$(safe_jailname stage)

if [ -z "$SAFE_NAME" ]; then
	echo "unset SAFE_NAME"
	exit
fi

echo "safe name: $SAFE_NAME"

zfs_filesystem_exists()
{
	if zfs list -t filesystem "$1" 2>/dev/null | grep -q "^$1"; then
		echo "$1 filesystem exists"
		return 0
	else
		return 1
	fi
}

zfs_snapshot_exists()
{
	if zfs list -t snapshot "$1" 2>/dev/null | grep -q "$1"; then
		echo "$1 snapshot exists"
		return 0
	else
		return 1
	fi
}

base_snapshot_exists()
{
	if zfs_snapshot_exists "$BASE_SNAP"; then
		return 0
	fi

	echo "$BASE_SNAP does not exist, use 'provision base' to create it"
	return 1
}

jail_conf_header()
{
    tee -a /etc/jail.conf <<EO_JAIL_CONF_HEAD

exec.start = "/bin/sh /etc/rc";
exec.stop = "/bin/sh /etc/rc.shutdown";
exec.clean;
mount.devfs;
path = "$ZFS_JAIL_MNT/\$name";
interface = $JAIL_NET_INTERFACE;
host.hostname = \$name;

EO_JAIL_CONF_HEAD
}

get_jail_ip()
{
	case "$1" in
		base)
			echo "$JAIL_NET_PREFIX.2"; return;;
		dns)
			echo "$JAIL_NET_PREFIX.3"; return;;
		mysql)
			echo "$JAIL_NET_PREFIX.4"; return;;
		clamav)
			echo "$JAIL_NET_PREFIX.5"; return;;
		spamassassin)
			echo "$JAIL_NET_PREFIX.6"; return;;
		dspam)
			echo "$JAIL_NET_PREFIX.7"; return;;
		vpopmail)
			echo "$JAIL_NET_PREFIX.8"; return;;
		haraka)
			echo "$JAIL_NET_PREFIX.9"; return;;
		webmail)
			echo "$JAIL_NET_PREFIX.10"; return;;
		monitor)
			echo "$JAIL_NET_PREFIX.11"; return;;
		haproxy)
			echo "$JAIL_NET_PREFIX.12"; return;;
		rspamd)
			echo "$JAIL_NET_PREFIX.13"; return;;
		avg)
			echo "$JAIL_NET_PREFIX.14"; return;;
		dovecot)
			echo "$JAIL_NET_PREFIX.15"; return;;
		redis)
			echo "$JAIL_NET_PREFIX.16"; return;;
		geoip)
			echo "$JAIL_NET_PREFIX.17"; return;;
		stage)
			echo "$JAIL_NET_PREFIX.254"; return;;
	esac

	if echo "$1" | grep -q ^base; then
		echo "$JAIL_NET_PREFIX.2"; return
	fi

	return 2
}

add_jail_conf()
{
	local _jail_ip; _jail_ip=$(get_jail_ip "$1");
	if [ -z "$_jail_ip" ]; then
		echo "can't determine IP for jail $1"
		exit
	fi

	if [ ! -e /etc/jail.conf ]; then
		jail_conf_header
	fi

	if grep -q "$1" /etc/jail.conf; then
		return
	fi

	local _path=""
	local _safe; _safe=$(safe_jailname "$1")
	if [ "$1" != "$_safe" ]; then
		_path="
		path = $ZFS_JAIL_MNT/${1};"
	fi

	tee -a /etc/jail.conf <<EO_JAIL_CONF

$1	{
		ip4.addr = ${_jail_ip};${_path}${JAIL_CONF_EXTRA}
	}
EO_JAIL_CONF
}

stop_jail()
{
	local _safe; _safe=$(safe_jailname "$1")
	echo "stopping jail $1 ($_safe)"
	service jail stop "$_safe"
	jail -r "$_safe" 2>/dev/null
}

stage_unmount()
{
	unmount_ports "$STAGE_MNT"
	unmount_data "$1"
	stage_unmount_dev
	unmount_aux_data "$1"
}

create_staged_fs()
{
	tell_status "stage jail cleanup"
	stop_jail stage
	stage_unmount "$1"

	if zfs_filesystem_exists "$ZFS_JAIL_VOL/stage"; then
		echo "zfs destroy $ZFS_JAIL_VOL/stage"
		zfs destroy -f "$ZFS_JAIL_VOL/stage" || exit	
	fi

	tell_status "stage jail filesystem setup"
	echo "zfs clone $BASE_SNAP $ZFS_JAIL_VOL/stage"
	zfs clone "$BASE_SNAP" "$ZFS_JAIL_VOL/stage" || exit

	stage_mount_ports
	mount_data "$1" "$STAGE_MNT"
	echo
}

unmount_aux_data()
{
	case $1 in
		spamassassin)  unmount_data geoip ;;
		haraka)        unmount_data geoip ;;
		dovecot)       unmount_data vpopmail ;;
	esac
}

mount_aux_data() {
	case $1 in
		spamassassin)  mount_data geoip ;;
		haraka)        mount_data geoip ;;
		dovecot)       mount_data vpopmail ;;
	esac
}

start_staged_jail()
{
	local _name="$1"
	local _path="$2"

	if [ -z "$_name" ]; then _name="$SAFE_NAME"; fi
	if [ -z "$_path" ]; then _path="$STAGE_MNT"; fi

	tell_status "stage jail $_name startup"

	jail -c \
		name=stage \
		host.hostname="$_name" \
		path="$_path" \
		interface="$JAIL_NET_INTERFACE" \
		ip4.addr="$(get_jail_ip stage)" \
		exec.start="/bin/sh /etc/rc" \
		exec.stop="/bin/sh /etc/rc.shutdown" \
		allow.sysvipc=1 \
		mount.devfs \
		$JAIL_START_EXTRA \
		|| exit

	mount_aux_data "$_name"

	pkg -j stage update
}

rename_fs_staged_to_ready()
{
	local _new_vol="$ZFS_JAIL_VOL/${1}.ready"

	# clean up stages that failed promotion
	if zfs_filesystem_exists "$_new_vol"; then
		echo "zfs destroy $_new_vol (failed promotion)"
		zfs destroy "$_new_vol" || exit
	fi

	# get the wait over with before shutting down production jail
	local _tries=0
	local _zfs_rename="zfs rename $ZFS_JAIL_VOL/stage $_new_vol"
	echo "$_zfs_rename"
	until $_zfs_rename; do
		if [ "$_tries" -gt 25 ]; then
			echo "trying to force rename"
			_zfs_rename="zfs rename -f $ZFS_JAIL_VOL/stage $_new_vol"
		fi
		echo "waiting for ZFS filesystem to quiet ($_tries)"
		_tries=$((_tries + 1))
		sleep 5
	done
}

rename_fs_active_to_last()
{
	local LAST="$ZFS_JAIL_VOL/$1.last"
	local ACTIVE="$ZFS_JAIL_VOL/$1"

	if zfs_filesystem_exists "$LAST"; then
		echo "zfs destroy $LAST"
		zfs destroy "$LAST" || exit
	fi

	if ! zfs_filesystem_exists "$ACTIVE"; then
		return
	fi

	local _tries=0
	local _zfs_rename="zfs rename $ACTIVE $LAST"
	echo "$_zfs_rename"
	until $_zfs_rename; do
		if [ $_tries -gt 5 ]; then
			echo "trying to force rename ($_tries)"
			_zfs_rename="zfs rename -f $ACTIVE $LAST"
		fi
		echo "waiting for ZFS filesystem to quiet ($_tries)"
		_tries=$((_tries + 1))
		sleep 5
	done
}

rename_fs_ready_to_active()
{
	echo "zfs rename $ZFS_JAIL_VOL/${1}.ready $ZFS_JAIL_VOL/$1"
	zfs rename "$ZFS_JAIL_VOL/${1}.ready" "$ZFS_JAIL_VOL/$1" || exit
}

tell_status()
{
	echo; echo "   ***   $1   ***"; echo
	sleep 1
}

proclaim_success()
{
	echo
	echo "Success! A new '$1' jail is provisioned"
	echo
}

stage_clear_caches()
{
	echo "clearing pkg cache"
	rm -rf "$STAGE_MNT/var/cache/pkg/*"
}

stage_resolv_conf()
{
	local _nsip; _nsip=$(get_jail_ip dns)
	echo "nameserver $_nsip" | tee "$STAGE_MNT/etc/resolv.conf"
}

promote_staged_jail()
{
	tell_status "promoting jail $1"
	stop_jail stage
	stage_resolv_conf
	stage_unmount "$1"
	stage_clear_caches

	rename_fs_staged_to_ready "$1"

	stop_jail "$1"
	unmount_data "$1" "$ZFS_JAIL_MNT/$1"
	unmount_ports "$ZFS_JAIL_MNT/$1"

	rename_fs_active_to_last "$1"
	rename_fs_ready_to_active "$1"
	add_jail_conf "$1"

	tell_status "start jail $1"
	service jail start "$1" || exit
	proclaim_success "$1"
}

stage_pkg_install()
{
	echo "pkg -j $SAFE_NAME install -y $*"
	pkg -j "$SAFE_NAME" install -y "$@"
}

stage_sysrc()
{
	# don't use -j as this is oft called when jail is not running
	echo "sysrc -R $STAGE_MNT $*"
	sysrc -R "$STAGE_MNT" "$@"
}

stage_make_conf()
{
	if grep -s "$1" "$STAGE_MNT/etc/make.conf"; then
		echo "preserving make.conf settings"
		return
	fi

	echo "$2" | tee -a "$STAGE_MNT/etc/make.conf" || exit
}

stage_exec()
{
	echo "jexec $SAFE_NAME $*"
	jexec "$SAFE_NAME" "$@"
}

stage_mount_ports()
{
	echo "mounting /usr/ports"
	mount_nullfs /usr/ports "$STAGE_MNT/usr/ports" || exit
}

unmount_ports()
{
	if [ ! -d "$1/usr/ports/mail" ]; then
		return
	fi

	if ! mount -t nullfs | grep -q "$1"; then
		return
	fi

	echo "unmounting $1/usr/ports"
	umount "$1/usr/ports" || exit
}

stage_fbsd_package()
{
	echo "installing FreeBSD package $1"
	fetch -m "$FBSD_MIRROR/pub/FreeBSD/releases/$FBSD_ARCH/$FBSD_REL_VER/$1.txz" || exit
	tar -C "$STAGE_MNT" -xvpJf "$1.txz" || exit
}

create_data_fs()
{
	if ! zfs_filesystem_exists "$ZFS_DATA_VOL"; then
		echo "zfs create -o mountpoint=$ZFS_DATA_MNT $ZFS_DATA_VOL"
		zfs create -o "mountpoint=$ZFS_DATA_MNT" "$ZFS_DATA_VOL"
	fi

	local _data; _data="${ZFS_DATA_VOL}/$1"
	if zfs_filesystem_exists "$_data"; then
		echo "$_data already exists"
		return
	fi

	echo "zfs create -o mountpoint=${ZFS_DATA_MNT}/${1} $_data"
	zfs create -o "mountpoint=${ZFS_DATA_MNT}/${1}" "$_data"
}

mount_data()
{
	local _data_vol; _data_vol="$ZFS_DATA_VOL/$1"

	if ! zfs_filesystem_exists "$_data_vol"; then
		echo "no $_data_vol to mount"
		return
	fi

	local _data_mnt; _data_mnt="$ZFS_DATA_MNT/$1"
	local _data_mp;  _data_mp=$(data_mountpoint "$1" "$2")

	if [ ! -d "$_data_mp" ]; then
		mkdir -p "$_data_mp"
	fi

	if mount -t nullfs | grep "$_data_mp"; then
		echo "$_data_mp already mounted!"
		return
	fi

	echo "nullfs mount $_data_mnt $_data_mp"
	mount_nullfs "$_data_mnt" "$_data_mp" || exit
}

unmount_data()
{
	local _data_vol; _data_vol="$ZFS_DATA_VOL/$1"

	if ! zfs_filesystem_exists "$_data_vol"; then
		#echo "no data fs $_data_vol to unmount"
		return
	fi

	local _data_mp=; _data_mp=$(data_mountpoint "$1" "$2")

	if mount -t nullfs | grep "$_data_mp"; then
		echo "unmount data fs $_data_mp"
		umount -t nullfs "$_data_mp"
	fi
}

data_mountpoint()
{
	local _base_dir="$2"
	if [ -z "$_base_dir" ]; then
		_base_dir="$STAGE_MNT"  # defaults to stage
	fi

	case $1 in
		mysql )
			echo "$_base_dir/var/db/mysql"; return ;;
		vpopmail )
			echo "$_base_dir/usr/local/vpopmail"; return ;;
		avg )
			echo "$_base_dir/data/avg"; return ;;
		geoip )
			echo "$_base_dir/usr/local/share/GeoIP"; return ;;
	esac

	echo "$_base_dir/data"
}

stage_unmount_dev()
{
	if ! mount -t devfs | grep -q "$STAGE_MNT/dev"; then
		return
	fi
	echo "unmounting $STAGE_MNT/dev"
	umount "$STAGE_MNT/dev" || exit
}

get_public_facing_nic()
{
	export PUBLIC_NIC

    if [ "$1" = 'ipv6' ]; then
        PUBLIC_NIC=$(netstat -rn | grep default | awk '{ print $4 }' | tail -n1)
    else
        PUBLIC_NIC=$(netstat -rn | grep default | awk '{ print $4 }' | head -n1)
    fi
}

get_public_ip()
{
    get_public_facing_nic "$1"

    export PUBLIC_IP6
    export PUBLIC_IP4

    if [ "$1" = 'ipv6' ]; then
        PUBLIC_IP6=$(ifconfig "$PUBLIC_NIC" | grep 'inet6' | grep -v fe80 | awk '{print $2}' | head -n1)
    else
        PUBLIC_IP4=$(ifconfig "$PUBLIC_NIC" | grep 'inet ' | awk '{print $2}' | head -n1)
    fi
}

mysql_db_exists()
{
	local _query="SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='$1';"
	result=$(echo "$_query" | jexec mysql mysql -s -N)
	if [ -z "$result" ]; then
		echo "$1 db does not exist"
		return 1  # db does not exist
	else
		echo "$1 db exists"
		return 0  # db exists
	fi
}

fetch_and_exec()
{
	local _toaster_sh="https://raw.githubusercontent.com/msimerson/Mail-Toaster-6/master"

	fetch -m "$_toaster_sh/provision-$1.sh"
	sh "provision-$1.sh"
}

provision()
{
	case "$1" in
		host)		fetch_and_exec "$1"; return;;
		base)		fetch_and_exec "$1"; return;;
		dns)		fetch_and_exec "$1"; return;;
		mysql)		fetch_and_exec "$1"; return;;
		clamav)		fetch_and_exec "$1"; return;;
		spamassassin) fetch_and_exec "$1"; return;;
		dspam)		fetch_and_exec "$1"; return;;
		vpopmail)	fetch_and_exec "$1"; return;;
		haraka)		fetch_and_exec "$1"; return;;
		webmail)	fetch_and_exec "$1"; return;;
		monitor)	fetch_and_exec "$1"; return;;
		haproxy)	fetch_and_exec "$1"; return;;
		rspamd)		fetch_and_exec "$1"; return;;
		avg)		fetch_and_exec "$1"; return;;
		dovecot)	fetch_and_exec "$1"; return;;
		redis)		fetch_and_exec "$1"; return;;
		geoip)		fetch_and_exec "$1"; return;;
	esac

    echo "unknown action $1"
}
