# OpenMRS 3.0 Reference Application

This project holds the build configuration for the OpenMRS 3.0 reference application, found on
https://dev3.openmrs.org and https://o3.openmrs.org.

## Quick start

### Run the app (using pre-built images)

```bash
docker compose up
```

The OpenMRS 3.x UI is accessible at http://localhost/openmrs/spa

OpenMRS Legacy UI is accessible at http://localhost/openmrs

### Production deployment with SSL

For production deployments with HTTPS/SSL certificates, create a `.env` file in the project root:

```env
COMPOSE_FILE=docker-compose.yml:docker-compose.ssl.yml
SSL_MODE=prod
CERT_WEB_DOMAINS=your-domain.com
CERT_CONTACT_EMAIL=admin@your-domain.com
```

Then start the application as usual:

```bash
docker compose up
```

The `COMPOSE_FILE` variable tells Docker Compose to automatically include the SSL overlay, so you never need to pass `-f` flags. See the [SSL/HTTPS Configuration](#sslhttps-configuration) section for detailed setup instructions.

## Overview

This distribution consists of four images:

- **db** - This is just the standard MariaDB image supplied to use as a database
- **backend** - This image is the OpenMRS backend. It is built from the main Dockerfile included in the root of the project and
  based on the core OpenMRS Docker file. Additional contents for this image are drawn from the `distro` sub-directory which
  includes a full Initializer configuration for the reference application intended as a starting point.
- **frontend** - This image is a simple nginx container that embeds the 3.x frontend, including the modules described in the
  `frontend/spa-assemble-config.json` file.
- **gateway** - This image is an nginx reverse proxy that sits in front of the `backend` and `frontend` containers
  and provides a common interface to both. This helps mitigate CORS issues.

When running with SSL enabled (using `docker-compose.ssl.yml`), an additional service is included:

- **certbot** - This image is used for generating and renewing SSL certificates (Let's Encrypt or self-signed)

## SSL/HTTPS Configuration

The application can be run with SSL/HTTPS support for both development and production environments.

SSL configuration lives in `docker-compose.ssl.yml`, which is included alongside the base `docker-compose.yml`. The recommended way to enable it is via a `.env` file in the project root:

```env
COMPOSE_FILE=docker-compose.yml:docker-compose.ssl.yml
```

This tells Docker Compose to automatically include the SSL overlay, so all commands remain simply `docker compose up`, `docker compose down`, etc. without needing `-f` flags. All SSL-related environment variables (like `SSL_MODE` and `CERT_WEB_DOMAINS`) can also be set in this file.

### Development mode (self-signed certificates)

For local development with HTTPS:

```env
# .env
COMPOSE_FILE=docker-compose.yml:docker-compose.ssl.yml
```

```bash
docker compose up
```

This will:
- Automatically generate self-signed certificates for `localhost` and `127.0.0.1`
- Configure nginx to use HTTPS on port 443
- Redirect HTTP (port 80) to HTTPS

The application will be accessible at:
- https://localhost/openmrs/spa
- https://127.0.0.1/openmrs/spa

**Note**: Your browser will show a security warning for self-signed certificates. This is expected - click "Advanced" and proceed to the site.

### Production mode (Let's Encrypt)

For production deployments with valid SSL certificates from Let's Encrypt, create a `.env` file:

```env
# .env
COMPOSE_FILE=docker-compose.yml:docker-compose.ssl.yml
SSL_MODE=prod
CERT_WEB_DOMAINS=example.com
CERT_CONTACT_EMAIL=admin@example.com
```

```bash
docker compose up
```

**Configuration options**:

- `SSL_MODE=prod` - Use Let's Encrypt certificates (required)
- `CERT_WEB_DOMAINS` - Your domain name(s), comma-separated (e.g., `example.com,www.example.com`). The first domain is used as the primary domain for certificate paths and the nginx `server_name` directive.
- `CERT_CONTACT_EMAIL` - Email for Let's Encrypt notifications
- `CERT_WEB_DOMAIN_COMMON_NAME` - (Optional) Override the primary domain. By default, this is derived from the first domain in `CERT_WEB_DOMAINS`. You only need to set this if you want the certificate's common name to differ from the first domain.
- `SSL_STAGING=true` - (Optional) Use Let's Encrypt staging environment for testing

**The certbot container will**:
1. Create a temporary certificate to allow nginx to start
2. Wait for nginx to be ready
3. Request a real Let's Encrypt certificate via ACME HTTP-01 challenge
4. Reload nginx with the real certificate
5. Run a renewal daemon that checks for renewal every 12 hours

**Important**: Ensure your domain's DNS is correctly configured to point to your server before starting, as Let's Encrypt needs to verify domain ownership via HTTP.

### Testing with Let's Encrypt staging

To test the SSL setup without hitting Let's Encrypt rate limits, add `SSL_STAGING=true` to your `.env` file:

```env
# .env
COMPOSE_FILE=docker-compose.yml:docker-compose.ssl.yml
SSL_MODE=prod
SSL_STAGING=true
CERT_WEB_DOMAINS=example.com
CERT_CONTACT_EMAIL=admin@example.com
```

Staging certificates won't be trusted by browsers but allow you to verify the setup works correctly. Remove `SSL_STAGING` (or set it to `false`) once you've confirmed the setup works.

### Certificate profiles

Let's Encrypt offers different certificate profiles with varying validity periods:

| Profile | Validity | Use Case |
|---------|----------|----------|
| `classic` | 90 days (default) | Standard certificates |
| `tlsserver` | 45 days | Shorter validity for improved security |
| `shortlived` | 6 days | Required for IP address certificates |

To request a specific profile, add `CERT_PROFILE` to your `.env` file:

```env
# .env (additions)
CERT_PROFILE=tlsserver
```

**Note**: Let's Encrypt is transitioning all certificates to 45-day validity by 2028. Using the `tlsserver` profile allows you to opt-in to shorter certificates now.

### IP address certificates

Let's Encrypt now supports issuing certificates for publicly-addressable IP addresses. These certificates must use the `shortlived` profile (6-day validity).

```env
# .env
COMPOSE_FILE=docker-compose.yml:docker-compose.ssl.yml
SSL_MODE=prod
CERT_WEB_DOMAINS=203.0.113.50
CERT_CONTACT_EMAIL=admin@example.com
```

**Important notes for IP address certificates**:
- The IP address must be publicly addressable (not private IPs like 192.168.x.x or 10.x.x.x)
- The `shortlived` profile is automatically selected when an IP address is detected
- Certificates are valid for approximately 6 days and renew automatically
- IPv6 addresses are also supported

You can also mix domain names and IP addresses:

```env
CERT_WEB_DOMAINS=example.com,203.0.113.50
```

When any IP address is included, the shortlived profile is required and will be automatically enforced.

### Manual certificate renewal

While certificates renew automatically in production mode, you can manually force renewal if needed.

**If the certbot container is running** (prod mode):

```bash
# Force renewal
docker compose exec certbot certbot renew --force-renewal --webroot -w /var/www/certbot

# Reload nginx to pick up new certificates
docker compose exec gateway nginx -s reload
```

**If certbot container has stopped or for one-off renewal**:

```bash
# Run certbot in one-off mode (override entrypoint to run certbot directly)
docker compose run --rm --entrypoint certbot certbot \
  renew --force-renewal --webroot -w /var/www/certbot

# Reload nginx
docker compose exec gateway nginx -s reload
```

**Check certificate expiration**:

```bash
# If certbot container is running
docker compose exec certbot certbot certificates

# If certbot container is stopped
docker compose run --rm --entrypoint certbot certbot certificates
```

### Regenerating certificates

If you need to start fresh with certificates (e.g., after changing domains), delete the letsencrypt volume and restart:

```bash
docker compose down

# Remove only this project's letsencrypt volume
docker volume rm "$(docker compose config | awk '/^name:/{print $2}')_letsencrypt-data"

docker compose up
```

The certbot entrypoint skips certificate generation when it finds existing certificates for the configured domain. Removing the volume forces it to go through the full setup process again.

## Backup and Restore

This distribution includes automated backup and restore functionality using Restic. The backup system can back up both the MariaDB database and Docker volumes to a variety of storage backends (local filesystem, S3, SFTP, etc.).

### Setup

1. Copy the backup environment template to `.env`:

```bash
cp .env.backup .env
```

2. Edit `.env` and configure the required variables:

```env
# Restic repository location (choose one backend type)
# Local filesystem:
RESTIC_REPOSITORY=/path/to/backup/repository
# S3:
RESTIC_REPOSITORY=s3:s3.amazonaws.com/bucket-name
# SFTP:
RESTIC_REPOSITORY=sftp:user@host:/path/to/repo
# Rest server:
RESTIC_REPOSITORY=rest:http://host:8000

# Password to encrypt/decrypt the backup repository
# IMPORTANT: Store this securely! You cannot restore without it.
RESTIC_PASSWORD=your_secure_password_here

# Snapshot ID to restore (leave empty to restore the latest snapshot)
RESTIC_RESTORE_SNAPSHOT=

# Log level: debug, info, warning, error
RESTIC_LOG_LEVEL=info

# Backup schedule (cron format) - default: daily at 1 AM
BACKUP_CRON_SCHEDULE=0 1 * * *

# Snapshot retention policy
RESTIC_KEEP_DAILY=7
RESTIC_KEEP_WEEKLY=4
RESTIC_KEEP_MONTHLY=12
RESTIC_KEEP_YEARLY=3

# Local path for backup data
BACKUP_PATH=./openmrs_backup
```

### Using the backup-restore.sh script

The `backup-restore.sh` script provides convenient commands for backup and restore operations:

#### Initialize a new backup repository

```bash
./backup-restore.sh init
```

This creates a new Restic repository at the location specified in `RESTIC_REPOSITORY`. Only run this once when setting up backups for the first time.

#### Create a manual backup

```bash
./backup-restore.sh create
```

This immediately creates a backup of the database and volumes, regardless of the scheduled backup time.

#### List available backup snapshots

```bash
./backup-restore.sh list
```

This displays all available backup snapshots with their IDs, dates, and sizes.

#### Restore from a backup

```bash
./backup-restore.sh restore
```

This will:
1. Show a list of available snapshots
2. Prompt you to select a snapshot (or press Enter for the latest)
3. Stop the application
4. Restore the database and volumes from the selected snapshot
5. Prompt you to start the application again

**Warning**: Restore will replace all current data with the backup data. Ensure you have selected the correct snapshot before proceeding.

#### Start with automatic scheduled backups

```bash
./backup-restore.sh start
```

This starts the OpenMRS application with the backup service running in the background. Backups will be created automatically according to the `BACKUP_CRON_SCHEDULE` (default: daily at 1 AM).

### Manual Docker Compose usage

You can also use Docker Compose directly without the manage.sh script:

#### Initialize repository

```bash
docker compose -f docker-compose-backup.yml run --rm backup init
```

#### Create backup

```bash
docker compose -f docker-compose-backup.yml run --rm backup backup
```

#### List snapshots

```bash
docker compose -f docker-compose-backup.yml run --rm backup snapshots
```

#### Restore from backup

```bash
# Set the snapshot ID to restore (optional - defaults to latest)
export RESTIC_RESTORE_SNAPSHOT=<snapshot-id>

# Stop the application
docker compose down

# Start the restore process
docker compose -f docker-compose.yml -f docker-compose-restore.yml up -d restore

# Monitor restore progress
docker compose logs -f restore

# After restore completes, start the application
docker compose up -d
```

#### Start with automatic backups

```bash
docker compose -f docker-compose.yml -f docker-compose-backup.yml up -d
```

### What gets backed up

The backup system backs up:
- **MariaDB database** - The entire OpenMRS database
- **Docker volumes** - The `openmrs-data` and `db-data` volumes

These are labeled in `docker-compose.yml`:
- `backend` service has `restic-compose-backup.volumes: "true"` label
- `db` service has `restic-compose-backup.mariadb: "true"` label

### Snapshot retention policy

By default, the backup system keeps:
- 7 daily backups
- 4 weekly backups
- 12 monthly backups
- 3 yearly backups

Older snapshots are automatically pruned according to this policy. Adjust these values in `.env` if needed.

### Backup storage backends

Restic supports multiple storage backends. Configure `RESTIC_REPOSITORY` accordingly:

| Backend | Example Repository Format |
|---------|--------------------------|
| Local filesystem | `/path/to/backup` |
| S3 | `s3:s3.amazonaws.com/bucket-name` |
| SFTP | `sftp:user@host:/path/to/repo` |
| REST server | `rest:http://host:8000` |
| Azure Blob Storage | `azure:container:/path` |
| Google Cloud Storage | `gs:bucket:/path` |
| Backblaze B2 | `b2:bucket:/path` |

For S3-compatible services (like MinIO), you may need to set additional environment variables like `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.

### Security considerations

- **Store `RESTIC_PASSWORD` securely** - Without it, you cannot access or restore your backups
- **Encrypt your backup storage** - If using cloud storage, enable encryption at rest
- **Test your backups** - Regularly test restore procedures to ensure backups are valid
- **Monitor backup logs** - Check that scheduled backups are running successfully

### Running with Grafana

The service can run with Grafana for monitoring logs. You can run it with:
```bash
docker compose -f docker-compose.yml -f docker-compose.grafana.yml up
```
Grafana will be available at http://localhost/grafana. Use admin as username and see docker-compose.grafana.yml for the initial password.

If you would like to use grafana in your distro, you just need to copy over `docker-compose.grafana.yml`.

### Environment variables reference

| Variable | Default | Description |
|----------|---------|-------------|
| `SSL_MODE` | `dev` | `dev` for self-signed certificates, `prod` for Let's Encrypt |
| `SSL_STAGING` | `false` | Use Let's Encrypt staging environment (set to `true` for testing) |
| `CERT_WEB_DOMAINS` | `localhost,127.0.0.1` | Comma-separated list of domain names or IP addresses |
| `CERT_WEB_DOMAIN_COMMON_NAME` | first domain from `CERT_WEB_DOMAINS` | Override the primary domain used for certificate paths and nginx `server_name`. Most users should not set this. |
| `CERT_CONTACT_EMAIL` | (empty) | Email for Let's Encrypt notifications (required in prod mode) |
| `CERT_RSA_KEY_SIZE` | `4096` | RSA key size for certificates |
| `CERT_PROFILE` | (empty) | Certificate profile: `classic` (90 days), `tlsserver` (45 days), or `shortlived` (6 days). Auto-set to `shortlived` for IP addresses |

## Contributing to the configuration

This project uses the [Initializer](https://github.com/mekomsolutions/openmrs-module-initializer) module
to configure metadata for this project. The Initializer configuration can be found in the configuration
subfolder of the distro folder. Any files added to this will be automatically included as part of the
metadata for the RefApp.

Eventually, we would like to split this metadata into two packages:

- `openmrs-core`, which will contain all the metadata necessary to run OpenMRS
- `openmrs-demo`, which will include all of the sample data we use to run the RefApp

The `openmrs-core` package will eventually be a standard part of the distribution, with the `openmrs-demo`
provided as an optional add-on. Most data in this configuration _should_ be regarded as demo data. We
anticipate that implementation-specific metadata will replace data in the `openmrs-demo` package,
though they may use that metadata as a starting point for that customization.

To help us keep track of things, we ask that you suffix any files you add with either
`-core_demo` for files that should be part of the demo package and `-core_data` for
those that should be part of the core package. For example, a form named `test_form.json` would become
`test_core-core_demo.json`.

Frontend configuration can be found in `frontend/config-core_demo.json`.

Thanks!
