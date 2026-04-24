#!/usr/bin/env python3
import json
import subprocess

def get_tofu_output():
    result = subprocess.run(
        ["tofu", "output", "-json"],
        cwd="../tofu",
        capture_output=True,
        text=True
    )
    return json.loads(result.stdout)

def main():
    data = get_tofu_output()

    master_ip = data["master_ip"]["value"]
    worker_ips = data["worker_ips"]["value"]

    inventory = {
        "master": {"hosts": [master_ip]},
        "workers": {"hosts": worker_ips},
        "all": {
            "vars": {
                "ansible_user": "ubuntu",
                "ansible_ssh_private_key_file": "~/.ssh/id_rsa"
            }
        }
    }

    print(json.dumps(inventory, indent=2))

if __name__ == "__main__":
    main()
