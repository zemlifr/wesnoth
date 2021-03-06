#!/bin/bash

if [ "$TRAVIS_OS_NAME" = "osx" ]; then
    scons translations build=release --debug=time nls=true jobs=2 || exit 1

    cd ./projectfiles/Xcode

    xcodebuild CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -project "The Battle for Wesnoth.xcodeproj" -target "The Battle for Wesnoth" -configuration "$CFG"
    BUILD_RET=$?

    if [ "$UPLOAD_ID" != "" ] && [ "$TRAVIS_PULL_REQUEST" == "false" ]; then
# workaround for a bug in hdiutil where it freezes if multiple srcfolder-s are specified
        cp -R "build/$CFG/The Battle for Wesnoth.app" "../../packaging/macos/The Battle for Wesnoth.app"
        hdiutil create -volname "Wesnoth_${CFG}" -fs 'HFS+' -srcfolder ../../packaging/macos -ov -format UDBZ "Wesnoth_${CFG}.dmg"
        ./../../utils/travis/sftp "Wesnoth_${CFG}.dmg"
    fi

    ccache -s
    ccache -z

    exit $BUILD_RET
elif [ "$TRAVIS_OS_NAME" = "windows" ]; then
    powershell "MSBuild.exe projectfiles/VC14/wesnoth.sln -p:PlatformToolset=v141 -p:Configuration=$CFG"
    BUILD_RET=$?

    if [ "$UPLOAD_ID" != "" ] && [ "$TRAVIS_PULL_REQUEST" == "false" ]; then
        ./utils/travis/sftp wesnoth.exe wesnothd.exe
    fi

    if [ "$BUILD_RET" != "0" ]; then
        sqlite3 "projectfiles/VC14/$CFG/filehashes.sqlite" "update FILES set MD5 = OLD_MD5, OLD_MD5 = '-' where OLD_MD5 != '-'"
    else
        sqlite3 "projectfiles/VC14/$CFG/filehashes.sqlite" "update FILES set OLD_MD5 = '-' where OLD_MD5 != '-'"
    fi

    if [ "$CFG" == "Release" ] && [ "$BUILD_RET" == "0" ]; then
        ./run_wml_tests -g -v -c -t "$WML_TEST_TIME"
        BUILD_RET=$?
    fi

    exit $BUILD_RET
else
# additional permissions required due to flatpak's use of bubblewrap
# enabling tty/using unbuffer causes po4a-translate to hang during the translation job
    if [ "$NLS" != "only" ]; then
        docker run --cap-add=ALL --privileged \
               --env SFTP_PASSWORD --env IMAGE --env TRAVIS_COMMIT --env BRANCH --env UPLOAD_ID --env TRAVIS_PULL_REQUEST --env NLS --env CC --env CXX --env TOOL \
               --env CXXSTD --env CFG --env WML_TESTS --env WML_TEST_TIME --env PLAY_TEST --env MP_TEST --env BOOST_TEST --env LTO --env SAN --env VALIDATE \
               --env TRAVIS_TAG \
               --volume "$HOME"/build-cache:/home/wesnoth-travis/build \
               --volume "$HOME"/flatpak-cache:/home/wesnoth-travis/flatpak-cache \
               --volume "$HOME"/.ccache:/root/.ccache \
               --tty wesnoth-repo:"$IMAGE"-"$BRANCH" \
               unbuffer ./utils/travis/docker_run.sh
    else
        docker run --cap-add=ALL --privileged \
               --env SFTP_PASSWORD --env IMAGE --env TRAVIS_COMMIT --env BRANCH --env UPLOAD_ID --env TRAVIS_PULL_REQUEST --env NLS --env CC --env CXX --env TOOL \
               --env CXXSTD --env CFG --env WML_TESTS --env WML_TEST_TIME --env PLAY_TEST --env MP_TEST --env BOOST_TEST --env LTO --env SAN --env VALIDATE \
               --env TRAVIS_TAG \
               --volume "$HOME"/build-cache:/home/wesnoth-travis/build \
               --volume "$HOME"/flatpak-cache:/home/wesnoth-travis/flatpak-cache \
               --volume "$HOME"/.ccache:/root/.ccache \
               wesnoth-repo:"$IMAGE"-"$BRANCH" \
               ./utils/travis/docker_run.sh
    fi
fi
