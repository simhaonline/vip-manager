#!/bin/bash


set -eu -o pipefail
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# testing parameters
dev=`ip link show | grep -B1 ether | cut -d ":" -f2 | head -n1 | cut -d " " -f2`
vip=10.0.2.123

#cleanup
function cleanup {
    if test -f .ncatPid
    then
        kill `cat .ncatPid` 2> /dev/null || true
        rm .ncatPid
    fi
    if test -f .vipPid
    then
        kill `cat .vipPid` 2> /dev/null || true
        rm .vipPid
    fi
    if test -f .failed 
    then
        echo -e "${RED}### Some tests failed! ###${NC}"
        rm .failed
    fi
}
trap cleanup EXIT

# prerequisite test 0: vip should not yet be registered
! ip -c address show dev $dev | grep $vip

# podman rm etcd || true
# podman run -d --name etcd -p 2379:2379 -e "ETCD_ENABLE_V2=true" -e "ALLOW_NONE_AUTHENTICATION=yes" bitnami/etcd

# simulate server, e.g. postgres
ncat -vlk 0.0.0.0 12345  -e "/bin/echo $HOSTNAME" &
echo $! > .ncatPid

curl -s -XDELETE http://127.0.0.1:2379/v2/keys/service/pgcluster/leader ||true

touch .failed
./vip-manager --interface $dev --ip $vip --netmask 32 --trigger-key service/pgcluster/leader --trigger-value $HOSTNAME & #2>&1 &
echo $! > .vipPid
sleep 2

# test 1: vip should still not be registered
! ip -c address show dev $dev | grep $vip

# simulate patroni member promoting to leader
curl -s -XPUT http://127.0.0.1:2379/v2/keys/service/pgcluster/leader -d value=$HOSTNAME | jq .
sleep 2

# test 2: vip should now be registered
ip -c address show dev $dev | grep $vip

ncat -vzw 1 $vip 12345

# simulate leader change

curl -s -XPUT http://127.0.0.1:2379/v2/keys/service/pgcluster/leader -d value=0xGARBAGE | jq .
sleep 2

# test 3: vip should be deregistered again
! ip -c address show dev $dev | grep $vip

! ncat -vzw 1 $vip 12345

rm .failed
echo -e "${GREEN}### You've reached the end of the script, all \"tests\" have successfully been passed! ###${NC}"