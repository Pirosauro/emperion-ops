#!/bin/bash
set -e

echo ">>> Build Start"

cd magento

# Optionally create auth.json
if [ -z "${COMPOSER_AUTH}" ]; then
    echo "${COMPOSER_AUTH}" > auth.json
fi

# Composer install
composer install \
    --prefer-dist \
    --no-dev \
    --no-interaction \
    --no-progress \
    --optimize-autoloader

# Magento specific build steps
php bin/magento setup:di:compile
php bin/magento setup:static-content:deploy -f \
    --jobs=$(nproc) \
    -t Magento/backend \
    -t Hobiri/emperion \
    en_US it_IT

rm -f auth.json

echo ">>> Build Completed"

cd ..

# Create artifact
tar --exclude="magento/.gitattributes" \
    --exclude="magento/.github" \
    --exclude="magento/.gitignore" \
    --exclude="magento/.git" \
    --exclude="magento/app/etc/env.php" \
    --exclude="magento/auth.json" \
    --exclude="magento/pub/media" \
    --exclude="magento/pub/sitemap" \
    --exclude="magento/var/.maintenance.ip" \
    --exclude="magento/var/backups" \
    --exclude="magento/var/cache" \
    --exclude="magento/var/export" \
    --exclude="magento/var/import" \
    --exclude="magento/var/import_history" \
    --exclude="magento/var/importexport" \
    --exclude="magento/var/log" \
    --exclude="magento/var/page_cache" \
    --exclude="magento/var/report" \
    --exclude="magento/var/session" \
    --exclude="magento/var/tmp" \
    -czf ./artifact.tar.gz magento/

if [ ! -f ./artifact.tar.gz ]; then
    echo "ERROR: artifact.tar.gz was not created!"
    exit 1
fi

mv scripts/remote-deploy.sh ./remote-deploy.sh
ls -al

echo ">>> Artifact created successfully: $(du -sh ./artifact.tar.gz)"