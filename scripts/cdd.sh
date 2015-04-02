cdd ()
{
    if [[ ${@} =~ ^-{1,2}.* ]]; then
        jump ${@};
        return;
    fi;
    new_path="$(jump -search ${@})";
    if [ -d "${new_path}" ]; then
	jump -add ${new_path} 1
        mycd "${new_path}";
    else
        echo -e "\\033[31mNo match.\\033[0m";
        false;
    fi
}

complete -o default -F _jump_perl_completion cdd 

