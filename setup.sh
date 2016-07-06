#!/usr/bin/env bash

printf "== Installing local gems ==\n"
bundle install --path=gems --binstubs

printf "\n== Installing bower packages (used in browser) ==\n"
bower install

printf "\n== Installing npm packages (used by gulp and iso) ==\n"
npm install
