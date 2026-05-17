# Installation Guide

This guide walks through three common ways to get Magento or MageOS code into your fresh `magento-docker-bootstrap` checkout.

For a quick overview of the stack itself, see the [main README](../README.md). Once your code is in place, the [command reference](../README.md#command-reference) covers day-to-day operations.


You have three paths, all driven from the Makefile:

| Goal | Command | Prerequisite |
|---|---|---|
| Fresh Magento install | `make install` | `httpdocs/` contains `composer.json` (e.g. after `composer create-project`) |
| Existing project, no DB | `make composer-install` | code already in `httpdocs/`, no DB needed |
| Existing project + DB dump | `make import-db` | `db_dumps/latest_dbdump.sql.gz` present |

> **What does "code in `httpdocs/`" mean?**
> Magento's project root — the folder that contains `composer.json`, `bin/`, `app/`, `pub/`, `vendor/`, etc. — must sit **directly inside `httpdocs/`**, not nested in a subfolder. So you should end up with `httpdocs/composer.json`, `httpdocs/bin/magento`, `httpdocs/pub/index.php`. If your `composer.json` is at `httpdocs/magento2/composer.json`, the stack won't find it.

The three scenarios below show, step by step, how to get to that state.

### Scenario A — fresh Magento Open Source / Adobe Commerce install

You have nothing yet and want to start from scratch. Both Magento Open Source and Adobe Commerce (on-premise or Cloud) install the same way — only the `composer create-project` package name differs.

```bash
make configure       # answer the questions, pick the Magento version
make init            # build images and start containers (first run only)
make shell           # drop into the php-fpm container as www-data
```

Now you're inside the container, in `/var/www/html` (which is your `httpdocs/` from the host). Pick **one** of the two commands below, depending on which flavor you want:

```bash
# Magento Open Source
composer create-project --repository-url=https://repo.magento.com/ \
    magento/project-community-edition .

# OR — Adobe Commerce (on-premise or Cloud codebase)
composer create-project --repository-url=https://repo.magento.com/ \
    magento/project-enterprise-edition .
```

The `.` at the end installs straight into `/var/www/html`.

Composer will ask for your **public key** and **private key** — these come from your account at [https://commercemarketplace.adobe.com](https://commercemarketplace.adobe.com/customer/accessKeys/) (free signup, then go to *My Profile -> Marketplace -> Access Keys -> Create A New Access Key*). The public key is your username, the private key is your password.

When prompted, accept the offer to save the credentials — they land in `/var/www/.composer/auth.json` (persisted across container recreations via the `magento-composer-cache` volume).

> **Heads-up — auth.json copy step.** After `composer create-project` completes, subsequent `composer require` / `composer update` runs from `/var/www/html` may still prompt for the same credentials, because some Composer code paths only look at a project-local `auth.json`. The one-time fix, still inside the container:
>
> ```bash
> cd /var/www/html
> cp ../.composer/auth.json .
> ```
>
> This copies the saved credentials into the project root. Composer picks them up on every subsequent invocation, no more prompts. The file is git-ignored by Magento's default `.gitignore`, but double-check before committing.

Wait for `composer create-project` to finish (5–15 minutes), then leave the container:

```bash
exit
```

Back on the host, finish the installation:

```bash
make install         # runs setup:install with the values from .env
make sethostip
```

Open `https://<your-domain>` and you're done.

For more on the `composer create-project` step itself, see Adobe's official guide: [Install Adobe Commerce / Magento Open Source via Composer](https://experienceleague.adobe.com/en/docs/commerce-operations/installation-guide/composer).

### Scenario B — fresh MageOS install

Same as Scenario A but using the open MageOS distribution, which doesn't require Adobe Marketplace credentials.

```bash
make configure       # at the "platform" question, choose MageOS
make init
make shell
```

Inside the container:

```bash
composer create-project --repository-url=https://repo.mage-os.org/ \
    mage-os/project-community-edition .
exit
```

The `.` at the end installs straight into `/var/www/html`.

Back on the host:

```bash
make install
make sethostip
```

Done. See the official guide for more options (e.g. nightly builds, edge releases): [MageOS Installation](https://mage-os.org/get-started/installation/).

### Scenario C — clone an existing project from Git

You're joining a project that already has a Git repository.

```bash
make configure       # set the Magento and PHP versions to match the project
```

**Don't run `make init` yet** — first put the code in place. From the host, in the project directory:

```bash
# Important: the Magento root must be directly inside httpdocs/
git clone https://github.com/your-org/your-magento-project.git httpdocs
```

If `git clone` complains that `httpdocs/` is not empty (because of the `.gitkeep` placeholder), either delete the placeholder first (`rm httpdocs/.gitkeep`) or clone elsewhere and move the contents:

```bash
git clone https://github.com/your-org/your-magento-project.git /tmp/myrepo
mv /tmp/myrepo/* /tmp/myrepo/.[!.]* httpdocs/ 2>/dev/null
rm -rf /tmp/myrepo
```

After that, verify the layout — you should see `httpdocs/composer.json`, `httpdocs/bin/magento`, etc.

Now bring up the stack and pull dependencies:

```bash
make init
make composer-install
```

If you also have a database dump from your team:

```bash
cp /path/to/their-dump.sql.gz db_dumps/latest_dbdump.sql.gz
make import-db
```
or
```bash
cp /path/to/their-dump.sql.gz db_dumps/
make import-db FILE=db_dumps/staging-2026-04.sql.gz   # -> your filename
```

Otherwise run `make install` for a fresh DB, but make sure `app/etc/env.php` doesn't get committed to your repo (it's project-specific).

Finally:

```bash
make sethostip
```

You're up.

---

That covers the typical full bootstrap. The rest of the day is `make shell`, `make cache-flush`, `make compile` and friends.

