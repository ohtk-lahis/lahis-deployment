#!/usr/bin/env python3
"""Offline structural/template checks; no database or project imports."""
from datetime import date
import hashlib
import json
import subprocess
from pathlib import Path
import re
import runpy

from django.conf import settings
from django.template import Context, Engine
from django.template.defaultfilters import striptags

ROOT = Path(__file__).resolve().parents[2]
SEED = Path(__file__).resolve().parent
source_info = json.loads((SEED / 'source.json').read_text())
source_bytes = subprocess.check_output(['git', '-C', source_info['source_repository'], 'show',
                                       source_info['revision'] + ':' + source_info['path']])
assert hashlib.sha256(source_bytes).hexdigest() == source_info['sha256']
baseline = json.loads(source_bytes)
candidate = json.loads((ROOT / 'seeds/tot/report-setup.json').read_text())
loader = runpy.run_path(str(ROOT / 'scripts/apply-report-configuration.py'))['read_seed']
config = loader(ROOT / 'seeds/tot')
audit_raw = runpy.run_path(str(ROOT / 'scripts/apply-report-configuration.py'))['read_audit_configuration'](ROOT / 'seeds/tot')
assert json.loads(audit_raw)['reason'] == 'ເຫດຜົນ'
settings.configure(USE_I18N=False, USE_L10N=False)
engine = Engine()


def differences(old, new, path=''):
    if isinstance(old, dict):
        assert set(old) == set(new), path
        for k in old:
            yield from differences(old[k], new[k], path + '/' + k)
    elif isinstance(old, list):
        for i in range(max(len(old), len(new))):
            if i >= len(old):
                yield {'path': path + '/' + str(i), 'before': None, 'after': new[i]}
            else:
                yield from differences(old[i], new[i], path + '/' + str(i))
    elif old != new:
        yield {'path': path, 'before': old, 'after': new}


actual = list(differences(baseline, candidate))
recorded = json.loads((SEED / 'property-diff.json').read_text())
assert actual == [{k: r[k] for k in ['path', 'before', 'after']} for r in recorded]
assert len(actual) == 14
assert config['name'] == 'ສັດປ່ວຍ/ຕາຍ'
# Exact deep equality proves latest vocabulary, IDs, constraints and structure are retained.
for key in ['definition', 'followup_definition']:
    assert config[key] == baseline['reports'][0][key], key
for change in actual:
    p = change['path']
    assert p in ['/reports/0/name', '/reports/0/renderer_data_template',
                 '/reports/0/renderer_followup_data_template', '/configurations/14', '/configurations/15',
                 '/reports/0/close_definition/sections/0/questions/0/description',
                 '/reports/0/close_definition/sections/0/questions/1/description'] or (
                 ('/metric_accumulation/metrics/' in p or '/close_definition/sections/' in p)
                 and p.endswith('/label')), p
# Full snapshot preserves unrelated workflow, authority/flag and tenant config content.
assert candidate['configurations'][:-2] == baseline['configurations']
for key in ['source', 'captured_on', 'categories', 'states', 'user_configurations']:
    assert candidate[key] == baseline[key], key
for key in ['ordering', 'published', 'is_followable', 'category', 'state_definition', 'state_mappings', 'authority_codes']:
    assert candidate['reports'][0][key] == baseline['reports'][0][key], key

close_questions = config['close_definition']['sections'][0]['questions']
assert close_questions[0]['fields'] == baseline['reports'][0]['close_definition']['sections'][0]['questions'][0]['fields']
assert close_questions[1]['fields'] == baseline['reports'][0]['close_definition']['sections'][0]['questions'][1]['fields']
# Audience wording is reviewed in context; unchanged field constraints above preserve the numeric rule.
assert 'ເລກອ້າງອີງ' in close_questions[0]['description']
assert 'ຜ່ານສ່ວນຄຳຄິດເຫັນ (Comments)' in close_questions[0]['description']

form = config['definition']
species = form['sections'][0]['questions'][0]['fields'][0]['options']
disease_questions = form['sections'][1]['questions']
for option in species:
    # Baseline single-choice evaluates the selected raw value before adding text.
    matches = [q for q in disease_questions if option['value'] in [x.strip() for x in q['condition']['value'].split(',')]]
    assert len(matches) == 1, option
assert species[-1]['textInput'] is True
for q in disease_questions:
    assert q['condition']['name'] == 'animal_species'
    assert set(x.strip() for x in q['condition']['value'].split(',')) <= {o['value'] for o in species}

options_checked = 0
for section in form['sections']:
    for question in section['questions']:
        for field in question['fields']:
            options = field.get('options', [])
            assert len({o['value'] for o in options}) == len(options)
            for option in options:
                assert option['label'] == option['value'] and re.search('[\u0e80-\u0eff]', option['value'])
                if field['name'] == 'animal_species':
                    assert ',' not in option['value'], 'condition delimiter inside species option'
                options_checked += 1
assert options_checked == len(json.loads((SEED / 'value-dependencies.json').read_text()))


def multi(*values):
    # Same payload shape produced by baseline mobile/web: selected-key booleans + value.
    return dict([(value, True) for value in values] + [('value', ', '.join(values))])


def render(field, context):
    return striptags(engine.from_string(config[field]).render(Context(context)))


fields = {f['name']: f for s in form['sections'] for q in s['questions'] for f in q['fields']}
symptom_fields = ['digestive_symptoms', 'skin_external_symptoms', 'respiratory_symptoms',
                  'reproductive_symptoms', 'nervous_symptoms', 'general_symptoms', 'abnormalities_carcass']
base_data = {'num_sick': 2, 'num_dead': 0, 'num_recover': 1, 'num_total_animal': 20, 'num_household': 3,
             'animal_age_groups': multi('ສັດແຮກເກີດ', 'ສັດໂຕເຕັມໄວ'), 'animal_sex': multi('ເພດຜູ້', 'ເພດແມ່'),
             'unknown_symptoms': 'ຂໍ້ຄວາມອິດສະຫຼະ'}
for field in symptom_fields:
    base_data[field] = multi(*(o['value'] for o in fields[field]['options'][:2]))
for species_option in species:
    data = dict(base_data, animal_species=species_option['value'])
    q = next(q for q in disease_questions if data['animal_species'] in [v.strip() for v in q['condition']['value'].split(',')])
    data['suspected_disease'] = q['fields'][0]['options'][0]['value']
    if species_option.get('textInput'):
        data['animal_species_text'] = 'User supplied species'
    summary = render('renderer_data_template', {'data': data, 'incident_date': date(2026, 10, 8)})
    for expected in [data['animal_species'], data['suspected_disease'], 'ສັດແຮກເກີດ, ສັດໂຕເຕັມໄວ',
                     'ເພດຜູ້, ເພດແມ່', 'ປ່ວຍ 2', 'ຕາຍ 0', 'ຫາຍປ່ວຍ 1', 'ທັງໝົດ 20',
                     'ຜົນກະທົບ 3', '08/10/2026', data['unknown_symptoms']]:
        assert expected in summary, (expected, summary)
    for field in symptom_fields:
        assert data[field]['value'] in summary
    if data.get('animal_species_text'):
        assert data['animal_species_text'] in summary
    else:
        # Existing source acronyms (for example -PRRS) are retained; no forced removal.
        expected_ascii = set(re.findall('[A-Za-z]+', data['suspected_disease']))
        assert set(re.findall('[A-Za-z]+', summary)) <= expected_ascii, summary
    followup = render('renderer_followup_data_template', {'data': {'num_sick': 1, 'num_dead': 0, 'num_recover': 2,
                       'num_total_animal': 0, 'num_household': 0}, 'incident_data': data})
    for expected in [data['animal_species'], 'ປ່ວຍ 1', 'ຕາຍ 0', 'ຫາຍປ່ວຍ 2', 'ທັງໝົດ 0', 'ຜົນກະທົບ 0']:
        assert expected in followup
    if data.get('animal_species_text'):
        assert data['animal_species_text'] in followup
# Every disease value, including the authoritative PRRS acronym, survives interpolation.
for question in disease_questions:
    for option in question['fields'][0]['options']:
        data = dict(base_data, animal_species=question['condition']['value'].split(',')[0].strip(),
                    suspected_disease=option['value'])
        summary = render('renderer_data_template', {'data': data, 'incident_date': date(2026, 10, 8)})
        assert option['value'] in summary
zero = render('renderer_data_template', {'data': {'num_sick': 0, 'num_dead': 0, 'num_recover': 0,
              'num_total_animal': 0, 'num_household': 0}, 'incident_date': date(2026, 10, 8)})
for expected in ['ປ່ວຍ 0', 'ຕາຍ 0', 'ຫາຍປ່ວຍ 0', 'ທັງໝົດ 0', 'ຜົນກະທົບ 0', '08/10/2026']:
    assert expected in zero
print('PASS:', len(actual), 'property changes; latest definitions EXACTLY preserved;', options_checked,
      'choice occurrences; 11 species/7 conditions; initial + followup templates; multi-select, Other, free text, zero, date')
print('NOT VERIFIED: Lao linguistic acceptance; database apply/idempotence; mobile/web UI/sync; API export consumers')
