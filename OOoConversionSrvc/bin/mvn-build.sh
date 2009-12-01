#!/bin/sh
cd ..
mvn -e -D maven.test.skip=true clean compile package pre-site install
cd ./bin