import yaml
import re
import argparse
import logging
from typing import Dict, Any

def setup_logging(enable_logging: bool) -> None:
    """
    Sets up the logging configuration.

    Args:
        enable_logging (bool): Flag to enable or disable logging.
    """
    if enable_logging:
        logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
    else:
        logging.basicConfig(level=logging.CRITICAL)  # Only log critical issues

def parse_hemco_config(file_path: str) -> Dict[str, Any]:
    """
    Parses a HEMCO configuration file.

    Args:
        file_path (str): Path to the HEMCO configuration file.

    Returns:
        Dict[str, Any]: Parsed configuration data.
    """
    logging.info(f"Starting to parse file: {file_path}")
    with open(file_path, 'r') as file:
        lines = file.readlines()

    config_dict = {}
    current_section = None
    current_sub_section = None

    for line in lines:
        if line.startswith('!') or line.startswith('#'):
            continue  # Skip comments
        if re.match(r'^\s*$', line):
            continue  # Skip empty lines

        if line.startswith('BEGIN SECTION'):
            section_name = line.split('SECTION')[1].strip()
            current_section = section_name
            config_dict[current_section] = {}
            logging.info(f"Started section: {section_name}")
        elif line.startswith('END SECTION'):
            logging.info(f"Ended section: {current_section}")
            current_section = None
            current_sub_section = None
        elif line.startswith('%'):
            continue  # Skip lines with just '%'
        else:
            if current_section:
                if ':' in line:
                    key, value = line.split(':', 1)
                    key = key.strip()
                    value = value.strip()
                    config_dict[current_section][key] = value
                    logging.debug(f"Parsed key-value pair: {key}: {value}")
                else:
                    parts = line.split()
                    if current_sub_section:
                        config_dict[current_section][current_sub_section].append(parts)
                    else:
                        current_sub_section = parts[0]
                        config_dict[current_section][current_sub_section] = [parts]
                    logging.debug(f"Parsed sub-section: {parts}")

    logging.info(f"Finished parsing file: {file_path}")
    return config_dict

def convert_to_yaml(config_dict: Dict[str, Any], output_path: str) -> None:
    """
    Converts a dictionary to a YAML file.

    Args:
        config_dict (Dict[str, Any]): Dictionary to convert.
        output_path (str): Path to the output YAML file.
    """
    logging.info(f"Starting to convert dictionary to YAML file: {output_path}")
    with open(output_path, 'w') as file:
        yaml.dump(config_dict, file, default_flow_style=False)
    logging.info(f"YAML file created at: {output_path}")

def main() -> None:
    """
    Main function to parse command line arguments and convert HEMCO configuration file to YAML.
    """
    parser = argparse.ArgumentParser(description="Convert HEMCO configuration file to YAML format.")
    parser.add_argument('input', type=str, help='Path to the HEMCO_Config.rc file')
    parser.add_argument('output', type=str, help='Path to the output YAML file')
    parser.add_argument('--no-log', action='store_true', help='Disable logging')

    args = parser

