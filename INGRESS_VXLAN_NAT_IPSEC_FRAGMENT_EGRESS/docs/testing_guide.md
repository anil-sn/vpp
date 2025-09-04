# Testing Guide

This guide provides instructions on how to test the VPP Multi-Container Chain, including different test types and how to use various deployment modes.

## Prerequisites

Before running any tests, ensure the following:

*   **Environment Setup:** The VPP multi-container chain must be set up and running. Use the `setup` command to prepare the environment.
    ```bash
    sudo python3 src/main.py setup
    ```
*   **Root Privileges:** All test commands require `sudo` as they interact with Docker and network configurations.

## Running Tests

Tests are executed via the `test` command of the main script. You can specify the type of test and the deployment mode.

### 1. Run the Full Test Suite

This command will first verify inter-container connectivity and then proceed to generate and analyze traffic. This is the most comprehensive test.

```bash
sudo python3 src/main.py test
```

### 2. Test Only Connectivity

This command will only verify inter-container connectivity without generating traffic. This is useful for quickly checking network reachability between containers.

```bash
sudo python3 src/main.py test --type connectivity
```

### 3. Test Only Traffic Generation

This command will only generate and analyze traffic, assuming connectivity is already established. This is useful for focusing on data plane performance and processing.

```bash
sudo python3 src/main.py test --type traffic
```

## Specifying Deployment Modes

The system supports different deployment modes (e.g., `gcp`, `aws`) defined in `config.json`. You can specify the mode for any command that relies on the configuration.

If no `--mode` is specified, the system will use the `default_mode` defined in `config.json` (currently `gcp`).

### Example: Running Tests in AWS Mode

1.  **Setup for AWS Mode:**
    ```bash
    sudo python3 src/main.py setup --mode aws
    ```

2.  **Run Full Test in AWS Mode:**
    ```bash
    sudo python3 src/main.py test --mode aws
    ```

3.  **Run Connectivity Test in GCP Mode (explicitly):**
    ```bash
    sudo python3 src/main.py test --type connectivity --mode gcp
    ```

## Other Useful Commands

While testing, you might find these commands helpful:

*   **Show Current Status:** Displays the status of all containers and the chain topology.
    ```bash
    sudo python3 src/main.py status [--mode <mode>]
    ```

*   **Monitor the Chain:** Monitors the chain for a specified duration, showing VPP interface statistics.
    ```bash
    sudo python3 src/main.py monitor --duration 120 [--mode <mode>]
    ```

*   **Debug a Specific Container:** Executes a VPP command inside a specified container for debugging.
    ```bash
    sudo python3 src/main.py debug chain-nat "show nat44 sessions" [--mode <mode>]
    ```

*   **Clean Up the Environment:** Stops and removes all Docker containers and networks created by the setup.
    ```bash
    sudo python3 src/main.py cleanup [--mode <mode>]
    ```

By following this guide, you can effectively test the VPP Multi-Container Chain in various configurations and modes.
