#!/bin/sh
set -eu

usage="usage: create-user.sh USERNAME UID GID"

USERNAME="${1:?$usage}"
USER_UID="${2:?$usage}"
USER_GID="${3:?$usage}"

if getent group "$USERNAME" >/dev/null 2>&1; then
  [ "$(getent group "$USERNAME" | cut -d: -f3)" = "$USER_GID" ] ||
    groupmod --gid "$USER_GID" "$USERNAME"
else
  group_owner="$(getent group "$USER_GID" | cut -d: -f1)"
  if [ -n "$group_owner" ]; then
    groupmod --new-name "$USERNAME" "$group_owner"
  else
    groupadd --gid "$USER_GID" "$USERNAME"
  fi
fi

if ! id -u "$USERNAME" >/dev/null 2>&1; then
  user_owner="$(getent passwd "$USER_UID" | cut -d: -f1)"
  if [ -n "$user_owner" ]; then
    usermod --login "$USERNAME" \
      --home "/home/$USERNAME" --move-home "$user_owner"
  fi
fi

if id -u "$USERNAME" >/dev/null 2>&1; then
  [ "$(id -u "$USERNAME")" = "$USER_UID" ] || usermod --uid "$USER_UID" "$USERNAME"
  [ "$(id -g "$USERNAME")" = "$USER_GID" ] || usermod --gid "$USER_GID" "$USERNAME"
  chown -R "$USER_UID:$USER_GID" "/home/$USERNAME"
else
  useradd --uid "$USER_UID" --gid "$USER_GID" \
    --create-home --shell /bin/bash "$USERNAME"
fi
