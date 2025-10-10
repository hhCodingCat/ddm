import pandas as pd
import concurrent.futures
import os
import json
import requests
import yaml
import ipaddress

def read_yaml_from_url(url):
    response = requests.get(url)
    response.raise_for_status()
    yaml_data = yaml.safe_load(response.text)
    return yaml_data

def read_list_from_url(url):
    response = requests.get(url)
    response.raise_for_status()
    lines = response.text.strip().splitlines()
    # 对于纯 TXT 列表，每行一个规则
    rows = []
    for line in lines:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        # 检查是否 Clash 格式 (pattern,address)
        if ',' in line:
            parts = line.split(',', 1)
            pattern = parts[0].strip()
            address = parts[1].strip()
            rows.append({'pattern': pattern, 'address': address, 'other': None})
        else:
            # 纯域名列表：假设 DOMAIN-SUFFIX
            rows.append({'pattern': 'DOMAIN-SUFFIX', 'address': line, 'other': None})
    df = pd.DataFrame(rows, columns=['pattern', 'address', 'other'])
    return df

def is_ipv4_or_ipv6(address):
    try:
        ipaddress.IPv4Network(address)
        return 'ipv4'
    except ValueError:
        try:
            ipaddress.IPv6Network(address)
            return 'ipv6'
        except ValueError:
            return None

def parse_and_convert_to_dataframe(link):
    if link.endswith('.yaml') or link.endswith('.yml'):
        try:
            yaml_data = read_yaml_from_url(link)
            rows = []
            if isinstance(yaml_data, dict) and 'payload' in yaml_data:
                items = yaml_data.get('payload', [])
            elif isinstance(yaml_data, str):
                lines = yaml_data.splitlines()
                items = [line.strip("'") for line in lines if line.strip()]
            else:
                items = yaml_data if isinstance(yaml_data, list) else []
            
            for item in items:
                item = item.strip("'")
                if ',' in item:
                    pattern, address = item.split(',', 1)
                    rows.append({'pattern': pattern.strip(), 'address': address.strip(), 'other': None})
                else:
                    # 纯项：检查 IP 或域名
                    ip_type = is_ipv4_or_ipv6(item)
                    if ip_type:
                        pattern = 'IP-CIDR' if ip_type == 'ipv4' else 'IP-CIDR6'
                    elif item.startswith('+') or item.startswith('.'):
                        pattern = 'DOMAIN-SUFFIX'
                        address = item.lstrip('+.')
                    else:
                        pattern = 'DOMAIN'
                    rows.append({'pattern': pattern, 'address': item, 'other': None})
            df = pd.DataFrame(rows, columns=['pattern', 'address', 'other'])
        except Exception as e:
            print(f"Error parsing YAML {link}: {e}")
            df = pd.DataFrame(columns=['pattern', 'address', 'other'])
    else:
        df = read_list_from_url(link)
    return df

def sort_dict(obj):
    if isinstance(obj, dict):
        return {k: sort_dict(obj[k]) for k in sorted(obj)}
    elif isinstance(obj, list) and all(isinstance(elem, dict) for elem in obj):
        return sorted([sort_dict(x) for x in obj], key=lambda d: sorted(d.keys())[0])
    elif isinstance(obj, list):
        return sorted(sort_dict(x) for x in obj)
    else:
        return obj

def parse_list_file(link, output_directory):
    with concurrent.futures.ThreadPoolExecutor() as executor:
        results = list(executor.map(parse_and_convert_to_dataframe, [link]))
        df = pd.concat(results, ignore_index=True)

    df = df[~df['pattern'].str.contains('#', na=False)].reset_index(drop=True)

    map_dict = {'DOMAIN-SUFFIX': 'domain_suffix', 'HOST-SUFFIX': 'domain_suffix', 'DOMAIN': 'domain', 'HOST': 'domain', 'host': 'domain',
                'DOMAIN-KEYWORD':'domain_keyword', 'HOST-KEYWORD': 'domain_keyword', 'host-keyword': 'domain_keyword', 'IP-CIDR': 'ip_cidr',
                'ip-cidr': 'ip_cidr', 'IP-CIDR6': 'ip_cidr', 
                'IP6-CIDR': 'ip_cidr','SRC-IP-CIDR': 'source_ip_cidr', 'GEOIP': 'geoip', 'DST-PORT': 'port',
                'SRC-PORT': 'source_port', "URL-REGEX": "domain_regex"}

    df = df[df['pattern'].isin(map_dict.keys())].reset_index(drop=True)

    df = df.drop_duplicates().reset_index(drop=True)
    df['pattern'] = df['pattern'].replace(map_dict)

    os.makedirs(output_directory, exist_ok=True)

    result_rules = {"version": 3, "rules": []}  # 更新到 version 3
    domain_entries = []

    for pattern, addresses in df.groupby('pattern')['address'].apply(list).to_dict().items():
        if pattern == 'domain_suffix':
            rule_entry = {pattern: ['.' + address.strip() for address in addresses]}
            result_rules["rules"].append(rule_entry)
            domain_entries.extend([address.strip() for address in addresses])
        elif pattern == 'domain':
            domain_entries.extend([address.strip() for address in addresses])
        else:
            rule_entry = {pattern: [address.strip() for address in addresses]}
            result_rules["rules"].append(rule_entry)
    domain_entries = list(set(domain_entries))
    if domain_entries:
        result_rules["rules"].insert(0, {'domain': domain_entries})

    file_name = os.path.join(output_directory, f"{os.path.basename(link).split('.')[0]}.json")
    with open(file_name, 'w', encoding='utf-8') as output_file:
        json.dump(sort_dict(result_rules), output_file, ensure_ascii=False, indent=2)

    srs_path = file_name.replace(".json", ".srs")
    compile_cmd = f"sing-box rule-set compile --output {srs_path} {file_name}"
    result = os.system(compile_cmd)
    if result != 0:
        print(f"Error compiling SRS for {link}: {result}")
    return file_name

with open("../source.txt", 'r') as links_file:
    links = links_file.read().splitlines()

links = [l for l in links if l.strip() and not l.strip().startswith("#")]

output_dir = "./"
result_file_names = []

for link in links:
    result_file_name = parse_list_file(link, output_directory=output_dir)
    result_file_names.append(result_file_name)

for file_name in result_file_names:
    print(file_name)
