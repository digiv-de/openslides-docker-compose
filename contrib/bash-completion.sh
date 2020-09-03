_osinstancectl()
{
  local cur prev opts diropts
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  opts="ls add rm start stop update erase vicfg"
  opts+=" --help --long --metadata --online --offline --error"
  opts+=" --clone-from --force --color --project-dir --fast"
  opts+=" --image-info --version"
  opts+=" --server-image --server-tag --client-image --client-tag --all-tags"
  opts+=" --local-only --no-add-account"
  diropts="ls|rm|start|stop|update|erase|vicfg|--clone-from"

  if [[ ${prev} =~ ${diropts} ]]; then
    COMPREPLY=( $(cd /srv/openslides/docker-instances && compgen -d -- ${cur}) )
    return 0
  fi

  if [[ ${cur} == * ]] ; then
    COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
    return 0
  fi
}

complete -F _osinstancectl osinstancectl
complete -F _osinstancectl osstackctl
