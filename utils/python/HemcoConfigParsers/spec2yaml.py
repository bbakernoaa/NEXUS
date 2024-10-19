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

def parse_hemco_species(file_path: str) -> Dict[str, Any]:
    """
    Parses a HEMCO species configuration file.

    Args:
        file_path (str): Path to the HEMCO species configuration file.

    Returns:
        Dict[str, Any]: Parsed species configuration data.
    """
    logging.info(f"Starting to parse file: {file_path}")
    with open(file_path, 'r') as file:
        lines = file.readlines()

    species_dict = {}
    current_section = None

    for line in lines:
        if line.startswith('!') or line.startswith('#'):
            continue  # Skip comments
        if re.match(r'^\s*$', line):
            continue  # Skip empty lines

        if line.startswith('BEGIN'):
            section_name = line.split(' ')[1].strip()
            current_section = section_name
            species_dict[current_section] = {}
            logging.info(f"Started section: {section_name}")
        elif line.startswith('END'):
            logging.info(f"Ended section: {current_section}")
            current_section = None
        else:
            if current_section:
                parts = line.split()
                species_dict[current_section][parts[1]] = {
                    "MW": parts[2],
                    "K0": parts[3],
                    "CR": parts[4],
                    "pKA": parts[5]
                }
                logging.debug(f"Parsed line: {parts}")

    logging.info(f"Finished parsing file: {file_path}")
    return species_dict

def convert_to_yaml(species_dict: Dict[str, Any], output_path: str) -> None:
    """
    Converts a dictionary to a YAML file.

    Args:
        species_dict (Dict[str, Any]): Dictionary to convert.
        output_path (str): Path to the output YAML file.
    """
    logging.info(f"Starting to convert dictionary to YAML file: {output_path}")
    with open(output_path, 'w') as file:
        yaml.dump(species_dict, file, default_flow_style=False)
    logging.info(f"YAML file created at: {output_path}")

def main() -> None:
    """
    Main function to parse command line arguments and convert HEMCO species configuration file to YAML.
    """
    parser = argparse.ArgumentParser(description="Convert HEMCO species configuration file to YAML format.")
    parser.add_argument('input', type=str, help='Path to the HEMCO_Species.rc file')
    parser.add_argument('output', type=str, help='Path to the output YAML file')
    parser.add_argument('--log', action='store_true', default=True, help='Enable logging')

    args = parser.parse_args()

    setup_logging(args.log)
    
    logging.info(f"Received input file: {args.input}")
    logging.info(f"Received output file: {args.output}")

    species_dict = parse_hemco_species(args.input)
    convert_to_yaml(species_dict, args.output)

    logging.info('Conversion complete!')

if __name__ == '__main__':
    main()
