# Camunda 8 Docker Installation Script 🚀

## 1. Project Description
This project provides a **cloud-agnostic shell script** to install and configure **Camunda 8** using **Docker Compose** on any Linux-based VM. It automates:
- ✅ Installation of required tools
- ✅ Docker & Docker Compose setup
- ✅ Elasticsearch kernel configuration
- ✅ Camunda Docker Compose bundle download
- ✅ Environment configuration
- ✅ Camunda stack startup
- ✅ Health check execution
---

## 2. Installation

### Pre-requisites
| Component      | Requirement               |
|---------------|----------------------------|
| **OS**        | Ubuntu 20.04 or later      |
| **Hardware**  | 4 GB RAM, 2 vCPUs          |
| **Software**  | bash, curl, unzip, tar, yq |
| **Privileges**| Root or sudo access        |
| **Optional**  | `yq` for YAML editing      |
---

### Steps
```bash
# 1. Clone the repository
git clone <repo-url>
cd <repo-folder>

# 2. Make script executable
chmod +x CamundaDockerInstall.sh

# 3. Run the script
./CamundaDockerInstall.sh
```

The script will:
- Install required tools
- Install Docker & Docker Compose
- Configure Elasticsearch
- Download Camunda bundle
- Configure .env and docker-compose.yaml
- Start Camunda stack

---

## 3. Usage
./CamundaDockerInstall.sh

After successful installation, access services via:

| Service        | URL                             |
|---------------|----------------------------------|
| **Web Modeler** | http://<VM-IP>:8070            |
| **Operate**     | http://<VM-IP>:8088/operate    |
| **Optimize**    | http://<VM-IP>:8083            |
| **Tasklist**    | http://<VM-IP>:8088/tasklist   |
| **Identity**    | http://<VM-IP>:8088/identity   |
| **Elasticsearch**| http://<VM-IP>:9200           |
| **Keycloak**    | http://<VM-IP>:18080/auth/     |

**Default Credentials:** `admin/admin`

---

## 4. Change Log
- **v1.0 (2025-08-21)**
  - Initial release
  - Added rollback mechanism
  - Health check integration
---

## 5. License Info
Apache License, Version 2.0

---

## 7. Author Info
- **Author**: Shivam Bhardwaj
- **Reviewer**: Sumit Sahay

---

## Example Logs
```
[2025-08-21 10:00:00] STEP 1: Checking Docker...
[2025-08-21 10:00:05] SUCCESS: Docker installed successfully.
[2025-08-21 10:05:00] STEP 6: Starting Camunda stack...
[2025-08-21 10:05:30] SUCCESS: Camunda stack started successfully.
```

---

## Troubleshooting
| Issue                          | Solution |
|--------------------------------|----------|
| Docker not found              | Ensure Docker is installed and running |
| Permission denied             | Run script with sudo |
| Camunda services not starting | Check logs in logs/servicelog_<timestamp>.log |
| Health check failed           | Verify ports 8070 and 8080 are open |
| Character mismatch error      | Run `dos2unix camundacomposeinstall.sh` and `dos2unix camundahealthcheck.sh` |

## NOTE: If you encounter character mismatch or unexpected behavior due to hidden ^M characters: (When files are created or edited in Windows, they typically use CRLF (Carriage Return + Line Feed) as line endings. Unix/Linux systems use just LF (Line Feed). This difference can cause issues when running shell scripts on Linux that were originally written or edited in Windows. dos2unix removes the carriage return characters (\r) so the file becomes compatible with Unix/Linux systems.)



