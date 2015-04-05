#!/usr/bin/env bash

set -e

: ${1?"Usage: $0 test|install|deploy|release|website-only"}

COMMAND=$1

#######################################################################################################################
function checkNoUncommitedChanges {
  echo "Checking that there are no uncommited changes"
  git diff-index --quiet origin/HEAD --
  RET=$?
  if [ $RET != 0 ]; then
    echo "You have uncommited changes, please commit and push to origin everything before deploying the doc."
    exit $RET;
  fi;
}

function createScalaProject {
  SCALA_VERSION=$1
  SCALA_NEXT_VERSION=$2
  SCALA_RANGE_VERSION="$SCALA_VERSION.0"
  SCALA_PROJECT="genson-scala_$SCALA_VERSION"

  cp -R genson-scala $SCALA_PROJECT

  # Replacing the first occurrence of scala version definition in the properties and letting maven take care of the rest
  xmlstarlet edit -L -u "/project/properties/scala.version" -v $SCALA_VERSION $SCALA_PROJECT/pom.xml
  xmlstarlet edit -L -u "/project/properties/scala.range.version" -v "$SCALA_RANGE_VERSION" $SCALA_PROJECT/pom.xml

  # Need also to change the artifact id to include the scala version
  xmlstarlet edit -L -u "/project/artifactId" -v "$SCALA_PROJECT" $SCALA_PROJECT/pom.xml

  # Add this project to the parent pom
  sed -i "/<modules>/a <module>$SCALA_PROJECT</module>" pom.xml
}

function deployWebsite {
  RELEASE_VERSION=$1

  # checkout the release tag
  git checkout genson-parent-$RELEASE_VERSION
  mvn clean package -DskipTests

  # checkout and prepare gh-pages branch for the new generated doc
  git clone git@github.com:owlike/genson.git tmp_doc
  cd tmp_doc
  git checkout gh-pages
  rm -R *

  echo -e "latest_version: $RELEASE_VERSION \nproduction: true" > _config-release.yml
  cat _config-release.yml

  jekyll build --source ../website --destination . --config ../website/_config.yml,_config-release.yml

  rm _config-release.yml

  cp -R ../genson/target/apidocs Documentation/Javadoc
  cp -R ../genson-scala_2.10/target/apidocs Documentation/Scaladoc

  git add -u .
  git add .
  git commit -m "Documentation Release $RELEASE_VERSION"
  git push origin gh-pages
}
#######################################################################################################################

# checkNoUncommitedChanges

#git clone git@github.com:owlike/genson.git tmp_release

#cd tmp_release

sed -i "s/<module>genson-scala<\/module>//" pom.xml

createScalaProject 2.10
createScalaProject 2.11

case "$COMMAND" in
"test")
    mvn test
    ;;
"install")
    mvn install
    ;;
"deploy")
    mvn deploy
    ;;
"release")
    VERSION=$(sed -n 's|[ \t]*<version>\(.*\)</version>|\1|p' pom.xml|head -1|sed 's/-SNAPSHOT/d/')
    mvn release:clean

    # Deleting genson-scala as we want to push only the new copy per scala version
    rm -Rf genson-scala

    mvn release:prepare
    mvn release:perform

    deployWebsite $VERSION
    ;;
"website-only")
    if [ -z ${2+x} ]; then
      echo "Undefined release version, ex: make-release.sh website-only 1.2"
      exit 1
    fi

    deployWebsite $2
    ;;
*)
    echo "Unknown command: $COMMAND"
    exit 1;
esac


