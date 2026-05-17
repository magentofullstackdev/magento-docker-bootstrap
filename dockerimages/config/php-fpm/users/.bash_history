cd /var/www/html
ls -lah
composer install
magento set:up
magento set:di:compile
magento c:f
magento c:c
magento mode:show
magento deploy:mode:set developer
magento mod:dis Magento_TwoFactorAuth Magento_AdminAdobeImsTwoFactorAuth
magento indexer:reindex
magento indexer:status
magento setup:static-content:deploy -f
flushfront
upcompile
n98 dev:console
n98 sys:info
n98 cache:flush
n98 db:dump --compression="gzip" /var/www/db_dumps/dump-$(date +%Y%m%d).sql.gz
n98 db:import --compression="gzip" /var/www/db_dumps/latest_dbdump.sql.gz
vendor/bin/phpcs --standard=Magento2 app/code/
vendor/bin/phpcbf --standard=Magento2 app/code/
exit
