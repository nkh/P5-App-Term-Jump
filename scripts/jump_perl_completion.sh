
_jump_perl_completion()
{
local old_ifs="${IFS}"
local IFS=$'\n';
COMPREPLY=( $(jump_perl_completion.pl ${COMP_CWORD} ${COMP_WORDS[@]}) );
IFS="${old_ifs}"

return 1;
}

complete -o default -F _jump_perl_completion jump


