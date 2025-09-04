import json
from pathlib import Path

class ConfigManager:
    _instance = None

    def __new__(cls, config_file='config.json', mode=None):
        if cls._instance is None:
            cls._instance = super(ConfigManager, cls).__new__(cls)
            cls._instance._initialize(config_file, mode)
        elif mode and cls._instance._current_mode != mode:
            # Re-initialize if mode changes
            cls._instance._initialize(config_file, mode)
        return cls._instance

    def _initialize(self, config_file, mode):
        self.project_root = Path(__file__).parent.parent.parent
        self.config_path = self.project_root / config_file
        self._load_config()
        self._current_mode = mode if mode else self.config.get("default_mode", "gcp")
        self.current_config = self.config["modes"][self._current_mode]

    def _load_config(self):
        try:
            with open(self.config_path, 'r') as f:
                self.config = json.load(f)
        except FileNotFoundError:
            raise FileNotFoundError(f"Configuration file not found: {self.config_path}")
        except json.JSONDecodeError as e:
            raise json.JSONDecodeError(f"Error decoding JSON from {self.config_path}: {e}", e.doc, e.pos)

    def get_networks(self):
        return self.current_config["networks"]

    def get_containers(self):
        return self.current_config["containers"]

    def get_connectivity_tests(self):
        return self.current_config["connectivity_tests"]

    def get_traffic_config(self):
        return self.current_config["traffic_config"]

    def get_mode(self):
        return self._current_mode
