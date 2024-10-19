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

def parse_hemco_grid(file_path: str) -> Dict[str, Any]:
    """
    Parses a HEMCO grid configuration file.

    Args:
        file_path (str): Path to the HEMCO grid configuration file.

    Returns:
        Dict[str, Any]: Parsed grid configuration data.
    """
    logging.info(f"Starting to parse file: {file_path}")
    with open(file_path, 'r') as file:
        lines = file.readlines()

    grid_dict = {}
    for line in lines:
        if line.startswith('!') or line.startswith('#'):
            continue  # Skip comments
        if re.match(r'^\s*$', line):
            continue  # Skip empty lines

        if ':' in line:
            key, value = line.split(':', 1)
            key = key.strip()
            value = value.split('#')[0].strip()  # Remove inline comments
            grid_dict[key] = value
            logging.debug(f"Parsed key-value pair: {key}: {value}")

    logging.info(f"Finished parsing file: {file_path}")
    return grid_dict

def convert_to_yaml(grid_dict: Dict[str, Any], output_path: str) -> None:
    """
    Converts a dictionary to a YAML file.

    Args:
        grid_dict (Dict[str, Any]): Dictionary to convert.
        output_path (str): Path to the output YAML file.
    """
    logging.info(f"Starting to convert dictionary to YAML file: {output_path}")
    with open(output_path, 'w') as file:
        yaml.dump(grid_dict, file, default_flow_style=False)
    logging.info(f"YAML file created at: {output_path}")

def main() -> None:
    """
    Main function to parse command line arguments and convert HEMCO grid configuration file to YAML.
    """
    parser = argparse.ArgumentParser(description="Convert HEMCO grid configuration file to YAML format.")
    parser.add_argument('input', type=str, help='Path to the HEMCO grid configuration file')
    parser.add_argument('output', type=str, help='Path to the output YAML file')
    parser.add_argument('--log', action='store_true', default=True, help='Enable logging')

    args = parser.parse_args()

    setup_logging(args.log)
    
    logging.info(f"Received input file: {args.input}")
    logging.info(f"Received output file: {args.output}")

    grid_dict = parse_hemco_grid(args.input)
    convert_to_yaml(grid_dict, args.output)

    logging.info('Conversion complete!')

if __name__ == '__main__':
    main()
