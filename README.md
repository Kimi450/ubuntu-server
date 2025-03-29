# Ubuntu Server
Highly opinionated server setup to cater to my needs

## Server Setup

***NOTE:*** If things dont work for some reason, try restarting and seeing if that fixes it.

### Cloud
Probably get a VM from [Oracle Always Free Tier](https://www.oracle.com/ie/cloud/free/) stuff.

### On-Prem
Use your own server

- #### Install Ubuntu
  https://ubuntu.com/download/desktop

- #### Enable ssh server (required for ansible to work)
  https://linuxize.com/post/how-to-enable-ssh-on-ubuntu-18-04/
  ```
  sudo apt update
  sudo apt install openssh-server
  sudo systemctl enable ssh
  sudo systemctl start ssh
  ```

- #### Disable sleep for the server
  This is to make sure it doesnt turn off mid install or when idle. If its a laptop, make sure power off when lid is closed is also turned off.

  You can do this via the UI or refer to this [stackoverflow post](https://askubuntu.com/questions/47311/how-do-i-disable-my-system-from-going-to-sleep).

## Client Setup

- #### Enable passwordless ssh access from remote machine to server (required for ansible to work)
  ```
  ssh-keygen -t ed25519 -C "primary-key"
  file ~/.ssh/id_ed25519.pub
  ssh-copy-id -p <ssh-port> <remote-user>@<server-ip>
  ```

  If youre using a machine that only allows for publickey auth, then you can upload your key that you just generated with the following command

  ```
  ssh-copy-id -i ~/.ssh/id_ed25519.pub -o 'IdentityFile ~/.ssh/<your-existing-private-key-for-access>.key' -p <ssh-port> <remote-user>@<server-ip>
  ```

- #### Install python and pip
  ```
  sudo apt update
  sudo apt install python3 pip
  ```

- #### Update the `group_vars/all` file to fill out the required information there
  At the very least, search for the items with tags `# FILL OUT`

  - ##### Get CloudFlare information [OPTIONAL]
    - This is if you use CloudFlare for your domain name and want the public IP updated automatically every set amount of time incase it is changed on the server.
    - **NOTE:** Make sure the services installed in this dont overlap with any existing implied DNS entries you may have (keep this in mind if you see any weird behaviour, im not an expert here and im too tired to think about this at the moment)
    - Register your domain name on CloudFlare
    - Go to the main CloudFlare page
    - Then `Websites`
    - Then select the relevant `Zone` (basically the website you used in the `group_vals/all` file)
    - Go to the `Overview` page
      - On the right side you can see the `Zone ID`
      - Put this in the `group_vars/all` file
      - Here you can also see the link to the API token page
    - Go to the `DNS` page 
      - Put in the following records (**REQUIRED**)

        | Type | Name                   | Content            | Proxy Status | TTL    |
        |------|------------------------|--------------------|--------------|--------|
        | `A`  | `<YOUR_DOMAIN_NAME>`   | `<YOUR_PUBLIC_IP>` | `DNS only`   | `Auto` |
        | `A`  | `*.<YOUR_DOMAIN_NAME>` | `<YOUR_PUBLIC_IP>` | `DNS only`   | `Auto` |
  
      - Now you can also use `<YOUR_DOMAIN_NAME>` in the `group_vars/all` file instead of the server's IP address
    - Create a Custom API token from the [api-tokens](https://dash.cloudflare.com/profile/api-tokens) page with the following permissions and include the specific `Zone` (or website) from `Zone Resources` section
      - To edit DNS entries
        - `Zone:DNS:Edit`
      - To read `Zone` information
        - `Zone:Zone:Read`
      - Put this token/key in the `group_vars/all` file
    - If not needed, remove the line below line from `setup.yaml`
    `- import_playbook: install-and-configure-cloudflare-dns-updater-service.yaml`

- #### Update the `hosts.yaml` file to fill out the template

- #### Expose required ports on your router
  - Expose (port forward on your router) ports for the services you wish to have available externally based on the list [here](#exposed-services).

- #### Run the ansible runner script
  - `./run.sh`
  - You can add `-vvvv` to get more verbose output

- #### After the installation

  **REMEMBER**: You can add additional directories for services via the `group_vars` file as well under the `persistence` section.

  ```yaml
  - name: spare-disk
    host_path: "/mnt/b/downloads"
  ```

  The above section will mount `/mnt/b/downloads` onto the pod as `/data/spare-disk/downloads`

  - ##### [OPTIONAL] Setup Fishet
    - Consider setting up [fishnet](https://github.com/lichess-org/fishnet) to help [Lichess](https://lichess.org/) run game analysis!
      - Kubernetes installations are also supported and documented [here](https://github.com/lichess-org/fishnet/blob/master/doc/install.md#kubernetes)

  - ##### Setup Grafana
    - Add the recommended dashboards (Make sure you select the correct job in the variables section, you can default to `kubernetes-service-scraper`)
      - [Node Exporter Full](https://grafana.com/grafana/dashboards/1860)
      - [Loki Kubernetes Logs](https://grafana.com/grafana/dashboards/15141)
      - [Container Log Dashboard](https://grafana.com/grafana/dashboards/16966)
      - [Sonarr v3](https://grafana.com/grafana/dashboards/12530-sonarr-v3/)
      - [Radarr v3](https://grafana.com/grafana/dashboards/12896-radarr-v3/)
      - [Pods (Aggregated view)](https://grafana.com/grafana/dashboards/8860)
      - [Monitor Pod CPU and Memory usage](https://grafana.com/grafana/dashboards/15055)
      - [Node Exporter for Prometheus Dashboard EN v20201010](https://grafana.com/grafana/dashboards/11074)
    - Would recommend adding a panel with the following query as it is useful to monitor pods as well
      - For average
        ```
        avg(irate(container_cpu_usage_seconds_total[2m])) by (pod,container)
        ```
    - You can find information on how to use [Loki](https://grafana.com/oss/loki/) in Grafana [here](https://grafana.com/docs/loki/latest/operations/grafana/)

  - ##### Setup Jellyfin
    - Initial setup is just following on-screen instructions.
      - If asked to select server, delete it and refresh the page.
    - Point Jellyfin to use the directories mentioned in the playbooks for shows, movies, music and books.
      - By default, on the Jellyfin pod, the directories it will be:
        ```
        /data/root-disk/shows
        /data/root-disk/movies
        /data/root-disk/music
        /data/root-disk/books
        ```
    - Add any other config required.
      - Recommend setting up the Open Subtitles plugin which requires creating an account on [their website](https://www.opensubtitles.org/en/?).
      - For Hardware acceleration go to ``Admin > Dashboard > Playback``
          - Enable ``Hardware acceleration``
          - Select ``Video Acceleration API (VAAPI)`` which is setup already to use the **integrated Intel GPU**. Not tested with anything else (like a dedicated AMD/Nvidea GPU)
            - You should see CPU usage drop and GPU usage go up, disable it if you dont or troubleshoot.
            - You can use the ``intel-gpu-tools`` package to monitor (notice GPU usage when hardware encoding is enabled, and no GPU usage when it is disabled) at least the intel GPU by running the command below on the host:
              ``sudo intel_gpu_top``
          - Select the formats for which hardware acceleration should be enabled
            - Recommend not selecting ```HEVC 10bit``` because for some reason that breaks it
          - Defaults to CPU/software encoding if hardware acceleration does not work for a file, I think.
          - More infomarmation on their [Jellyfin's page for Hardware Acceleration](https://jellyfin.org/docs/general/administration/hardware-acceleration.html)
    - Add any plugins you may want
      - [Trackt](https://trakt.tv/dashboard)
        - To track the shows you watch
        - Create a Trackt account
        - Go to ``Admin > Dashboard > Plugins > Catalogue``
          - Enable Trackt
          - Restart Jellyfin (Shutdown server from the `Dashboard` and k8s will restart, or delete the pod)
        - Go to ``Admin > Dashboard > Plugins > Trackt``
          - Select the user
          - `Authorize Device`
          - Follow onscreen instructions
        - Go to ``Admin > Dashboard > Scheduled Tasks > Trackt``
          - Create a daily scheduled task for importing data from and exporting data to tract.tv

  - ##### Setup qBittorrent
    - Default login credentials are randomly generated, you need to look at ansible logs to get the default login credentials.
      - Look for the substring `You can log into qBittorrent` in the logs to find the creds in the form `admin/<RANDOM_PASSWORD>`
        - If `<RANDOM_PASSWORD>` is not seen, that means that a password was found to be set already and that a randomly generated password was not used. Please try to remeber the password or reinstall to override configuration to use default passwords again.
    - Change the default login details
      - Go to ``Tools > Options > Web UI > Authentication``
    - Set default download location to one the mentioned directories (or make sure to put it in the right directory when downloading for ease)
      - Go to ``Tools > Options > Downloads > Default Save Path``
      - Recommend using ``/data/root-disk/downloads``
    - Set seeding limits
      - Recommend seeding limits for when seeding ratio hits "1" to give back to the community. It is under ``Tools > Options > BitTorrent > Seeding Limits``
    - Set torrent download/upload limits
      - Recommended to keep 12 active torrents, 6 downloads and 6 uploads. It is under ``Tools > Options > BitTorrent > Torrent Queueing``

  - ##### Setup Calibre
    - Do base setup
      - Set folder to be ``/data/root-disk/books`` and select ``Yes`` for it to rebuild the library if asked.
    - Go to ``Preferences > Sharing over the net``
      - Check the box for ``Require username and password to access the Content server``
      - Check the box for ``Run the server automatically when calibre starts``
      - Click on ``Start server``
      - Go to the ``User accounts tab`` and create a user
        - Make a note of the credentials for use in ``Readarr`` setup
      - Restart the app/pod
        - You can do so by also pressing `CTRL + R` on the main screen

  - ##### Setup Calibre Web
    - Default login is ``admin/admin123``
    - Set folder to be ``/data/root-disk/books``
    - To enable web reading, click on ``Admin`` (case sensitive) on the top right
      - Click on the user, default is ``admin``
      - Enable ``Allow ebook viewer``
      - Change password to something more secure
      - Save settings

  - ##### Setup Radarr/Sonarr/Readarr/Lidarr
    - Service function

      | Service | Purpose  |
      |---------|----------|
      | Readarr | Books    |
      | Sonarr  | TV Shows |
      | Radarr  | Movies   |
      | Lidarr  | Music    |

    - Go to ``Settings`` and click on ``Show Advanced``
    - Enable authentication
      - Set `Authentication` to `Forms (Login Page)`
      - Set `Authentication Required` to `Enabled`
      - Set username and password for access
    - Add torrent client
      - Go to ``Settings > Download Clients > Add > qBittorent``
      - Add the host: ``qbittorrent``
      - Add the port: ``10095``
      - Add the username: ``<qBittorrent_username>``
      - Add the password: ``<qBittorrent_password>``
      - Enable the ``Remove Completed`` option.
        - This will copy the download from the downloads directory to the destination directory for the service. Once the seeding limits are reached, it will delete the torrent and its files from the downloads directory.
        - More information on [sonarrs's wiki page](https://wiki.servarr.com/sonarr/settings#Torrent_Process) and [radarr's wiki page](https://wiki.servarr.com/radarr/settings#Torrent_Process) under `Remove Completed Downloads`. They should all have the same idea though.
    - Set the root directories to be the following
      - Go to ``Settings > Media Management``

        | Service | Root Directory    |
        |---------|-------------------|
        | Readarr | ``/data/root-disk/books/``  |
        | Sonarr  | ``/data/root-disk/shows/``  |
        | Radarr  | ``/data/root-disk/movies/`` |
        | Lidarr  | ``/data/root-disk/music/``  |
      - Enable renaming
    - Adjust quality definitions
      - Go to ``Settings > Quality``
      - Set the ``Size Limit`` or ``Megabytes Per Minute`` (or equivalent) to appropriate numbers
        - This will ensure your downloads are not "too big"
      - For movies and shows, ``2-3GiB/h`` would usually be sufficient as the ``Preferred`` value, and you can leave the ``Max`` value a bit higher to ensure a better chance of download grabs
        - Min: 0
        - Preferred: 30
        - Max: 70 (you can also use 2000 but you might get bigger files more often)
    - Go to ``Settings > Media Management``
        - If present, make sure ``Use Hardlinks instead of Copy`` is enabled
    - Radarr/Sonarr specific config
      - Go to ``Settings > Profiles``
        - If present, for all relevant profiles (or just all of them), set the `Language` for the profile to be `Original` (or whatever language you prefer it to be instead) to download the media in that specific language.
      - **[EXPERIMENTAL]** Enforce downloads of original language media only
        - Go to ``Settings > Custom Formats``
          - Add a new Custom Format with ``Language`` Condition
            - Set ``Language: Original``
            - Set ``Required: True``
        - Go to ``Settings > Profiles``
          - Select all [relevant] profiles and set the following
            - ``Minimum Custom Format Score`` to ``0`` (sum of the custom formats scores)
            - Your new Custom Format's score to be ``0`` (if the value is lower than the minimum score then downloads will be blocked)
    - Readarr specific config
      - Go to ``Settings > Media Management``
        - Add root folder (you cannot edit an existing one)
          - Set the path to be ``/data/root-disk/books/``
          - Enable ``Use Calibre`` options the the following defaults
            - Calibre host: ``calibre-webserver``
            - Calibre port: ``8081``
            - Calibre Username: ``<calibre_username>``
            - Calibre Password: ``<calibre_password>``
        - Enabled ``Rename Books`` and use the defaults

  - ##### Setup Prowlarr
    - Enable authentication
      - Set `Authentication` to `Forms (Login Page)`
      - Set `Authentication Required` to `Enabled`
      - Set username and password for access
    - Add `FlareSolverr` service as a proxy, refer to [this](https://trash-guides.info/Prowlarr/prowlarr-setup-flaresolverr/) guide for help
      - Go to ``Settings > Indexers``
      - Add a new proxy for `FlareSolverr`
        - Add a tag to it, for example `flaresolverr`
          - **NOTE:** This tag needs to be used for any indexer that needs to bypass CloudFlare and DDoS-Gaurd protection
        - The default host will be `http://flaresolverr:8191/`
    - Follow the [official Quick Start Guide](https://wiki.servarr.com/prowlarr/quick-start-guide)
      - Add all the indexers you wish to use, some good ones listed below. Find more indexers on [Prowlarr's Supported Indexers page](https://wiki.servarr.com/prowlarr/supported-indexers).
        - Standard
          ```
          1337x
            Add "flaresolverr" tag
          LimeTorrents
          The Pirate Bay
          EZTV
          ```
        - Anime
          ```
          Anidex
            Add with higher priority, example "1", since it has good english subtitled content
            Add "flaresolverr" tag
          Bangumi Moe
          Nyaa.si
          Tokyo Toshokan
          ```
        - It is recommended to use private indexers for books and music as they are harder to find otherwise
    - Add Sonarr, Radarr, Lidarr and Readarr to the ``Settings > Apps > Application`` section using the correct API token and kubernetes service names
      - By default prowlarr server will be:
        ```
        http://prowlarr:9696
        ```
      - By default the services will be:
        ```
        http://sonarr:8989
        http://radarr:7878
        http://lidarr:8686
        http://readarr:8787
        ```
      - Select extra `Sync Catagories` for each application if required
        - I would recommend keeping the default categories for the most part
        - For the apps `Sonarr` and `Radarr`, it might be worthwhile using both `TV` and `Movies` categories
        - **NOTE:** If you dont know what to do, add all of them for every app (comes at the cost of slower searches). But this may also result in some weird behaviour which would need troubleshooting.

  - ##### Setup Bazarr
    - Enable authentication
      - Go to ``Settings > General``
      - Under ``Security`` select ``Form`` as the form of ``Authentication``
      - Set username and password for access
    - Follow the official [Setup Guide](https://wiki.bazarr.media/Getting-Started/Setup-Guide/)
      - Go to ``Settings > Radarr`` and ``Settings > Sonarr``
        - Click on `Enable`
        - Fill out the details and save
          - Use the API tokens from the respective services, found under ``Settings > General > Security > API Key``
          - Use the kubernetes service name and port

            | Service Name | Port |
            |--------------|------|
            | radarr       | 7878 |
            | sonarr       | 8989 |

          - Set a suitable minimum score, probabl `70` is fine
        - Fill out the path mappings if the directories in which data is stored is different for both services (by default both services will use the same directory to access data, so you dont need to change anything for a default install)
      - Go to ``Settings > Languages``
        - Add a language profile and set defaults for movies and series'
        - You may need to set language filters first before being able to create a profile with the languages in them
        - Add both, for hearing impaired and regular ones, to increase your chances
      - Go to ``Settings > Provider`` and add providers for subtitles
        - Decent options are:
          - Opensubtitles.com
          - TVSubtitles
          - YIFY Subtitles
          - Supersubtitles
      - Go to ``Settings > Subtitles`` and make changes if needed
      - Manually add the language profile to all the scanned media after first installation
    - NOTE:
      - If it doesnt work, manually restart the pod few times. It just works, not sure why. If that doesnt work, try reinstalling.

  - ##### Setup Jellyseerr
    - One stop shop for Sonarr/Radarr requests
    - Run the first time setup for Jellyfin
      - `Choose Server Type`
        - Select `Jellyfin`
      - `Account sign in`
        - Jellyfin URL: `http://jellfin:8096`
        - Email Address: `<YOUR_EMAIL>`
        - Username: `<JELLYFIN_USERNAME>`
        - Password: `<JELLYFIN_PASSWORD>`
        - You can then login using your Jellyfin credentials
          - If you do not wish to do so, set a local user password by editing your account under `Users` to login with your email ID instead
      - `Configure Media Server`
        - Click on `Sync Libraries`
          - Enable all Libraries that get listed
        - Also run a manual scan
      - `Configure Services`
        - Setup all the services
          - Use the correct API keys, hostnames and ports for the services
              | Service Name | Port |
              |--------------|------|
              | jellyfin     | 8096 |
              | sonarr       | 8989 |
              | radarr       | 7878 |
          - Quality profile can be `HD-1080p` or `HD - 720/1080p`
          - Select the applicable root folders
          - Check relevant options that suit your needs
            - General
              - Enable `Tag Requests`
              - Enable `Scan`
              - Enable `Default Server`
            - Sonarr specific
              - Enable `Season Folders`
    - Go to `Users` and either add new users or import from Jellyfin directly
      - This is not required by default
      - Give them `Manage Requests` and other permissions for ease where applicable
    - Go to `Settings -> Users` and give them all `Auto-Approve` and `Auto-Request` Permissions by default for ease.

  - ##### Setup Immich
    - Just follow onscreen instructions to create an account
    - Setup the config as you please from there!

  - ##### Setup Ombi
    - One stop shop for Sonarr/Radarr/Lidarr requests
    - Get the API keys for Jellyfin, Sonarr and Radarr
      - Jellyfin
        - Go to ``Admin > Dashboard > API Keys``
        - Generate a new API key with an appropriate name
      - Sonarr/Radarr/Lidarr
        - Use the API tokens from the respective services, found under ``Settings > General > Security > API Key`` 
    - Set credentials for login
    - Go to ``Settings``
      - Use the correct API keys, hostnames and ports for the services
          | Service Name | Port |
          |--------------|------|
          | jellyfin     | 8096 |
          | sonarr       | 8989 |
          | radarr       | 7878 |
          | lidarr       | 8686 |
      - Click on the ``Load Profiles`` and ``Load Root Folders`` buttons and use the appropriate defaults as used in the services seen [here](#setup-radarrsonarrreadarrlidarr).
      - Setup ``Movies`` using ``Radarr``
      - Setup ``TV`` using ``Sonarr``
        - Enable the ``Enable season folders`` option
        - Enable the ``V3`` option
      - Setup ``Music`` using ``Lidarr``
      - Setup ``Media Server`` using ``Jellyfin``
      - **Dont forget to click on ``Enable`` for each of those setups as well**
    - Go to ``Users``
      - Setup additional users
      - Give the following roles to *trusted* users for convinience
        ```
        Request Tv
        Request Movie
        Request Music
        Auto Approve Tv
        Auto Approve Movie
        Auto Approve Music
        ```

  - ##### Use Squid
    - Use the username and password from the `group_vars/all` file to use this as a proxy server
    - The address would be `<PUBLIC_IP>:<GROUP_VARS_PORT>` or `<DOMAIN_NAME>:<GROUP_VARS_PORT>` or `<LAN_IP>:<GROUP_VARS_PORT>`

  - ##### Use Sambashare
    - For external access:
    - To authenticate
      - Thee username will be the `<ANSIBLE_USER>` you used in the `hosts.yaml` file
      - The password will be in the `group_vars/all` file (`smb.password` section).
    - In Windows, connect to it using `\\<LAN_IP>\<SHARE_NAME_FROM_GROUP_VARS_ALL>`
    - More information [here](https://ubuntu.com/tutorials/install-and-configure-samba#4-setting-up-user-accounts-and-connecting-to-share)

  - ##### Exposed Services
    - You need to create DNS entries to access the Ingress services. The following entries are recommended:
      - `*.<DOMAIN_NAME>`
      - `<DOMAIN_NAME>`
    - You can port forward the following ports on your router to gain external access. On your router:
      - Set a static IP for your server (if applicable) so the router doesnt assign a different IP to the machine breaking your port-forwarding setup
      - Following are some sample rules based on the `all` file defaults for port forwarding, feel free to tweak to your needs.

      | Service     | Default access | Where                                                             | Server port                      |                Public facing port |
      |-------------|----------------|-------------------------------------------------------------------|----------------------------------|-----------------------------------|
      | ssh         | ssh            | `<LAN_IP>` or `<DOMAIN_NAME>`                                     |                               22 | `<IN_LINE_WITH_HOSTS_FILE_OR_22>` |
      | samba       | proxy          | `\\<LAN_IP>\<SHARE_NAME>` or `\\<DOMAIN_NAME>\<SHARE_NAME>`       |   TCP: `139,445`, UDP: `137,138` |       `<BEST_NOT_TO_EXPOSE_THIS>` |
      | squid       | proxy          | `<LAN_IP>:<GROUP_VARS_PORT>` or `<DOMAIN_NAME>:<GROUP_VARS_PORT>` |        `<IN_LINE_WITH_ALL_FILE>` |                    `<YOU_DECIDE>` |
      | grafana     | Ingress        | `grafana.<DOMAIN_NAME>`                                           |     30080 (HTTP) / 30443 (HTTPS) |           80 (HTTP) / 443 (HTTPS) |
      | jellyfin    | Ingress        | `jellyfin.<DOMAIN_NAME>`                                          |     30080 (HTTP) / 30443 (HTTPS) |           80 (HTTP) / 443 (HTTPS) |
      | jellyseerr  | Ingress        | `jellyseerr.<DOMAIN_NAME>`                                        |     30080 (HTTP) / 30443 (HTTPS) |           80 (HTTP) / 443 (HTTPS) |
      | ombi        | Ingress        | `ombi.<DOMAIN_NAME>`                                              |     30080 (HTTP) / 30443 (HTTPS) |           80 (HTTP) / 443 (HTTPS) |
      | prowlarr    | Ingress        | `prowlarr.<DOMAIN_NAME>`                                          |     30080 (HTTP) / 30443 (HTTPS) |           80 (HTTP) / 443 (HTTPS) |
      | bazarr      | Ingress        | `bazarr.<DOMAIN_NAME>`                                            |     30080 (HTTP) / 30443 (HTTPS) |           80 (HTTP) / 443 (HTTPS) |
      | radarr      | Ingress        | `radarr.<DOMAIN_NAME>`                                            |     30080 (HTTP) / 30443 (HTTPS) |           80 (HTTP) / 443 (HTTPS) |
      | sonarr      | Ingress        | `sonarr.<DOMAIN_NAME>`                                            |     30080 (HTTP) / 30443 (HTTPS) |           80 (HTTP) / 443 (HTTPS) |
      | readarr     | Ingress        | `readarr.<DOMAIN_NAME>`                                           |     30080 (HTTP) / 30443 (HTTPS) |           80 (HTTP) / 443 (HTTPS) |
      | lidarr      | Ingress        | `lidarr.<DOMAIN_NAME>`                                            |     30080 (HTTP) / 30443 (HTTPS) |           80 (HTTP) / 443 (HTTPS) |
      | immich      | Ingress        | `immich.<DOMAIN_NAME>`                                            |     30080 (HTTP) / 30443 (HTTPS) |           80 (HTTP) / 443 (HTTPS) |
      | librespeed  | Ingress        | `librespeed.<DOMAIN_NAME>`                                        |     30080 (HTTP) / 30443 (HTTPS) |           80 (HTTP) / 443 (HTTPS) |
      | calibre-web | Ingress        | `calibre-web.<DOMAIN_NAME>`                                       |     30080 (HTTP) / 30443 (HTTPS) |           80 (HTTP) / 443 (HTTPS) |
      | calibre     | LAN            | `<LAN_IP>:30000` (No ingress rules defined)                       |                            30100 |       `<BEST_NOT_TO_EXPOSE_THIS>` |

      NOTE: Security is an unkown when exposing a service to the internet.

# Appendix

## Prometheus TSDB Backup Restore

In case of a migration, you may choose to wnat to migrate data from prometheus along with the app backups stored in the server's app-config dir.

Resources:
- https://devopstales.github.io/home/backup-and-retore-prometheus/
- https://prometheus.io/docs/prometheus/latest/querying/api/
- https://gist.github.com/ksingh7/d5e4414d92241e0802e59fa4c585b98b

### Enable admin API

```bash
kubectl -n monitoring patch prometheus kube-prometheus-stack-prometheus --type merge --patch '{"spec":{"enableAdminAPI":true}}'
```

### Verify admin API is enabled

```bash
kubectl describe pod -n monitoring prometheus-kube-prometheus-stack-prometheus-0 | grep -i admin
```

To see

```bash
      --web.enable-admin-api
```

### Create TSDB snapshot

Start port forwardning in a different terminal and leave it running

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090
```

Take snapshot

```bash
curl -v -X 'POST' -ks 'localhost:9090/api/v1/admin/tsdb/snapshot'
```

### Download TSDB snapshot

#### Option 1: Download from pod to host

```bash
TMP_DIR=$(mktemp -d)
kubectl cp -c prometheus prometheus-kube-prometheus-stack-prometheus-0:/prometheus/snapshots ${TMP_DIR}
```

#### Option 2: Find the PV on your host and make a backup of the contents [RECOMMENDED]

This is easier and in the context of this server's setup.

```bash
export TMP_DIR=$(mktemp -d)

export PV_DIR=$(kubectl get pv -o yaml $(kubectl get pv | grep monitoring/prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0 | cut -d' ' -f1) | grep "path:" | cut -d " " -f 6)

cp -r ${PV_DIR}/prometheus-db/snapshots/* ${TMP_DIR}
```

### Restore Backup

Copy over your backup to any other host if applicable.

```bash
export PV_DIR=$(kubectl get pv -o yaml $(kubectl get pv | grep monitoring/prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0 | cut -d' ' -f1) | grep "path:" | cut -d " " -f 6)

# clear dir. Might not be needed
rm -rf ${PV_DIR}/prometheus-db/*

# copy over old data
mv ${TMP_DIR}/* ${PV_DIR}/prometheus-db/
```

## Network troubleshooting tools

This repo will be of use: https://github.com/nicolaka/netshoot
