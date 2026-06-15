#!/bin/sh
# Общие вспомогательные функции для CGI-скриптов invnet.

urldecode() {
  printf '%b' "$(echo "$1" | sed 's/+/ /g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')"
}
