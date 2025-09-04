
import yaml
from pathlib import Path
from src.utils.config_manager import ConfigManager

def generate_compose_for_mode(mode: str, output_filename: str):
    print(f"Generating {output_filename} for mode '{mode}'...")
    
    config_manager = ConfigManager(mode=mode)
    networks = config_manager.get_networks()
    containers = config_manager.get_containers()
    project_root = Path(__file__).parent

    compose_data = {
        "services": {},
        "networks": {},
        "volumes": {
            "vpp-logs": {"driver": "local"},
            "packet-captures": {"driver": "local"}
        }
    }

    for net in networks:
        compose_data["networks"][net["name"]] = {
            "driver": "bridge",
            "ipam": {
                "config": [
                    {"subnet": net["subnet"]}
                ]
            }
        }
        if "gateway" in net:
            compose_data["networks"][net["name"]]["ipam"]["config"][0]["gateway"] = net["gateway"]

    for i, container in enumerate(containers):
        service_name = container["name"]
        networks_config = {}
        for net_name, ip_address in container["networks"].items():
            networks_config[net_name] = {"ipv4_address": ip_address}

        depends_on = []
        if i > 0:
            depends_on.append(containers[i - 1]["name"])

        compose_data["services"][service_name] = {
            "build": {
                "context": ".",
                "dockerfile": container["dockerfile"]
            },
            "container_name": service_name,
            "hostname": service_name,
            "privileged": True,
            "volumes": [
                f"./src/containers/{service_name.replace('chain-', '')}:/vpp-config:ro",
                "./src/configs:/vpp-common:ro",
                "/tmp/vpp-logs:/var/log/vpp"
            ],
            "networks": networks_config,
            "cap_add": ["NET_ADMIN", "SYS_ADMIN", "IPC_LOCK"],
            "ulimits": {
                "memlock": {"soft": -1, "hard": -1}
            },
            "depends_on": depends_on
        }
        if service_name == "chain-gcp":
            compose_data["services"][service_name]["volumes"].append("/tmp/packet-captures:/tmp")

    output_path = project_root / output_filename
    try:
        with open(output_path, 'w') as f:
            yaml.dump(compose_data, f, sort_keys=False)
        print(f"Successfully generated {output_path}")
    except Exception as e:
        print(f"Error writing {output_path}: {e}")

if __name__ == "__main__":
    try:
        import yaml
    except ImportError:
        print("Error: PyYAML is not installed. Please install it using: pip install pyyaml")
        exit(1)
        
    generate_compose_for_mode("gcp", "docker-compose.yml")
    generate_compose_for_mode("gcp", "docker-compose-gcp.yml")
    generate_compose_for_mode("aws", "docker-compose-aws.yml")
