#!/usr/bin/env sh
phone=root@10.42.43.15
package_file=`ls | grep hk.ndb.balanceasoperator`
echo "== Copying package file..."
scp $package_file $phone:/var/mobile
echo "== Installing..."
ssh $phone "dpkg -r hk.ndb.balanceasoperator; cd /var/mobile; dpkg -i $package_file; ## killall SpringBoard"
echo "===== Done."
