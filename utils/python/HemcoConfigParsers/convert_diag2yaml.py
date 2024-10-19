import yaml
import re
import argparse
import logging
from typing import Dict, List

def setup_logging() -> None:
    """
    Sets up the logging configuration.
    """
    logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def parse_hemco_diagn(file_path: str) -> Dict[str, List[Dict[str, str]]]:
    """
    Parses a HEMCO diagnostics configuration file.

    Args:
        file_path (str): Path to the HEMCO diagnostics file.

    Returns:
        Dict[str, List[Dict[str, str]]]: Parsed diagnostics data.
    """
    logging.info(f"Starting to parse file: {file_path}")
    with open(file_path, 'r') as file:
        lines = file.readlines()

    diagn_dict = {}
    current_section = None

    for line in lines:
        if line.startswith('!') or line.startswith('#'):
            continue  # Skip comments
        if re.match(r'^\s*$', line):
            continue  # Skip empty lines

        if line.startswith('BEGIN'):
            section_name = line.split(' ')[1].strip()
            current_section = section_name
            diagn_dict[current_section] = []
            logging.info(f"Started section: {section_name}")
        elif line.startswith('END'):
            logging.info(f"Ended section: {current_section}")
            current_section = None
        else:
            if current_section:
                parts = line.split()
                diagn_dict[current_section].append({
                    "Name": parts[0],
                    "Spec": parts[1],
                    "ExtNr": parts[2],
                    "Cat": parts[3],
                    "Hier": parts[4],
                    "Dim": parts[5],
                    "OutUnit": parts[6],
                    "LongName": " ".join(parts[7:])
                })
                logging.debug(f"Parsed line: {parts}")

    logging.info(f"Finished parsing file: {file_path}")
    return diagn_dict

def convert_to_yaml(diagn_dict: Dict[str, List[Dict[str, str]]], output_path: str) -> None:
    """
    Converts a dictionary to a YAML file.

    Args:
        diagn_dict (Dict[str, List[Dict[str, str]]]): Dictionary to convert.
        output_path (str): Path to the output YAML file.
    """
    logging.info(f"Starting to convert dictionary to YAML file: {output_path}")
    with open(output_path, 'w') as file:
        yaml.dump(diagn_dict, file, default_flow_style=False)
    logging.info(f"YAML file created at: {output_path}")

def main() -> None:
    """
    Main function to parse command line arguments and convert HEMCO diagnostics file to YAML.
    """
    setup_logging()
    parser = argparse.ArgumentParser(description="Convert HEMCO diagnostics file to YAML format.")
    parser.add_argument('input', type=str, help='Path to the HEMCO_Diagn.rc file')
    parser.add_argument('output', type=str, help='Path to the output YAML file')

    args = parser.parse_args()

    logging.info(f"Received input file: {args.input}")
    logging.info(f"Received output file: {args.output}")

    diagn_dict = parse_hemco_diagn(args.input)
    convert_to_yaml(diagn_dict, args.output)

    logging.info('Conversion complete!')

if __name__ == '__main__':
    main()


