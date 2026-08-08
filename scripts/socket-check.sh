#!/usr/bin/env bash
# Socket helpers shared by bootstrap/network verification.
# `ss -H -lun` columns are: State Recv-Q Send-Q Local Address:Port Peer Address:Port.
# The local endpoint is field 4 (not field 5).

udp_port_listening(){
  local port="$1"
  ss -H -lun 2>/dev/null | awk -v suffix=":${port}" '
    length($4) >= length(suffix) && substr($4, length($4)-length(suffix)+1) == suffix { found=1 }
    END { exit(found ? 0 : 1) }
  '
}

tcp_port_listening(){
  local port="$1"
  ss -H -ltn 2>/dev/null | awk -v suffix=":${port}" '
    length($4) >= length(suffix) && substr($4, length($4)-length(suffix)+1) == suffix { found=1 }
    END { exit(found ? 0 : 1) }
  '
}
