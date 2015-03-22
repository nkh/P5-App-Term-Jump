cdd ()
{
    if [[ ${@} =~ ^-{1,2}.* ]]; then
        jump ${@};
        return;
    fi;
    new_path="$(jump -search ${@})";
    if [ -d "${new_path}" ]; then
        mycd "${new_path}";
    else
        echo -e "\\033[31mNo match.\\033[0m";
        false;
    fi
}
