#!/bin/sh
cd ..
mvn -e -D maven.test.skip=true clean compile package pre-site install
cp ./target/OOoConversionSrvc-1.0-SNAPSHOT-executable.jar ./distributable/.
cd ./bin