#!/usr/bin/env bash

usage() {
  cat <<EOF
. $0
EOF
}

if [ "$0" == "${BASH_SOURCE[0]}" ] ; then
  echo "You need to source this script into a Bash shell - you executed it"
  usage
fi

if [ "$0" != "bash" ] ; then
  echo "You need to source this script into a Bash shell - detected $0"
  usage
fi

rm -f \
  /tmp/ls-tree.log \
  /tmp/filter.log

rm -rf repo1 repo2

working_dir=/var/tmp/alex

echo "Starting in $working_dir ..."
mkdir -p "$working_dir"
cd "$working_dir"

make_repo() {
  repo="$1" ; shift

  read -r a b c <<< "$@"

  mkdir "$repo"
  cd "$repo"

  git init
  touch "$a" "$b" "$c"
  git add .
  git commit -m "Initial commit"

  echo "hello" >> "$a"
  git add .
  git commit -m "Edit $a" ; cd ..
}

echo "Making repo1 and repo2 ..."
make_repo 'repo1' 'A' 'B' 'C'
make_repo 'repo2' 'D' 'E' 'F'

subdir=subdir

echo "Merging repo2 into repo1:$subdir/ ..."

cd ./repo1

set -x

## Begin merge procedure.

git remote add -f repo2 ../repo2

git merge -s ours --no-commit \
  repo2/master --allow-unrelated-histories

git read-tree --prefix="$subdir" -u repo2/master:
git commit -m "Merge remote-tracking branch 'repo2/master'"

## End merge procedure.

talk_about_history() {
  echo "A list of all files:"
  find *
  git log --graph
  echo "History on file A ..."
  git log --oneline A
  echo "History on file subdir/D ..."
  git log --oneline subdir/D
  echo "^^ Before history fix this is showing only the merge commit"
  echo "^^ After history fix it shows the original history"
}
talk_about_history

## Begin history fix procedure.

git filter-branch \
  --tree-filter \
    '(
       echo "=== $GIT_COMMIT :"
       git ls-tree "$GIT_COMMIT"
     ) \
         >> /tmp/ls-tree.log'

# Sed magic to get the first SHA1 of repo2.
first=$(sed -En '
  N
  /D$/ {
    s/=== (.*) :.*/\1/p
    q
  }
  D
  ' /tmp/ls-tree.log)

# AWK magic to get the last SHA1 of repo2.
last=$(awk '
  /===/ {
    a=$2
    getline
    if ($4 == "D") {
      last=a
    }
  }
  END {
    print last
  }
  ' /tmp/ls-tree.log)

git filter-branch --tree-filter '
  first='"$first"'
  last='"$last"'
  subdir='"$subdir"'

  log_file="/tmp/filter.log"

  [ "$GIT_COMMIT" = "$first" ] && seen_first="true"

  if [ "$seen_first" = "true" ] && [ "$seen_last" != "true" ] ; then
    echo "=== $GIT_COMMIT: making changes"

    files=$(git ls-tree --name-only "$GIT_COMMIT")
    mkdir -p "$subdir"

    for i in $files ; do
      mv "$i" "$subdir" || \
        echo "ERR: mv $i $subdir failed"
    done
  else
    echo "=== $GIT_COMMIT: ignoring"
  fi \
       >> "$log_file"

  [ "$GIT_COMMIT" = "$last" ] && seen_last="true"

  status=0  # tell tree-filter never to fail
'

## End history fix procedure.

set +x

talk_about_history

echo "Leaving you in repo1 to play. Goodbye!"
