<?php
/**
 * Sample env.php - REFERENCE ONLY, not loaded by Magento.
 *
 * Copied into the container at /var/www/env.sample.php so you can grep it
 * when tuning a real app/etc/env.php. Magento generates the real one during
 * `bin/magento setup:install` and refreshes `crypt.key`, `cache.graphql.id_salt`
 * and the `system` overrides on its own - do NOT copy this file over the
 * generated one. Service hostnames (db / redis / opensearch) match the
 * defaults baked into the Docker stack.
 *
 * Deliberately omitted:
 *   - crypt.key -> generated per installation, never share
 *   - cache.graphql.id_salt -> generated per installation, never share
 *   - system.default / system.websites -> environment-specific, leak domains and credentials
 */
return [
    'backend' => [
        'frontName' => 'admin'
    ],
    'MAGE_MODE' => 'developer',
    'x-frame-options' => 'SAMEORIGIN',
    'remote_storage' => [
        'driver' => 'file'
    ],
    'directories' => [
        'document_root_is_pub' => true
    ],
    'install' => [
        'date' => 'Sat, 01 Jan 2026 00:00:00 +0000'
    ],
    'downloadable_domains' => [
        'yourdomain.local'
    ],

    'db' => [
        'connection' => [
            'default' => [
                'host' => 'db',
                'dbname' => 'magento',
                'username' => 'magento',
                'password' => 'magento',
                'model' => 'mysql4',
                'engine' => 'innodb',
                'active' => '1',
                'driver_options' => [
                    1014 => false
                ]
            ],
            'indexer' => [
                'host' => 'db',
                'dbname' => 'magento',
                'username' => 'magento',
                'password' => 'magento',
                'model' => 'mysql4',
                'engine' => 'innodb',
                'active' => '1',
                'persistent' => null
            ]
        ],
        'table_prefix' => ''
    ],
    'resource' => [
        'default_setup' => [
            'connection' => 'default'
        ]
    ],

    'session' => [
        'save' => 'redis',
        'redis' => [
            'host' => 'redis',
            'port' => '6379',
            'password' => '',
            'timeout' => '2.5',
            'persistent_identifier' => '',
            'database' => '7',
            'compression_threshold' => '2048',
            'compression_library' => 'gzip',
            'log_level' => '1',
            'max_concurrency' => '50',
            'break_after_frontend' => '5',
            'break_after_adminhtml' => '30',
            'first_lifetime' => '600',
            'bot_first_lifetime' => '60',
            'bot_lifetime' => '7200',
            'disable_locking' => '0',
            'min_lifetime' => '60',
            'max_lifetime' => '2592000'
        ]
    ],

    'cache' => [
        'frontend' => [
            'default' => [
                'id_prefix' => 'mage_',
                'backend' => 'Cm_Cache_Backend_Redis',
                'backend_options' => [
                    'server' => 'redis',
                    'port' => '6379',
                    'persistent' => '',
                    'database' => '0',
                    'password' => '',
                    'force_standalone' => '0',
                    'connect_retries' => '1',
                    'read_timeout' => '10',
                    'automatic_cleaning_factor' => '0',
                    'compress_data' => '1',
                    'compress_tags' => '1',
                    'compress_threshold' => '20480',
                    'compression_lib' => 'gzip',
                    'use_lua' => '0'
                ]
            ],
            'page_cache' => [
                'id_prefix' => 'mage_',
                'backend' => 'Cm_Cache_Backend_Redis',
                'backend_options' => [
                    'server' => 'redis',
                    'port' => '6379',
                    'persistent' => '',
                    'database' => '1',
                    'password' => '',
                    'force_standalone' => '0',
                    'connect_retries' => '1',
                    'lifetimelimit' => '57600',
                    'compress_data' => '0'
                ]
            ]
        ],
        'allow_parallel_generation' => false
    ],

    'lock' => [
        'provider' => 'db',
        'config' => [
            'prefix' => ''
        ]
    ],

    'queue' => [
        'consumers_wait_for_messages' => 1
    ],
    'cron_consumers_runner' => [
        'cron_run' => true,
        'max_messages' => 20000,
        'single_thread' => true,
        'consumers' => [

        ]
    ],
    'checkout' => [
        'async' => 0,
        'deferred_total_calculating' => 0
    ],

    'indexer' => [
        'batch_size' => [
            'cataloginventory_stock' => [
                'simple' => 400
            ],
            'catalog_category_product' => 800,
            'catalogsearch_fulltext' => [
                'partial_reindex' => 100,
                'mysql_get' => 500,
                'elastic_save' => 500
            ],
            'catalog_product_price' => [
                'simple' => 400,
                'default' => 1000,
                'configurable' => 800
            ],
            'catalogpermissions_category' => 1000,
            'inventory' => [
                'simple' => 300,
                'default' => 600,
                'configurable' => 800
            ]
        ]
    ],

    'cache_types' => [
        'config' => 1,
        'layout' => 1,
        'block_html' => 1,
        'collections' => 1,
        'reflection' => 1,
        'db_ddl' => 1,
        'compiled_config' => 1,
        'eav' => 1,
        'customer_notification' => 1,
        'config_integration' => 1,
        'config_integration_api' => 1,
        'full_page' => 1,
        'translate' => 1
    ]
];
