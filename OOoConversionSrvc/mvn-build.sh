#!/bin/sh
mvn -e -D maven.test.skip=true clean compile package pre-site install
