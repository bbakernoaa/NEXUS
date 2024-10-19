import yaml
import re

def parse_hemco_config(file_path):
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
        elif line.startswith('END SECTION'):
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
                else:
                    parts = line.split()
                    if current_sub_section:
                        config_dict[current_section][current_sub_section].append(parts)
                    else:
                        current_sub_section = parts[0]
                        config_dict[current_section][current_sub_section] = [parts]

    return config_dict

def convert_to_yaml(config_dict, output_path):
    with open(output_path, 'w') as file:
        yaml.dump(config_dict, file, default_flow_style=False)

if __name__ == '__main__':
    hemco_config_path = 'path/to/hemco_config.rc'
    yaml_output_path = 'path/to/output.yaml'
    
    config_dict = parse_hemco_config(hemco_config_path)
    convert_to_yaml(config_dict, yaml_output_path)
    print(f'Conversion complete! YAML file created at {yaml_output_path}')
