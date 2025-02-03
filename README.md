## **SC23 Dockerized Nginx Configuration**

This project uses an Nginx configuration to map subdomains for each project in the Docker Compose setup. The configuration supports both local development (`sc23.local`) by updating `/etc/hosts` and deployment on a VPS (`sc23.site`) with wildcard HTTPS certification. For more details, refer to the [docker-compose.yml](../docker-compose.yml) file in the root of the repository.

I'm doing this repository public to share my Nginx configuration for local development and VPS deployment so you can use it as a reference for your projects, I don't intend to do a cookie-cutter solution for everyone, but I hope it helps you to understand how to configure Nginx for your projects with the following instructions.

### **General Setup**

1. **Set your projects to be pulled from Git**
    - Modify `pull_projects.sh` and add your projects.
    - Run `chmod +x pull_projects.sh`.
    - Run `./pull_projects.sh` to pull your projects.
    - This will clone your projects into the `projects` directory.

2. **Update the `docker-compose.yml` file**
    - Replace `sc23` with your domain name `yoursite`.
    - Remove all the services you don't need.
    - Add your own, make the context to the Dockerfile match each project you pulled.
    - You can use a `.env` file to store your environment variables.

### **Local Development Setup**

1. **Update `/etc/hosts` if you want to use the subdomains locally**
    ```bash
    sudo vi /etc/hosts
    ```
    Add the following lines:
    ```
    ##
    # Host Database
    #
    # localhost is used to configure the loopback interface
    # when the system is booting.  Do not change this entry.
    ##
    127.0.0.1       localhost
    255.255.255.255 broadcasthost
    ::1             localhost
    # 👇 Starting Here 👇
    127.0.0.1       yoursite.local
    127.0.0.1       aproject.yoursite.local
    127.0.0.1       anotherproject.yoursite.local
    # 👆 and so on...👆
    ```
    For Windows, you can edit the `hosts` file located at `C:\Windows\System32\drivers\etc\hosts`.

2. **Nginx Configuration for Local Development**
    - Modify your `nginx.conf` to add your main domain and subdomains replacing `sc23.local` with your domain `yoursite.local`, this should match your projects in the `docker-compose.yml` file.

### **VPS Deployment Setup**

1. **Wildcard HTTPS Certification**
    - Use a service like Let's Encrypt to obtain a wildcard certificate for `*.yoursite.com`.

2. **Nginx Configuration for VPS**
    - Ensure your `nginx.conf` maps the subdomains correctly for `yoursite.com` and includes the wildcard HTTPS certificate.

3. **Find and replace**
    - Replace all instances of `sc23.site` with your domain name `yoursite.com`.
    - Change the certificate paths to your wildcard certificate paths.

### **Running the services**

1. **Build the services**
    ```bash
    docker-compose up --build
    ```

2. **Testing URLs**
    - Open your browser and navigate to `http://yoursite.local` to see the main domain locally.
    - If you are in your VPS, you should be able to see the main domain `https://yoursite.com`.

2. **Stop the services**
    ```bash
    docker-compose down
    ```

