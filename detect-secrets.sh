#!/bin/bash
set -o errexit -o nounset -o xtrace -o pipefail
# clean the folders this script create
source "${0%/*}/.env"

GITHUB_TOKEN="${GITHUB_TOKEN}"
GITHUB_USERNAME="${GITHUB_USERNAME:-javier-mora}"

# Source files
# source ./github-api.sh
source ./clean.sh

# List of repository names
REPO_LIST_FILE='./repos.txt'

# Name of the org of the repos, 
# repos will be search as _GITHUB_ORG/repo-name
_GITHUB_ORG='EZSource'
_PR_FILE_REPORT="${0%/*}/pr-reports.txt"
_COMPLETED_PR_FILE_REPORT="${0%/*}/completed-pr-reports.txt"
_PR_REVIEWER_USER='Andres-Marquez-Trujillo'


PR_BRANCH='WCA4Z-8027'

#Multiline string declaration, dont add spaces before and after each EOF
create_baseline_commit_msg=$(cat <<- EOF
${PR_BRANCH} Add .secrets.baseline file

Managed by detect-secrets tool
for more information visit https://w3.ibm.com/w3publisher/detect-secrets
Note: this commit was automated for any problem pelase reach ${GITHUB_USERNAME}
EOF
)
#keep this EOF trimmed, no spaces


gh-login(){
  echo "${GITHUB_TOKEN}" |
    gh auth login --hostname github.ibm.com --with-token 
}
branch-chekcout-exists(){
  local branch="${1}"
  git rev-parse --verify "remotes/origin/${branch}" > /dev/null 2>&1
  return $?
}

secrets-baseline-in-branch(){
  local branch="${1}"

  if ! branch-chekcout-exists "${branch}"; then
    echo "RUNTIME: secrets-baseline-in-branch: ${branch} does not exist in current repo..."
    return 1
  fi

  git checkout "${branch}"
  
  if [ ! -f .secrets.baseline ]; then
    echo "RUNTIME: secrets-baseline-in-branch: .secrets.baseline file  does not exist in \
        current repo, branch ${branch}..."
    return 1
  fi

  return 0
}

make-pr-detect-secrets-to-repo(){

  local repository=${1}
  # local branch=${2:-master} #branch defined before the clone to get default branch

  pushd repos

  #get default branch 
  branch=$(gh repo view "${repository}" --json defaultBranchRef -q ".defaultBranchRef.name")
  echo "RUNTIME: Repository ${repository} as a default branch: ${branch}"

  gh repo clone "${repository}"
  git fetch --all

  pushd "${repository##*/}"

    if ! secrets-baseline-in-branch ${branch} && ! secrets-baseline-in-branch ${PR_BRANCH};  then
    echo RUNTIME: .secrets.baseline file not found on "${repository}", creating one
    git checkout -b "${PR_BRANCH}"
    detect-secrets scan --update .secrets.baseline  --suppress-unscannable-file-warnings 
    git add .secrets.baseline
    #creating a temp file for storing commit
    commit_file=$(mktemp)
    echo "${create_baseline_commit_msg}" > "${commit_file}"
    git commit -F "${commit_file}"

    # do not push in testing
    # git push origin ${PR_BRANCH}

    gh pr create --dry-run --head "${PR_BRANCH}" --fill-verbose \
                 --base "${branch}" \
                --reviewer "${_PR_REVIEWER_USER}" \
                 | tee -a "${_PR_FILE_REPORT}"

    echo "${repository}-${PR_BRANCH}" >> "${_COMPLETED_PR_FILE_REPORT}"
    
  else
    echo RUNTIME: .secrets.baseline file already in repository: "${repository##*/}-${branch}", skipping...
  fi
  popd #${repository##/*}
  popd #repos
}

make_pr_all_repos(){
  while read repo_name;
  do
    echo "${repo_name}"
    make-pr-detect-secrets-to-repo "${_GITHUB_ORG}/${repo_name}"
    # exit 0 #only testing first input 
  done < "${REPO_LIST_FILE}"
}


#START of SCRIPT

#creating a temp file
touch "${_PR_FILE_REPORT}"
mkdir repos
commit_file=$(mktemp)
echo "${create_baseline_commit_msg}" > "${commit_file}"

gh-login 
make_pr_all_repos
# ./clean.sh

# END OF SCRIPT
