I have started initializing the Frappe version-16 bench (bench init --ignore-exist --skip-redis-config-generation --frappe-branch version-16). Waiting for the environment setup and cloning to complete.

background job
docker compose exec frappe bash -c "cd /workspace && bench init --ignore-exist --skip-redis-config-generation --frappe-branch version-16 --verbose frappe-bench"

---

I have started fetching ERPNext version-16 (bench get-app --branch version-16 --resolve-deps erpnext). Waiting for the installation to finish.

background job
docker compose exec frappe bash -c "cd /workspace/frappe-bench && bench get-app --branch version-16 --resolve-deps erpnext"
