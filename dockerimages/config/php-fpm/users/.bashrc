# ~/.bashrc — Magento docker container shell
case $- in *i*) ;; *) return;; esac

HISTCONTROL=ignoreboth
shopt -s histappend
HISTSIZE=2000
HISTFILESIZE=5000
shopt -s checkwinsize

# coloured prompt
PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

# colour ls
if [ -x /usr/bin/dircolors ]; then
    eval "$(dircolors -b)"
    alias ls='ls --color=auto'
fi

# bash-completion
if ! shopt -oq posix; then
    [ -f /usr/share/bash-completion/bash_completion ] && . /usr/share/bash-completion/bash_completion
fi

# ---------- Magento aliases (preserved from the original setup) ----------
alias ll='ls -lah'
alias lltr='ls -lahtr'
alias q='exit'

alias magento='php -d memory_limit=-1 -f bin/magento'
alias mage='php -d memory_limit=-1 -f bin/magento'
alias n98='n98-magerun2.phar'
alias magerun='n98-magerun2.phar'

alias dockenable='docker-php-ext-enable'

# Cache & static rebuild shortcuts
alias flushfront='bin/magento cache:flush; rm -rf var/view_preprocessed/* pub/static/frontend/* /pub/static/deployed_version.txt pub/static/_cache/*'
alias upcompile='bin/magento set:up; bin/magento setup:di:compile'

# Redis cache cleanup
alias redis-flush='redis-cli -h redis flushall'

# DB dump / import shortcuts (assumes ./db_dumps mounted at /var/www/db_dumps)
alias dbimport='n98-magerun2.phar db:import --compression="gzip" /var/www/db_dumps/latest_dbdump.sql.gz'
alias customdbimport='n98-magerun2.phar db:import --compression="gzip"'
alias dbexport='n98-magerun2.phar db:dump --compression="gzip" /var/www/db_dumps/latest_dbdump.sql.gz'
alias customdbexport='n98-magerun2.phar db:dump --compression="gzip"'
