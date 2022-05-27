#!/bin/sh

alias perltidy='perltidy -utf8 -l=127 -f -kbl=1 -bbb -bbc -bbs -b -ple -bt=2 -pt=2 -sbt=2 -bvt=0 -sbvt=1 -cti=1 -bar -lp -anl';
which perltidy;
cd ..;
for i in $(git status | grep '^[[:cntrl:]]*modified:' | egrep 'bin/|\.(pm|t)$' | perl -nE 'say +(split)[-1]'); do echo $i; perltidy -b $i; done
