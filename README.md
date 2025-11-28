# Postgres Ansible Configuration

This repository contains an Ansible setup to:

- Provision a **Postgres + pgAdmin** stack in Docker on a **DB server**
- Provision a **backup server** that receives **encrypted, rsynced backups**
- Provide **playbooks to restore** a database from those backups
- Provide a **local helper script** to pull & restore a backup on a developer machine

It’s designed for a two-host setup:

- **DB server** – runs Docker, Postgres, pgAdmin, backup script & cron
- **Backup server** – stores encrypted backup files (via rsync over SSH)

---

## 1. Repository Layout

Key files:

- `ansible.cfg`  
  - Uses `inventory/hosts.ini`  
  - Uses roles from `roles/`  
  - Expects a `vault_password_file` (local file containing your Ansible Vault password)

- `inventory/hosts.ini`  
  - Defines `db_servers` and `backup_servers` and SSH connection details

- `inventory/group_vars/`
  - `all.yml` – common variables (backup paths, tenants list, etc.)
  - `db_servers.yml` – Postgres & pgAdmin settings for DB hosts
  - `backup_servers.yml` – basic vars for backup hosts

- `playbooks/`
  - `setup-postgres.yml` – configure **only DB servers**
  - `setup-backup.yml` – configure **only backup servers**
  - `setup-postgres-and-backup.yml` – configure **both** in one go
  - `restore-postgres.yml` – restore a database on the DB server from backup

- `roles/`
  - `utilities` – basic tools (git, editors, etc.)
  - `ufw` – firewall setup (opens SSH + Ansible SSH port)
  - `zsh` – installs zsh + Antigen for the `ansible_user`
  - `docker` – installs & configures Docker (Debian/Ubuntu)
  - `postgres_stack` – deploys docker-compose + init SQL for Postgres + pgAdmin
  - `postgres_backup` – sets up backup script, GPG encryption, rsync, cron, and SSH between DB & backup servers

- `vault.yml`, `dev-vault.yml`  
  - **Encrypted** Ansible vault files for secrets (see below)

- `restore-local.sh`  
  - Helper script to fetch & decrypt a backup from the backup server onto a **developer machine**.

---

## 2. Prerequisites

On your control machine (where you run Ansible):

- Python 3
- Ansible installed (e.g. via `pip install ansible` or your package manager)
- SSH access to:
  - DB server (as `ansible_user` from inventory)
  - Backup server (as `backup_server_user` from inventory)

On the **remote hosts**:

- OS: Debian/Ubuntu (Docker role is written for Debian family)
- SSH enabled and reachable via host/port configured in `inventory/hosts.ini`

---

## 3. Configure Inventory

Edit `inventory/hosts.ini` to reflect your real machines. Example:

```ini
[db_servers]
db-01 ansible_host=your.db.server.ip ansible_port=22 ansible_user=ansible ansible_ssh_private_key_file=~/.ssh/postgres_server_key

[backup_servers]
backup-01 ansible_host=your.backup.server.ip ansible_port=22 ansible_user=backupuser ansible_ssh_private_key_file=~/.ssh/backup_server_key

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_connection=ssh

Make sure:

* `ansible_ssh_private_key_file` paths exist on your control machine.
* The users (`ansible`, `backupuser`) exist on the remote machines and can sudo where needed.
```

---

## 4. Configure Variables

### 4.1. Global variables (`inventory/group_vars/all.yml`)

Important vars (existing in the file):

* Backup & stack paths:

```yaml
postgres_restore_work_dir: /var/tmp/postgres-restore
postgres_stack_root: /opt/postgres-stack
postgres_backup_script_dir: /usr/local/bin

backup_rsync_private_key_path: "/root/.ssh/id_rsa_postgres_backup"

backup_server_host: "127.0.0.1"
backup_server_port: 2223
backup_server_user: "backupuser"

backup_store_dir: "/backups/postgres"
backup_store_user: "backupuser"

backup_server_remote_dir: "/backups/postgres"
postgres_backup_dir: /var/backups/postgres
```

* Backup user (inside Postgres) and tenants:

```yaml
db_backup_user_name: backup_user
db_backup_user_password: "{{ vault_db_backup_user_password }}"

tenants:
  - name: tenant1
    db: tenant1
    user: tenant1_user
    password: "{{ vault_tenant1_password }}"
  - name: tenant2
    db: tenant2
    user: tenant2_user
    password: "{{ vault_tenant2_password }}"
  - name: tenant3
    db: tenant3
    user: tenant3_user
    password: "{{ vault_tenant3_password }}"
  - name: tenant4
    db: tenant4
    user: tenant4_user
    password: "{{ vault_tenant4_password }}"
  - name: tenant5
    db: tenant5
    user: tenant5_user
    password: "{{ vault_tenant5_password }}"
```

You can change the tenants list to match your real DBs.

### 4.2. DB server variables (`inventory/group_vars/db_servers.yml`)

Key fields:

```yaml
server_name: postgres-server
ansible_user: ansible

postgres_image: "postgres:18"
postgres_container_name: "db"

pgadmin_image: "dpage/pgadmin4:latest"
pgadmin_container_name: "pgadmin"

pgadmin_default_email: "admin@example.com"
pgadmin_default_password: "{{ vault_pgadmin_password }}"

postgres_user: "postgres"
postgres_password: "{{ vault_postgres_password }}"
postgres_db: "main_db"

local_backup_keep_days: 15
```

* Default ports in Docker (see `roles/postgres_stack/templates/docker-compose.yml.j2`):

  * Postgres: host `5433` → container `5432`
  * pgAdmin: host `5050` → container `80`

Adjust the image tag, ports, or default DB as needed.

### 4.3. Backup server variables (`inventory/group_vars/backup_servers.yml`)

```yaml
server_name: backup-server
ansible_user: backupuser
```

You may adjust the user / server name to fit your environment.

---

## 5. Secrets with Ansible Vault

This setup expects secrets in an **encrypted vault file** (e.g. `dev-vault.yml`) referenced by the playbooks.

Required secret variables (used across group_vars):

```yaml
vault_postgres_password: "super-secret-postgres-password"
vault_pgadmin_password: "super-secret-pgadmin-password"

vault_db_backup_user_password: "password-for-backup_user"

vault_tenant1_password: "..."
vault_tenant2_password: "..."
vault_tenant3_password: "..."
vault_tenant4_password: "..."
vault_tenant5_password: "..."

# Used by backup/restore scripts for symmetric GPG encryption
backup_encryption_passphrase: "a-strong-passphrase-for-gpg"
```

> Note: `backup_encryption_passphrase` is referenced in:
>
> * `roles/postgres_backup/templates/pg_backup.sh.j2`
> * `playbooks/restore-postgres.yml`

### 5.1. Create a vault password file

`ansible.cfg` expects a file named `vault_password_file` in the repo root.

```bash
echo "your-vault-password-here" > vault_password_file
chmod 600 vault_password_file
```

### 5.2. Create or edit the vault file

To create:

```bash
ansible-vault create dev-vault.yml
```

To edit:

```bash
ansible-vault edit dev-vault.yml
```

Paste in all the variables listed above.

---

## 6. Provisioning

All commands are run from the repo root.

### 6.1. Provision DB server only

```bash
ansible-playbook playbooks/setup-postgres.yml
```

This will:

* Install base utilities
* Configure UFW and SSH access
* Install Docker
* Deploy Postgres + pgAdmin via docker-compose at `{{ postgres_stack_root }}`
* Create tenants & backup user via `init.sql`
* Install backup script and cron on the DB server

### 6.2. Provision backup server only

```bash
ansible-playbook playbooks/setup-backup.yml
```

This will:

* Install base utilities and zsh
* Prepare remote backup directory
* Set up SSH keys & authorized_keys to allow DB server → backup server rsync

### 6.3. Provision both DB and backup servers

```bash
ansible-playbook playbooks/setup-postgres-and-backup.yml
```

This runs:

* `utilities`, `ufw`, `zsh`, `docker`, `postgres_stack`, `postgres_backup` on `db_servers`
* `utilities`, `zsh`, `postgres_backup` on `backup_servers`

---

## 7. How Backups Work

The backup logic lives primarily in:

* Role: `roles/postgres_backup`
* Script template: `roles/postgres_backup/templates/pg_backup.sh.j2`

On the **DB server**, the role:

1. Installs `rsync` and `gnupg`.
2. Generates a dedicated SSH key for root at:

   * `{{ backup_rsync_private_key_path }}` (default: `/root/.ssh/id_rsa_postgres_backup`)
3. Stores the public key in a fact so the **backup server** can authorize it.
4. Ensures local backup directory exists:

   * `{{ postgres_backup_dir }}` (default: `/var/backups/postgres`)
5. Deploys backup script:

   * `{{ postgres_backup_script_dir }}/pg_backup.sh` (default: `/usr/local/bin/pg_backup.sh`)
6. Installs a nightly cron job:

   * Runs at `02:00` as root
   * Logs to `/var/log/pg_backup.log`

The **backup script**:

* Runs `pg_dumpall --globals-only` and `pg_dump` for:

  * `{{ postgres_db }}` and all `tenants[*].db`
* Encrypts every dump with `gpg` using `backup_encryption_passphrase`
* Syncs the encrypted files to the backup server using `rsync` over SSH:

  * From: `{{ postgres_backup_dir }}/<timestamp>/`
  * To: `{{ backup_server_user }}@{{ backup_server_host }}:{{ backup_server_remote_dir }}/<timestamp>/`

On the **backup server**, the role:

* Ensures remote dir `{{ backup_server_remote_dir }}` exists
* Adds DB servers’ public keys to `authorized_keys` for `{{ backup_server_user }}`

---

## 8. Restoring a Database on the Server

Use the playbook: `playbooks/restore-postgres.yml`

Run:

```bash
ansible-playbook playbooks/restore-postgres.yml
```

You will be prompted for:

1. `backup_date` – directory name on the backup (e.g. `2025-01-01_02-00-00`)
2. `database_name` – which database to restore (e.g. `tenant1`)
3. `confirm_restore` – must type `yes` to proceed or it will abort

The playbook then:

1. Checks if the backup exists locally at `{{ postgres_backup_dir }}/{{ backup_date }}`.
2. If not, pulls it from the backup server via rsync.
3. Decrypts `{{ database_name }}.dump.gpg` using `backup_encryption_passphrase`.
4. Ensures the Postgres Docker container is running.
5. Terminates existing connections to that DB.
6. Drops the database if it exists.
7. Recreates the database.
8. Restores the dump using `pg_restore`.
9. Deletes the plaintext `/tmp/{{ database_name }}.dump`.

---

## 9. Restoring a Backup Locally (Developer Machine)

Script: `restore-local.sh`

This runs on **your local machine**, not via Ansible.

Steps:

1. Ensure you can SSH to the backup server from your local machine:

   * User/host/port/key in the script:

     ```bash
     BACKUP_SERVER_USER="backupuser"
     BACKUP_SERVER_HOST="127.0.0.1"
     BACKUP_SERVER_PORT="22"
     SSH_KEY="~/.ssh/backup_server_key"
     REMOTE_DIR="/backups/postgres"
     LOCAL_BACKUP_DIR="../postgres_backups"
     ```

2. Run the script:

   ```bash
   chmod +x restore-local.sh
   ./restore-local.sh
   ```

3. It will:

   * Show the last 10 backup directories from the remote server.
   * Ask you for:

     * `BACKUP_DATE` (one of those directories)
     * `DATABASE` (e.g. `tenant1`)
     * GPG passphrase (same `backup_encryption_passphrase` used by the servers)
   * Download `DATABASE.dump.gpg` from the backup server via rsync.
   * Decrypt it to `LOCAL_BACKUP_DIR/DATABASE.dump`.

4. The script includes **commented-out** restore commands for a local Postgres instance:

   ```bash
   # dropdb --if-exists "$LOCAL_DB_NAME"
   # createdb "$LOCAL_DB_NAME"
   # pg_restore -d "$LOCAL_DB_NAME" --no-owner --no-acl "${LOCAL_BACKUP_DIR}/${DATABASE}.dump"
   ```

   You can uncomment and adapt them (and maybe remove the final `rm`) depending on how your local Postgres is set up (Docker vs. bare metal).

---

## 10. Verifying Everything

After running `setup-postgres.yml` (or the combined playbook):

* On the DB server:

  * Check Docker containers:

    ```bash
    docker ps
    ```

    You should see the `{{ postgres_container_name }}` and `{{ pgadmin_container_name }}` containers.

  * Check ports from your machine:

    * `psql -h <db_server> -p 5433 -U postgres` (or your user)
    * `http://<db_server>:5050` for pgAdmin

  * Check backup script & cron:

    * Make script executable: `ls -l /usr/local/bin/pg_backup.sh`
    * Manually run: `sudo /usr/local/bin/pg_backup.sh`
    * Check logs: `sudo tail -f /var/log/pg_backup.log`

* On the backup server:

  * Verify backups arrive in `{{ backup_server_remote_dir }}` (default `/backups/postgres`).

---

## 11. Troubleshooting Tips

* **Vault password issues**
  If Ansible complains it cannot decrypt `dev-vault.yml`, check:

  * `vault_password_file` exists and has the correct password
  * File permissions (`chmod 600 vault_password_file`)

* **SSH / rsync issues**

  * Confirm you can SSH from DB server to backup server as `backup_server_user` using the key at `backup_rsync_private_key_path`.
  * Check `authorized_keys` on the backup server.

* **GPG issues**

  * Ensure GPG is installed (`gnupg` package).
  * Make sure `backup_encryption_passphrase` in your vault matches what you use in `restore-local.sh`.

---
