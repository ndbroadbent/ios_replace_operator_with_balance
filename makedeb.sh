#!/bin/bash

PackageName=hk.ndb.balanceasoperator

rm -f *.deb;

cd src;		
if [[ $1 == "--clean" ]]; then
	make clean;
fi;

make;
cd $OLDPWD;

./dpkg-deb-nodot deb ${PackageName};
