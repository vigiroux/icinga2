#!/bin/sh
# Icinga 2 | (c) 2012 Icinga GmbH | GPLv2+
# Except of function urlencode which is Copyright (C) by Brian White (brian@aljex.com) used under MIT license

PROG="`basename $0`"
ICINGA2HOST="`hostname`"
MAILBIN="mail"

if [ -z "`which $MAILBIN`" ] ; then
  echo "$MAILBIN not found in \$PATH. Consider installing it."
  exit 1
fi

## Function helpers
Usage() {
cat << EOF

Required parameters:
  -d LONGDATETIME (\$icinga.long_date_time\$)
  -e SERVICENAME (\$service.name\$)
  -l HOSTNAME (\$host.name\$)
  -n HOSTDISPLAYNAME (\$host.display_name\$)
  -o SERVICEOUTPUT (\$service.output\$)
  -r USEREMAIL (\$user.email\$)
  -s SERVICESTATE (\$service.state\$)
  -t NOTIFICATIONTYPE (\$notification.type\$)
  -u SERVICEDISPLAYNAME (\$service.display_name\$)

Optional parameters:
  -4 HOSTADDRESS (\$address\$)
  -6 HOSTADDRESS6 (\$address6\$)
  -b NOTIFICATIONAUTHORNAME (\$notification.author\$)
  -c NOTIFICATIONCOMMENT (\$notification.comment\$)
  -i ICINGAWEB2URL (\$notification_icingaweb2url\$, Default: unset)
  -f MAILFROM (\$notification_mailfrom\$, requires GNU mailutils (Debian/Ubuntu) or mailx (RHEL/SUSE))
  -v (\$notification_sendtosyslog\$, Default: false)

EOF
}

Help() {
  Usage;
  exit 0;
}

Error() {
  if [ "$1" ]; then
    echo $1
  fi
  Usage;
  exit 1;
}

urlencode() {
  local LANG=C i=0 c e s="$1"

  while [ $i -lt ${#1} ]; do
    [ "$i" -eq 0 ] || s="${s#?}"
    c=${s%"${s#?}"}
    [ -z "${c#[[:alnum:].~_-]}" ] || c=$(printf '%%%02X' "'$c")
    e="${e}${c}"
    i=$((i + 1))
  done
  echo "$e"
}

## Main
while getopts 4:6:b:c:d:e:f:hi:l:n:o:r:s:t:u:v: opt
do
  case "$opt" in
    4) HOSTADDRESS=$OPTARG ;;
    6) HOSTADDRESS6=$OPTARG ;;
    b) NOTIFICATIONAUTHORNAME=$OPTARG ;;
    c) NOTIFICATIONCOMMENT=$OPTARG ;;
    d) LONGDATETIME=$OPTARG ;; # required
    e) SERVICENAME=$OPTARG ;; # required
    f) MAILFROM=$OPTARG ;;
    h) Usage ;;
    i) ICINGAWEB2URL=$OPTARG ;;
    l) HOSTNAME=$OPTARG ;; # required
    n) HOSTDISPLAYNAME=$OPTARG ;; # required
    o) SERVICEOUTPUT=$OPTARG ;; # required
    r) USEREMAIL=$OPTARG ;; # required
    s) SERVICESTATE=$OPTARG ;; # required
    t) NOTIFICATIONTYPE=$OPTARG ;; # required
    u) SERVICEDISPLAYNAME=$OPTARG ;; # required
    v) VERBOSE=$OPTARG ;;
   \?) echo "ERROR: Invalid option -$OPTARG" >&2
       Usage ;;
    :) echo "Missing option argument for -$OPTARG" >&2
       Usage ;;
    *) echo "Unimplemented option: -$OPTARG" >&2
       Usage ;;
  esac
done

shift $((OPTIND - 1))

## Keep formatting in sync with mail-host-notification.sh
for P in LONGDATETIME HOSTNAME HOSTDISPLAYNAME SERVICENAME SERVICEDISPLAYNAME SERVICEOUTPUT SERVICESTATE USEREMAIL NOTIFICATIONTYPE ; do
  eval "PAR=\$${P}"

  if [ ! "$PAR" ] ; then
    Error "Required parameter '$P' is missing."
  fi
done

## Add line-breaks to very long service-outputs to avoid
## mail servers rejecting the message because of hitting
## a max. message line limit (RFC821 max. 1000b per line)
##
## but move on, if the strings seems to take care of its
## own formating (containing \n or \r)
if [ ! -z "${SERVICEOUTPUT}" ] \
   && [ "${#SERVICEOUTPUT}" -ge 900 ] \
   && ! [[ "${SERVICEOUTPUT}" =~ ($'\n'|$'\r') ]]; then
   TMP_OUTPUT=''
   STR_CNT=0
   STR_STEPS=600
   while [ $STR_CNT -lt ${#SERVICEOUTPUT} ]; do
      TMP_OUTPUT+="${SERVICEOUTPUT:$STR_CNT:$STR_STEPS}\\n"
      ((STR_CNT+=STR_STEPS)) || true
   done
   SERVICEOUTPUT="${TMP_OUTPUT}"
   unset TMP_OUTPUT STR_CNT
fi

## Build the message's subject
SUBJECT="[$NOTIFICATIONTYPE] $SERVICEDISPLAYNAME on $HOSTDISPLAYNAME is $SERVICESTATE!"
ENCODED_SUBJECT="=?utf-8?B?$(base64 --wrap=0 <<< "$SUBJECT")?="

## Build the notification message
NOTIFICATION_MESSAGE=`cat << EOF
***** Service Monitoring on $ICINGA2HOST *****

$SERVICEDISPLAYNAME on $HOSTDISPLAYNAME is $SERVICESTATE!

Info:    $SERVICEOUTPUT

When:    $LONGDATETIME
Service: $SERVICENAME
Host:    $HOSTNAME
EOF
`

## Check whether IPv4 was specified.
if [ -n "$HOSTADDRESS" ] ; then
  NOTIFICATION_MESSAGE="$NOTIFICATION_MESSAGE
IPv4:    $HOSTADDRESS"
fi

## Check whether IPv6 was specified.
if [ -n "$HOSTADDRESS6" ] ; then
  NOTIFICATION_MESSAGE="$NOTIFICATION_MESSAGE
IPv6:    $HOSTADDRESS6"
fi

## Check whether author and comment was specified.
if [ -n "$NOTIFICATIONCOMMENT" ] ; then
  NOTIFICATION_MESSAGE="$NOTIFICATION_MESSAGE

Comment by $NOTIFICATIONAUTHORNAME:
  $NOTIFICATIONCOMMENT"
fi

## Check whether Icinga Web 2 URL was specified.
if [ -n "$ICINGAWEB2URL" ] ; then
  NOTIFICATION_MESSAGE="$NOTIFICATION_MESSAGE

$ICINGAWEB2URL/monitoring/service/show?host=$(urlencode "$HOSTNAME")&service=$(urlencode "$SERVICENAME")"
fi

## Check whether verbose mode was enabled and log to syslog.
if [ "$VERBOSE" = "true" ] ; then
  logger "$PROG sends $SUBJECT => $USEREMAIL"
fi

## Send the mail using the $MAILBIN command.
## If an explicit sender was specified, try to set it.
if [ -n "$MAILFROM" ] ; then

  ## Modify this for your own needs!

  ## Debian/Ubuntu use mailutils which requires `-a` to append the header
  if [ -f /etc/debian_version ]; then
    /usr/bin/printf "%b" "$NOTIFICATION_MESSAGE" | tr -d '\015' \
    | $MAILBIN -a "From: $MAILFROM" -s "$ENCODED_SUBJECT" $USEREMAIL
  ## Other distributions (RHEL/SUSE/etc.) prefer mailx which sets a sender address with `-r`
  else
    /usr/bin/printf "%b" "$NOTIFICATION_MESSAGE" | tr -d '\015' \
    | $MAILBIN -r "$MAILFROM" -s "$ENCODED_SUBJECT" $USEREMAIL
  fi

else
  /usr/bin/printf "%b" "$NOTIFICATION_MESSAGE" | tr -d '\015' \
  | $MAILBIN -s "$ENCODED_SUBJECT" $USEREMAIL
fi
