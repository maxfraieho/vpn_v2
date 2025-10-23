# VPN and Proxy Management System

This repository contains a collection of scripts and configurations for managing VPN and proxy services.

## Overview

The system includes various components for handling network routing, proxy services, and connection management through different protocols and technologies.

## Components

- Shell scripts for management and automation
- Python scripts for service control and routing
- Configuration files for various services
- Documentation files

## Setup

1. Clone the repository
2. Review and modify configuration files as needed
3. Run the appropriate management scripts based on your requirements

## Scripts

- `manager_v2.sh` - Main management script
- `smart_proxy_v2.py` - Python-based proxy management
- `survey_automation_v2.py` - Automation script
- `run_md_service.sh` - Service runner
- `test_routing.sh` - Routing test script
- `diagnostic.sh` - System diagnostics

## Special Notes for Termux/Android Users

If you're running this system on Termux/Android:

1. Some diagnostic tools may not work properly due to platform limitations
2. See `TERMUX_README.md` for specific instructions and known issues
3. Network connectivity testing should be done externally rather than relying on internal diagnostics

## Notes

- Configuration files may contain sensitive information - review .gitignore before deployment
- Some components may require specific dependencies
- Review all configuration files before use in production environments